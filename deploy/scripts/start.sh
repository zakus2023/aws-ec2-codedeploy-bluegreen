#!/usr/bin/env bash
# Exit on error, undefined variables, or failed pipes for safety.
set -euo pipefail
# Blank line for readability between setup sections.

# Explain that ENV can be "prod" or "dev" to select config paths.
# Environment: prod or dev (must match platform module SSM paths and CI)
# Explain this is the simple default approach in CI.
# Option A: hardcode for single-env (e.g. prod only from CI)
# Use ENV if set, otherwise default to "prod".
ENV="${ENV:-prod}"
# Blank line for readability between options.

# Explain the alternate option uses a file from user data.
# Option B: read from a file written by user data (if you set it in launch template)
# Example of reading that file or falling back to prod.
# ENV="$(cat /opt/bluegreen-env 2>/dev/null || echo prod)"
# Blank line for readability between metadata lookups.

# Query EC2 metadata to get the instance region.
REGION="$(curl -s http://169.254.169.254/latest/meta-data/placement/region)"
# Ask AWS STS for the numeric AWS account ID.
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
# Blank line for readability before SSM lookups.

# Explain which SSM parameter paths are used for repo and tag.
# SSM paths match platform module: /bluegreen/{env}/ecr_repo_name and /bluegreen/{env}/image_tag
# Read the ECR repository name from SSM in this region.
ECR_REPO_NAME="$(aws ssm get-parameter --name "/bluegreen/${ENV}/ecr_repo_name" --region "$REGION" --query Parameter.Value --output text)"
# Read the image tag from SSM in this region.
IMAGE_TAG="$(aws ssm get-parameter --name "/bluegreen/${ENV}/image_tag" --region "$REGION" --query Parameter.Value --output text)"
# Blank line for readability before building the image URI.

# Build the full ECR image URI (account/region/repo:tag).
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO_NAME}:${IMAGE_TAG}"
# Blank line for readability before login.

# Get an auth token and pipe it into docker login.
aws ecr get-login-password --region "$REGION" | \
  # Log Docker into the ECR registry for this account/region.
  docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
# Blank line for readability before pulling the image.

# Download the container image from ECR.
docker pull "$ECR_URI"
# Blank line for readability before running the container.

# Run the container in the background (detached mode).
docker run -d \
  # Name the running container "sample-app".
  --name sample-app \
  # Map host port 8080 to container port 8080.
  -p 8080:8080 \
  # Provide the image tag as the APP_VERSION env var.
  -e APP_VERSION="$IMAGE_TAG" \
  # Ensure Docker restarts the container on failures/reboots.
  --restart always \
  # Use the image URI we built above.
  "$ECR_URI"