#!/usr/bin/env bash
set -euo pipefail

# Stop and remove old container if it exists
if docker ps -a --format '{{.Names}}' | grep -q '^sample-app$'; then
  docker rm -f sample-app || true
fi