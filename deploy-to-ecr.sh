#!/bin/bash
# Deploy VarFish to Amazon ECR for App Runner
set -euo pipefail

# Configuration - UPDATE THESE VALUES
AWS_REGION="us-east-2"  # Changed to match your configured region
ECR_REPO_NAME="varfish-server"
IMAGE_TAG="latest"

echo "=== Building and pushing VarFish to Amazon ECR ==="

# 1. Create ECR repository (if it doesn't exist)
echo "Creating ECR repository..."
aws ecr create-repository \
    --repository-name "$ECR_REPO_NAME" \
    --region "$AWS_REGION" \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256 \
    || echo "Repository may already exist"

# 2. Get login token and authenticate Docker
echo "Logging into ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin \
    "$(aws sts get-caller-identity --query Account --output text).dkr.ecr.$AWS_REGION.amazonaws.com"

# 3. Build the image
echo "Building Docker image..."
docker build -f Dockerfile.apprunner -t "$ECR_REPO_NAME:$IMAGE_TAG" .

# 4. Tag for ECR
ECR_URI="$(aws sts get-caller-identity --query Account --output text).dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO_NAME:$IMAGE_TAG"
echo "Tagging image: $ECR_URI"
docker tag "$ECR_REPO_NAME:$IMAGE_TAG" "$ECR_URI"

# 5. Push to ECR
echo "Pushing to ECR..."
docker push "$ECR_URI"

echo "=== SUCCESS ==="
echo "Container image URI for App Runner:"
echo "$ECR_URI"
echo ""
echo "Next steps:"
echo "1. Go to AWS App Runner console"
echo "2. Create new service"
echo "3. Use Container image URI: $ECR_URI"
echo "4. Set environment variables (see .env.apprunner)"
