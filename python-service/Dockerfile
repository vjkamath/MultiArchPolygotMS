FROM --platform=$TARGETPLATFORM python:3.9-slim

# Install curl for health checks
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements first (better caching)
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application
COPY src /app/src/

# Show directory contents for debugging
RUN ls -la /app/src/

# Expose port
EXPOSE 5000

# Set environment variable
ENV PORT=5000

# Start application
CMD ["python", "/app/src/app.py"]
