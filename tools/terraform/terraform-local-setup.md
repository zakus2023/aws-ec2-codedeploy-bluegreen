# Installing Terraform Inside Your Project Folder (Portable Setup)

This guide explains how to install and use Terraform **inside your project folder** so it works in Git Bash, Cursor, VS Code, and CI environments without a system-wide install.

---

## ✅ Prerequisites

You should have:

- Windows 10/11  
- Git Bash (MINGW64) installed  
- A project folder (e.g. `CICD-With-AI`)

---

## 📌 Step 1 — Navigate to your project

Open **Git Bash** and go to your project root:

```bash
cd /c/My-Projects/CICD-With-AI

mkdir -p tools/terraform

curl -L -o tools/terraform/terraform.zip \
https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_windows_amd64.zip

unzip -o tools/terraform/terraform.zip -d tools/terraform


rm -f tools/terraform/terraform.zip

you should have this: 
tools/terraform/terraform.exe

ls -la tools/terraform


You can already run Terraform like this:

tools/terraform/terraform.exe -version


Expected output:

Terraform v1.6.6
on windows_amd64

📌 Step 5 — Add Terraform to PATH (for this terminal session)
export PATH="$PWD/tools/terraform:$PATH"
hash -r


Now test:

terraform -version

📌 Step 6 — Make it persistent for this project (setup.sh)

Create a helper script in your project root:

cat > setup.sh <<'EOF'
#!/usr/bin/env bash
export PATH="$(pwd)/tools/terraform:$PATH"
hash -r 2>/dev/null || true
echo "Terraform added to PATH for this project"
terraform -version || terraform.exe -version
EOF


Make it executable:

chmod +x setup.sh


Use it anytime:

./setup.sh

📌 Step 7 — Using Terraform in Cursor / VS Code

Open Cursor terminal in your project

Run:

./setup.sh
terraform -version


Terraform will now work inside Cursor.