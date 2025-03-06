#!/bin/bash

# Exit on error
set -e

# AWS Configuration
AWS_REGION="us-west-2"  # Change this to your region
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

# Infrastructure Configuration
VPC_CIDR="10.0.0.0/16"
CLUSTER_NAME="polyglot-cluster"

# ECR Repository Names
ECR_REPO_PREFIX="multiarch-polyglot"
NODEJS_REPO_NAME="${ECR_REPO_PREFIX}-nodejs"
PYTHON_REPO_NAME="${ECR_REPO_PREFIX}-python"

# Full ECR Repository URIs
NODEJS_ECR_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${NODEJS_REPO_NAME}"
PYTHON_ECR_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PYTHON_REPO_NAME}"

# Version/Tag Management
VERSION=$(git describe --tags --always 2>/dev/null || echo "v1.0.0")
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
TAG="${VERSION}-${TIMESTAMP}"

# Variables for network resources
VPC_ID=""
SUBNET_1_ID=""
SUBNET_2_ID=""
SG_ID=""
EXECUTION_ROLE_ARN=""
ALB_ARN=""
NODEJS_TG_ARN=""
PYTHON_TG_ARN=""
ALB_DNS=""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message=$@
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    case $level in
        "INFO") echo -e "${GREEN}[INFO]${NC} ${timestamp} - $message" ;;
        "WARN") echo -e "${YELLOW}[WARN]${NC} ${timestamp} - $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} ${timestamp} - $message" ;;
    esac
}

# Initialize script
init_script() {
    log "INFO" "Initializing deployment script..."
    
    # Verify AWS credentials
    if ! AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null); then
        log "ERROR" "Failed to get AWS account ID. Please check AWS credentials."
        exit 1
    fi
    log "INFO" "Using AWS Region: ${AWS_REGION}"
    
    # Verify required commands
    for cmd in aws docker; do
        if ! command -v $cmd &> /dev/null; then
            log "ERROR" "Required command not found: $cmd"
            exit 1
        fi
    done
    
    log "INFO" "Initialization completed"
}

# Error handler
handle_error() {
    log "ERROR" "An error occurred on line $1"
    cleanup
    exit 1
}

# Cleanup function
cleanup() {
    log "INFO" "Cleaning up resources..."
    docker buildx rm multiarch-builder 2>/dev/null || true
}

# Set up error handling
trap 'handle_error $LINENO' ERR

