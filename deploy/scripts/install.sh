#!/usr/bin/env bash
set -euo pipefail

# Ensure Docker is running
systemctl enable docker || true
systemctl start docker || true

# Ensure AWS CLI exists (for ECR login and SSM in start.sh)
if ! command -v aws >/dev/null 2>&1; then
  yum install -y awscli
fi

# Target directory for the bundle (must match appspec files.destination)
mkdir -p /opt/codedeploy-bluegreen