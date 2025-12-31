#!/bin/bash

# =============================================================================
# FaltuBaat Multi-Container ECS Deployment Script
# =============================================================================

set -e

# Configuration - UPDATE THESE VALUES
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-YOUR_ACCOUNT_ID}"
CLUSTER_NAME="faltubaat-cluster"
SERVICE_NAME="faltubaat-multi-service"

echo "🚀 Deploying FaltuBaat Multi-Container to ECS..."

# Navigate to project root
cd "$(dirname "$0")/../../.."

# 1. Login to ECR
echo "📦 Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# 2. Build Docker images
echo "🔨 Building Docker images..."

# Build chat-app image
echo "  Building chat-app..."
docker build -t faltubaat-app -f deploy/docker/multi-container/Dockerfile.app .

# Build nginx-rtmp image
echo "  Building nginx-rtmp..."
docker build -t faltubaat-nginx-rtmp -f deploy/docker/multi-container/Dockerfile.nginx-rtmp deploy/docker/multi-container/

# 3. Tag images for ECR
echo "🏷️ Tagging images..."
docker tag faltubaat-app:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/faltubaat-app:latest
docker tag faltubaat-nginx-rtmp:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/faltubaat-nginx-rtmp:latest

# 4. Push to ECR
echo "⬆️ Pushing to ECR..."
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/faltubaat-app:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/faltubaat-nginx-rtmp:latest

# 5. Register new task definition
echo "📝 Registering task definition..."
aws ecs register-task-definition \
    --cli-input-json file://deploy/ecs/multi-container/task-definition.json \
    --region $AWS_REGION

# 6. Update service to use new task definition
echo "🔄 Updating ECS service..."
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service $SERVICE_NAME \
    --task-definition faltubaat-multi \
    --force-new-deployment \
    --region $AWS_REGION

echo ""
echo "✅ Multi-container deployment initiated successfully!"
echo ""
echo "🐳 Containers deployed:"
echo "  chat-app      → Node.js Chat Application"
echo "  nginx-rtmp    → Nginx RTMP/HLS Streaming"
echo ""
echo "📊 Monitor deployment:"
echo "  aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $AWS_REGION"
echo ""
echo "📋 View logs:"
echo "  Chat App:   aws logs tail /ecs/faltubaat/chat-app --follow --region $AWS_REGION"
echo "  Nginx RTMP: aws logs tail /ecs/faltubaat/nginx-rtmp --follow --region $AWS_REGION"