# Create VPC and networking
create_vpc_if_needed() {
    log "INFO" "Setting up VPC and networking..."
    
    # Check existing VPC
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=cidr,Values=${VPC_CIDR}" \
        --query 'Vpcs[0].VpcId' \
        --output text 2>/dev/null)
    
    if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
        log "INFO" "Creating new VPC..."
        
        # Create VPC
        VPC_ID=$(aws ec2 create-vpc \
            --cidr-block ${VPC_CIDR} \
            --query 'Vpc.VpcId' \
            --output text 2>/dev/null)
        
        aws ec2 modify-vpc-attribute \
            --vpc-id ${VPC_ID} \
            --enable-dns-hostnames "{\"Value\":true}" > /dev/null
        
        # Get available AZs
        AZS=($(aws ec2 describe-availability-zones \
            --region ${AWS_REGION} \
            --query 'AvailabilityZones[?State==`available`].ZoneName' \
            --output text))
        
        # Create subnets
        log "INFO" "Creating subnets..."
        SUBNET_1_ID=$(aws ec2 create-subnet \
            --vpc-id ${VPC_ID} \
            --cidr-block "10.0.1.0/24" \
            --availability-zone "${AZS[0]}" \
            --query 'Subnet.SubnetId' \
            --output text 2>/dev/null)
        
        SUBNET_2_ID=$(aws ec2 create-subnet \
            --vpc-id ${VPC_ID} \
            --cidr-block "10.0.2.0/24" \
            --availability-zone "${AZS[1]}" \
            --query 'Subnet.SubnetId' \
            --output text 2>/dev/null)
        
        # Enable auto-assign public IP
        aws ec2 modify-subnet-attribute \
            --subnet-id ${SUBNET_1_ID} \
            --map-public-ip-on-launch > /dev/null
        
        aws ec2 modify-subnet-attribute \
            --subnet-id ${SUBNET_2_ID} \
            --map-public-ip-on-launch > /dev/null
        
        # Create Internet Gateway
        IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text 2>/dev/null)
        aws ec2 attach-internet-gateway --vpc-id ${VPC_ID} --internet-gateway-id ${IGW_ID} > /dev/null
        
        # Create Route Table
        ROUTE_TABLE_ID=$(aws ec2 create-route-table --vpc-id ${VPC_ID} --query 'RouteTable.RouteTableId' --output text 2>/dev/null)
        aws ec2 create-route --route-table-id ${ROUTE_TABLE_ID} --destination-cidr-block 0.0.0.0/0 --gateway-id ${IGW_ID} > /dev/null
        aws ec2 associate-route-table --subnet-id ${SUBNET_1_ID} --route-table-id ${ROUTE_TABLE_ID} > /dev/null
        aws ec2 associate-route-table --subnet-id ${SUBNET_2_ID} --route-table-id ${ROUTE_TABLE_ID} > /dev/null
        
        log "INFO" "Waiting for network resources to be available..."
        sleep 15
    else
        log "INFO" "Using existing VPC: ${VPC_ID}"
        
        # Get existing subnets
        SUBNET_IDS=($(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=${VPC_ID}" \
            --query 'Subnets[?MapPublicIpOnLaunch==`true`].SubnetId' \
            --output text))
        
        if [ ${#SUBNET_IDS[@]} -ge 2 ]; then
            SUBNET_1_ID=${SUBNET_IDS[0]}
            SUBNET_2_ID=${SUBNET_IDS[1]}
        else
            log "ERROR" "Not enough public subnets found in VPC"
            return 1
        fi
    fi
    
    log "INFO" "Network setup completed"
    return 0
}

# Create Security Group
create_security_group() {
    log "INFO" "Setting up security groups..."
    
    SG_NAME="${CLUSTER_NAME}-ecs-sg"
    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${SG_NAME}" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null)
    
    if [ "$SG_ID" == "None" ] || [ -z "$SG_ID" ]; then
        log "INFO" "Creating security group..."
        SG_ID=$(aws ec2 create-security-group \
            --group-name ${SG_NAME} \
            --description "Security group for ${CLUSTER_NAME}" \
            --vpc-id ${VPC_ID} \
            --query 'GroupId' \
            --output text 2>/dev/null)
            
        aws ec2 authorize-security-group-ingress \
            --group-id ${SG_ID} \
            --protocol tcp \
            --port 3000 \
            --cidr 0.0.0.0/0 > /dev/null || true
            
        aws ec2 authorize-security-group-ingress \
            --group-id ${SG_ID} \
            --protocol tcp \
            --port 5000 \
            --cidr 0.0.0.0/0 > /dev/null || true
    fi
    
    return 0
}

# Create ECR Repositories
create_ecr_repos() {
    log "INFO" "Setting up ECR repositories..."
    
    for repo in "${NODEJS_REPO_NAME}" "${PYTHON_REPO_NAME}"; do
        if ! aws ecr describe-repositories --repository-names "$repo" >/dev/null 2>&1; then
            log "INFO" "Creating repository: $repo"
            aws ecr create-repository \
                --repository-name "$repo" \
                --image-scanning-configuration scanOnPush=true \
                --region ${AWS_REGION} > /dev/null
        else
            log "INFO" "Repository already exists: $repo"
        fi
    done
    
    return 0
}

# Create Task Execution Role
create_task_execution_role() {
    log "INFO" "Setting up ECS task execution role..."
    
    ROLE_NAME="ecsTaskExecutionRole-${CLUSTER_NAME}"
    
    if ! aws iam get-role --role-name ${ROLE_NAME} >/dev/null 2>&1; then
        log "INFO" "Creating new role: ${ROLE_NAME}"
        
        # Create trust policy
        TRUST_POLICY='{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {
                    "Service": "ecs-tasks.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }]
        }'
        
        aws iam create-role \
            --role-name ${ROLE_NAME} \
            --assume-role-policy-document "${TRUST_POLICY}" > /dev/null
        
        aws iam attach-role-policy \
            --role-name ${ROLE_NAME} \
            --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy > /dev/null
        
        aws iam attach-role-policy \
            --role-name ${ROLE_NAME} \
            --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess > /dev/null
        
        log "INFO" "Waiting for role to be available..."
        sleep 10
    else
        log "INFO" "Using existing role: ${ROLE_NAME}"
    fi
    
    EXECUTION_ROLE_ARN=$(aws iam get-role --role-name ${ROLE_NAME} --query 'Role.Arn' --output text)
    return 0
}

# Create ECS Cluster
create_ecs_cluster() {
    log "INFO" "Setting up ECS cluster..."
    
    if ! aws ecs describe-clusters \
        --clusters ${CLUSTER_NAME} \
        --query 'clusters[0].status' \
        --output text 2>/dev/null | grep -q ACTIVE; then
        
        aws ecs create-cluster --cluster-name ${CLUSTER_NAME} > /dev/null
        sleep 10
    fi
    
    return 0
}

# Setup Docker buildx
setup_buildx() {
    log "INFO" "Setting up Docker buildx..."
    
    docker buildx rm multiarch-builder 2>/dev/null || true
    docker buildx create --name multiarch-builder --driver docker-container --use > /dev/null
    docker buildx inspect --bootstrap > /dev/null
    
    return 0
}

# ECR Login
ecr_login() {
    log "INFO" "Logging into Amazon ECR..."
    aws ecr get-login-password --region ${AWS_REGION} | \
        docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com > /dev/null 2>&1
    return 0
}

# Build and Push Node.js Service
build_nodejs() {
    log "INFO" "Building Node.js service for ARM64..."
    
    cd nodejs-service
    docker buildx build \
        --platform linux/arm64 \
        --tag "${NODEJS_ECR_REPO}:${TAG}" \
        --tag "${NODEJS_ECR_REPO}:latest" \
        --push \
        . > /dev/null 2>&1
    cd ..
    
    return 0
}

# Build and Push Python Service
build_python() {
    log "INFO" "Building Python service for X86_64..."
    
    cd python-service
    docker buildx build \
        --platform linux/amd64 \
        --tag "${PYTHON_ECR_REPO}:${TAG}" \
        --tag "${PYTHON_ECR_REPO}:latest" \
        --push \
        . > /dev/null 2>&1
    cd ..
    
    return 0
}

# Create Task Definitions
create_task_definitions() {
    log "INFO" "Creating task definitions..."
    
    # Node.js Task Definition
      # Node.js Task Definition
    NODEJS_TASK_DEF=$(cat <<EOF
{
    "family": "nodejs-service",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "256",
    "memory": "512",
    "executionRoleArn": "${EXECUTION_ROLE_ARN}",
    "runtimePlatform": {
        "cpuArchitecture": "ARM64",
        "operatingSystemFamily": "LINUX"
    },
    "containerDefinitions": [{
        "name": "nodejs-service-container",
        "image": "${NODEJS_ECR_REPO}:latest",
        "essential": true,
        "portMappings": [{
            "containerPort": 3000,
            "hostPort": 3000,
            "protocol": "tcp"
        }],
        "healthCheck": {
            "command": [
                "CMD-SHELL",
                "curl -f http://localhost:3000/health || exit 1"
            ],
            "interval": 30,
            "timeout": 5,
            "retries": 3,
            "startPeriod": 60
        },
        "logConfiguration": {
            "logDriver": "awslogs",
            "options": {
                "awslogs-group": "/ecs/${CLUSTER_NAME}/nodejs",
                "awslogs-region": "${AWS_REGION}",
                "awslogs-stream-prefix": "ecs",
                "awslogs-create-group": "true"
            }
        },
        "environment": [
            {
                "name": "PORT",
                "value": "3000"
            }
        ]
    }]
}
EOF
)


    # Python Task Definition
    PYTHON_TASK_DEF=$(cat <<EOF
{
    "family": "python-service",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "256",
    "memory": "512",
    "executionRoleArn": "${EXECUTION_ROLE_ARN}",
    "runtimePlatform": {
        "cpuArchitecture": "X86_64",
        "operatingSystemFamily": "LINUX"
    },
    "containerDefinitions": [{
        "name": "python-service-container",
        "image": "${PYTHON_ECR_REPO}:latest",
        "essential": true,
        "portMappings": [{
            "containerPort": 5000,
            "hostPort": 5000,
            "protocol": "tcp"
        }],
        "healthCheck": {
            "command": ["CMD-SHELL", "curl -f http://localhost:5000/health || exit 1"],
            "interval": 30,
            "timeout": 5,
            "retries": 3,
            "startPeriod": 60
        },
        "logConfiguration": {
            "logDriver": "awslogs",
            "options": {
                "awslogs-group": "/ecs/${CLUSTER_NAME}/python",
                "awslogs-region": "${AWS_REGION}",
                "awslogs-stream-prefix": "ecs",
                "awslogs-create-group": "true"
            }
        },
        "environment": [
            {
                "name": "PORT",
                "value": "5000"
            }
        ]
    }]
}
EOF
)

    # Register task definitions
    log "INFO" "Registering Node.js task definition..."
    aws ecs register-task-definition --cli-input-json "$NODEJS_TASK_DEF" > /dev/null
    
    log "INFO" "Registering Python task definition..."
    aws ecs register-task-definition --cli-input-json "$PYTHON_TASK_DEF" > /dev/null
    
    return 0
}

# Create Application Load Balancer
create_load_balancer() {
    log "INFO" "Setting up Application Load Balancer..."

    # Create ALB Security Group
    ALB_SG_NAME="${CLUSTER_NAME}-alb-sg"
    log "INFO" "Checking ALB security group..."
    
    ALB_SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${ALB_SG_NAME}" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null)

    if [ "$ALB_SG_ID" == "None" ] || [ -z "$ALB_SG_ID" ]; then
        log "INFO" "Creating ALB security group..."
        ALB_SG_ID=$(aws ec2 create-security-group \
            --group-name ${ALB_SG_NAME} \
            --description "Security group for ${CLUSTER_NAME} ALB" \
            --vpc-id ${VPC_ID} \
            --query 'GroupId' \
            --output text 2>/dev/null)

        aws ec2 authorize-security-group-ingress \
            --group-id ${ALB_SG_ID} \
            --protocol tcp \
            --port 80 \
            --cidr 0.0.0.0/0 > /dev/null
    fi

    # Create ALB
    ALB_NAME="${CLUSTER_NAME}-alb"
    if ! aws elbv2 describe-load-balancers --names ${ALB_NAME} >/dev/null 2>&1; then
        log "INFO" "Creating Application Load Balancer..."
        ALB_ARN=$(aws elbv2 create-load-balancer \
            --name ${ALB_NAME} \
            --subnets ${SUBNET_1_ID} ${SUBNET_2_ID} \
            --security-groups ${ALB_SG_ID} \
            --scheme internet-facing \
            --type application \
            --query 'LoadBalancers[0].LoadBalancerArn' \
            --output text 2>/dev/null)

        log "INFO" "Waiting for ALB to become active..."
        sleep 30
    else
        ALB_ARN=$(aws elbv2 describe-load-balancers \
            --names ${ALB_NAME} \
            --query 'LoadBalancers[0].LoadBalancerArn' \
            --output text 2>/dev/null)
    fi

    # Function to create target group
    create_target_group() {
        local name=$1
        local port=$2

        log "INFO" "Creating target group: ${name}"
        local tg_arn=$(aws elbv2 create-target-group \
            --name ${name} \
            --protocol HTTP \
            --port ${port} \
            --vpc-id ${VPC_ID} \
            --target-type ip \
            --health-check-path "/health" \
            --health-check-interval-seconds 30 \
            --health-check-timeout-seconds 5 \
            --healthy-threshold-count 2 \
            --unhealthy-threshold-count 3 \
            --query 'TargetGroups[0].TargetGroupArn' \
            --output text 2>/dev/null)

        echo "${tg_arn}"
    }

    # Create target groups and store ARNs
        # Create target groups and store ARNs
    log "INFO" "Creating Node.js target group..."
    NODEJS_TG_ARN=$(aws elbv2 create-target-group \
        --name "${CLUSTER_NAME}-nodejs" \
        --protocol HTTP \
        --port 3000 \
        --vpc-id ${VPC_ID} \
        --target-type ip \
        --health-check-enabled \
        --health-check-path "/health" \
        --health-check-protocol HTTP \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --health-check-port traffic-port \
        --matcher HttpCode=200 \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null)

    
    
    log "INFO" "Creating Python target group..."
    PYTHON_TG_ARN=$(aws elbv2 create-target-group \
        --name "${CLUSTER_NAME}-python" \
        --protocol HTTP \
        --port 5000 \
        --vpc-id ${VPC_ID} \
        --target-type ip \
        --health-check-enabled \
        --health-check-path "/health" \
        --health-check-protocol HTTP \
        --health-check-port traffic-port \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --matcher HttpCode=200 \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null)


    # Create listener
    log "INFO" "Creating ALB listener..."
    LISTENER_ARN=$(aws elbv2 create-listener \
        --load-balancer-arn "${ALB_ARN}" \
        --protocol HTTP \
        --port 80 \
        --default-actions "[{\"Type\":\"forward\",\"TargetGroupArn\":\"${NODEJS_TG_ARN}\"}]" \
        --query 'Listeners[0].ListenerArn' \
        --output text 2>/dev/null)

    # Create rule for Python service
    log "INFO" "Creating rule for Python service..."
    ACTION="[{\"Type\":\"forward\",\"TargetGroupArn\":\"${PYTHON_TG_ARN}\"}]"
    CONDITION='[{"Field":"path-pattern","Values":["/api"]}]'
    
      # Create rule for Python service
    log "INFO" "Creating rule for Python service..."
    aws elbv2 create-rule \
        --listener-arn "${LISTENER_ARN}" \
        --priority 10 \
        --conditions '[{"Field":"path-pattern","Values":["/api"]}]' \
        --actions "[{\"Type\":\"forward\",\"TargetGroupArn\":\"${PYTHON_TG_ARN}\"}]" > /dev/null


    # Get ALB DNS name
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "${ALB_ARN}" \
        --query 'LoadBalancers[0].DNSName' \
        --output text 2>/dev/null)

    log "INFO" "Load balancer setup completed"
    return 0
}

# Deploy ECS Services
deploy_services() {
    log "INFO" "Deploying ECS services..."

    deploy_single_service() {
        local service_name=$1
        local task_family=$2
        local container_port=$3
        local target_group_arn=$4
        local container_name="${service_name}-container"
        
        # Delete existing service if it exists
        if aws ecs describe-services \
            --cluster ${CLUSTER_NAME} \
            --services ${service_name} \
            --query 'services[0].status' \
            --output text 2>/dev/null | grep -q ACTIVE; then
            
            log "INFO" "Deleting existing service: ${service_name}"
            aws ecs delete-service \
                --cluster ${CLUSTER_NAME} \
                --service ${service_name} \
                --force > /dev/null
            
            log "INFO" "Waiting for service to be deleted..."
            sleep 30
        fi
            
        log "INFO" "Creating new service: ${service_name}"
        # In the deploy_single_service function, update the create-service command
        aws ecs create-service \
            --cluster ${CLUSTER_NAME} \
            --service-name ${service_name} \
            --task-definition ${task_family} \
            --desired-count 1 \
            --launch-type FARGATE \
            --network-configuration "awsvpcConfiguration={subnets=[\"${SUBNET_1_ID}\",\"${SUBNET_2_ID}\"],securityGroups=[\"${SG_ID}\"],assignPublicIp=ENABLED}" \
            --load-balancers "[{\"targetGroupArn\":\"${target_group_arn}\",\"containerName\":\"${container_name}\",\"containerPort\":${container_port}}]" \
            --health-check-grace-period-seconds 120 > /dev/null


        log "INFO" "Waiting for service ${service_name} to become stable..."
        aws ecs wait services-stable \
            --cluster ${CLUSTER_NAME} \
            --services ${service_name} 2>/dev/null
    }

    # Deploy both services
    deploy_single_service "nodejs-service" "nodejs-service" 3000 "${NODEJS_TG_ARN}"
    deploy_single_service "python-service" "python-service" 5000 "${PYTHON_TG_ARN}"
    
    return 0
}

check_container_health() {
    local service_name=$1
    
    # Get task ARN
    TASK_ARN=$(aws ecs list-tasks \
        --cluster ${CLUSTER_NAME} \
        --service-name ${service_name} \
        --query 'taskArns[0]' \
        --output text)
    
    if [ -n "$TASK_ARN" ]; then
        # Get task details
        aws ecs describe-tasks \
            --cluster ${CLUSTER_NAME} \
            --tasks ${TASK_ARN}
        
        # Get logs
        TASK_ID=$(echo $TASK_ARN | awk -F/ '{print $3}')
        aws logs get-log-events \
            --log-group "/ecs/${CLUSTER_NAME}/nodejs" \
            --log-stream "ecs/nodejs-service-container/${TASK_ID}"
    fi
}


# Main function
main() {
    log "INFO" "Starting deployment process..."
    
    # Initialize
    init_script
    
    # Infrastructure setup
    create_vpc_if_needed || { log "ERROR" "VPC creation failed"; exit 1; }
    create_security_group || { log "ERROR" "Security group creation failed"; exit 1; }
    create_ecr_repos || { log "ERROR" "ECR repository creation failed"; exit 1; }
    create_task_execution_role || { log "ERROR" "Task execution role creation failed"; exit 1; }
    create_ecs_cluster || { log "ERROR" "ECS cluster creation failed"; exit 1; }
    
    # Application deployment
    setup_buildx || { log "ERROR" "Docker buildx setup failed"; exit 1; }
    ecr_login || { log "ERROR" "ECR login failed"; exit 1; }
    build_nodejs || { log "ERROR" "Node.js build failed"; exit 1; }
    build_python || { log "ERROR" "Python build failed"; exit 1; }
    
    # Create and deploy services
    create_task_definitions || { log "ERROR" "Task definition creation failed"; exit 1; }
    create_load_balancer || { log "ERROR" "Load balancer creation failed"; exit 1; }
    deploy_services || { log "ERROR" "Service deployment failed"; exit 1; }
    
    log "INFO" "Deployment completed successfully!"
    log "INFO" "Application can be accessed at: http://${ALB_DNS}"
    log "INFO" "API endpoint: http://${ALB_DNS}/api"
}

# Run main function
main
