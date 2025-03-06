#!/bin/bash

# Exit on error
set -e

# AWS Configuration
AWS_REGION="us-west-2"  # Change this to your region
CLUSTER_NAME="polyglot-cluster"

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

# Function to drain and delete ECS services
drain_ecs_services() {
    log "INFO" "Starting service drain process..."
    
    services=("nodejs-service" "python-service")
    
    for service in "${services[@]}"; do
        if aws ecs describe-services \
            --cluster ${CLUSTER_NAME} \
            --services ${service} \
            --query 'services[0].status' \
            --output text 2>/dev/null | grep -q ACTIVE; then
            
            log "INFO" "Draining service: ${service}"
            
            # Update service to 0 count
            aws ecs update-service \
                --cluster ${CLUSTER_NAME} \
                --service ${service} \
                --desired-count 0 > /dev/null
                
            log "INFO" "Waiting for ${service} tasks to drain..."
            aws ecs wait services-stable \
                --cluster ${CLUSTER_NAME} \
                --services ${service}
            
            log "INFO" "Deleting service: ${service}"
            aws ecs delete-service \
                --cluster ${CLUSTER_NAME} \
                --service ${service} \
                --force > /dev/null || true
        else
            log "INFO" "Service not found or already deleted: ${service}"
        fi
    done
    
    # Wait for services to be fully deleted
    log "INFO" "Waiting for services to be fully deleted..."
    sleep 30
    
    log "INFO" "Service drain and deletion completed"
}

# Main function
main() {
    log "INFO" "Starting service drain process..."
    drain_ecs_services
    log "INFO" "All services have been drained and deleted"
    log "INFO" "You can now run deploy-all.sh for a fresh deployment"
}

# Run main function
main
