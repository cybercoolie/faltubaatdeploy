#!/bin/bash

# =============================================================================
# FaltuBaat Single-Container ECS Deployment Script
# =============================================================================

set -e

# Configuration - UPDATE THESE VALUES
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-YOUR_ACCOUNT_ID}"
ECR_REPO="faltubaat-single"
CLUSTER_NAME="faltubaat-cluster"
SERVICE_NAME="faltubaat-single-service"

echo "🚀 Deploying FaltuBaat Single-Container to ECS..."

# Navigate to project root
cd "$(dirname "$0")/../../.."

# 1. Login to ECR
echo "📦 Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# 2. Build Docker image
echo "🔨 Building Docker image..."
docker build -t $ECR_REPO -f deploy/docker/single-container/Dockerfile .

# 3. Tag image for ECR
echo "🏷️ Tagging image..."
docker tag $ECR_REPO:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:latest

# 4. Push to ECR
echo "⬆️ Pushing to ECR..."
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:latest

# 5. Register new task definition
echo "📝 Registering task definition..."
aws ecs register-task-definition \
    --cli-input-json file://deploy/ecs/single-container/task-definition.json \
    --region $AWS_REGION

# 6. Update service to use new task definition
echo "🔄 Updating ECS service..."
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service $SERVICE_NAME \
    --task-definition $ECR_REPO \
    --force-new-deployment \
    --region $AWS_REGION

echo ""
echo "✅ Deployment initiated successfully!"
echo ""
echo "📊 Monitor deployment:"
echo "  aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $AWS_REGION"
echo ""
echo "📋 View logs:"
echo "  aws logs tail /ecs/faltubaat-single --follow --region $AWS_REGION"
