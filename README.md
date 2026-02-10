# CICD-With-AI (AWS EC2 Blue/Green)

Blue/green deployment for a Node.js app on AWS EC2: Terraform (bootstrap + platform + dev/prod), Docker + ECR, and either **Ansible over SSM** or **CodeDeploy** for deploy.

## Quick links

- **RUN_COMMANDS_ORDER.md** — Exact command order: bootstrap → dev/prod → **OIDC + GitHub Actions (§3a)** → build+push → deploy (Ansible or CodeDeploy) → validate; destroy order; EC2 user data reference.
- **IMPLEMENT_AWS_EC2_BLUEGREEN.md** — Full step-by-step implementation guide (app, deploy bundle, Terraform, Ansible alternative, GitHub Actions, CrewAI).
- **ansible/README.md** — Ansible deploy over SSM (setup, install, run playbooks). On Windows: **WSL** (step-by-step for beginners in that file) or **Ansible 2.13** workaround in PowerShell (native Windows not supported in 2.14+).

## Deploy options

1. **Ansible (recommended)** — Over SSM; no CodeDeploy agent required for deploy. Follow **RUN_COMMANDS_ORDER.md** §5a step-by-step (Steps 5.1–5.4: venv, config, get S3 bucket from Terraform, run playbook with `-e ssm_bucket=...`; for **prod** add `-e env=prod`). Full details in **ansible/README.md**.
2. **CodeDeploy** — Bundle in S3 + create deployment. See **RUN_COMMANDS_ORDER.md** §5b.
