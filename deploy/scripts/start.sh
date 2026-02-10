#!/usr/bin/env bash
# Exit on error, undefined variables, or failed pipes for safety.
set -euo pipefail
# Blank line for readability between setup sections.

# Explain that ENV can be "prod" or "dev" to select config paths.
# Environment: prod or dev (must match platform module SSM paths and CI)
# Explain this is the simple default approach in CI.
# Option A: hardcode for single-env (e.g. prod only from CI)
# Prefer the instance env file written by user data, then ENV var.
# Fail fast if neither is present to avoid pulling the wrong env tag.
if [[ -f /opt/bluegreen-env ]]; then
  ENV="$(tr -d '[:space:]' < /opt/bluegreen-env)"
elif [[ -n "${ENV:-}" ]]; then
  ENV="$ENV"
else
  echo "ERROR: ENV not set and /opt/bluegreen-env missing; cannot choose SSM paths." >&2
  exit 1
fi
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
if [[ -z "$IMAGE_TAG" || "$IMAGE_TAG" == "initial" || "$IMAGE_TAG" == "unset" ]]; then
  echo "ERROR: image_tag is not set to a real image tag in SSM (/bluegreen/${ENV}/image_tag)." >&2
  exit 1
fi
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