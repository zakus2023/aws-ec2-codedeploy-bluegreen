#!/usr/bin/env bash
export PATH="$(pwd)/tools/terraform:$PATH"
hash -r 2>/dev/null || true
echo "Terraform added to PATH for this project"
terraform -version || terraform.exe -version
