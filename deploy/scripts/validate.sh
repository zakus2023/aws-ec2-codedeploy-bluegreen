#!/usr/bin/env bash
set -euo pipefail

# Give the app a moment to bind to port 8080
sleep 3

STATUS="$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health || true)"
if [[ "$STATUS" != "200" ]]; then
  echo "Health check failed, status=$STATUS"
  exit 1
fi

echo "ValidateService OK"