# Run Commands in Order (Create + Destroy)

This guide shows the **exact command order** and **where to run each command from**.

## 1) Bootstrap (run once)

**From:** repo root `C:\My-Projects\CICD-With-AI`
```bash
cd infra/bootstrap
terraform init
terraform apply -auto-approve
```

## 2) Dev environment

**From:** repo root
```bash
cd infra/envs/dev
terraform init -backend-config=backend.hcl -reconfigure
# If you see "provider ... required by this configuration but no version is selected", run:
# terraform init -upgrade
terraform apply -auto-approve -var-file=dev.tfvars
```

## 3) Prod environment

**From:** repo root
```bash
cd infra/envs/prod
terraform init -backend-config=backend.hcl -reconfigure
# If lock file is inconsistent (e.g. null provider missing): terraform init -upgrade
terraform apply -auto-approve -var-file=prod.tfvars
```

---

## 3a) OIDC and GitHub Actions (one-time setup)

**What this is for:** Let GitHub Actions run Terraform and build/push Docker images **without storing AWS keys** in the repo. AWS trusts GitHub via **OIDC** (OpenID Connect): when a workflow runs, GitHub gives it a short-lived token; your workflow uses that token to assume an **IAM role** in your AWS account. You do this once per repo.

**When to do this:** After you have applied **bootstrap**, **dev**, and **prod** (sections 1–3). Then follow the steps below in order.

**Run all commands below in bash** (WSL, Git Bash, or Linux/macOS terminal). Ensure AWS credentials are configured (e.g. `aws sts get-caller-identity` works).

---

### Step 3a.1 — Apply the OIDC Terraform (creates the IAM role in AWS)

This creates in AWS: (1) an **OIDC identity provider** for GitHub, and (2) an **IAM role** that only your GitHub repo can assume. The role has permissions for Terraform (S3, DynamoDB, EC2, ALB, etc.), ECR, SSM, and CodeDeploy.

**From:** repo root, in **bash**.

**Option A — Copy-paste all OIDC commands in bash (one block)**

Replace `YOUR_GITHUB_ORG` with your GitHub username or org (e.g. `zak20`). Replace `YOUR_REPO_NAME` with the repo name (e.g. `CICD-With-AI`). Run from the repo root:

```bash
cd infra/oidc
terraform init
terraform apply -auto-approve -var="github_org=YOUR_GITHUB_ORG" -var="github_repo=YOUR_REPO_NAME"
```

Example (repo `zak20/CICD-With-AI`):

```bash
cd infra/oidc
terraform init
terraform apply -auto-approve -var="github_org=zak20" -var="github_repo=CICD-With-AI"
```

**Option B — Run step by step in bash**

1. From repo root: `cd infra/oidc`
2. `terraform init`
3. `terraform apply -auto-approve -var="github_org=YOUR_GITHUB_ORG" -var="github_repo=YOUR_REPO_NAME"`

After apply, Terraform prints an output like:

```text
role_arn = "arn:aws:iam::058264482067:role/github-actions-bluegreen"
```

**Copy this entire ARN** (including `arn:aws:iam::...`). You will paste it into a GitHub secret in the next step.

---

### Step 3a.2 — Add GitHub repository secrets (browser only)

GitHub Actions will use two **secrets** to connect to AWS: the role ARN and the region. There is **no bash command** for this step — you add secrets in the GitHub website.

1. Open your repo on **GitHub.com** (e.g. `https://github.com/zak20/CICD-With-AI`).
2. Click **Settings** (top menu of the repo).
3. In the left sidebar, click **Secrets and variables → Actions** (under "Security").
4. Click **New repository secret**.
5. Add the first secret:
   - **Name:** `AWS_ROLE_TO_ASSUME`
   - **Value:** the **role_arn** you copied from Step 3a.1 (e.g. `arn:aws:iam::058264482067:role/github-actions-bluegreen`).  
   Click **Add secret**.
6. Add the second secret:
   - Click **New repository secret** again.
   - **Name:** `AWS_REGION`
   - **Value:** `us-east-1` (or your AWS region).  
   Click **Add secret**.

You should now see **AWS_ROLE_TO_ASSUME** and **AWS_REGION** under Repository secrets. Do not share these or commit them; only GitHub Actions will use them.

---

### Step 3a.3 — Workflow files (already in the repo)

This repo includes five workflow files under `.github/workflows/`:

| File | When it runs | What it does |
|------|----------------|--------------|
| **terraform-plan.yml** | On every **pull request** that changes `infra/**` | Runs `terraform plan` for prod (no apply). Lets you review infra changes before merge. |
| **terraform-apply.yml** | On **push to main** when `infra/**` changes | Runs `terraform apply` for **prod**. Uses GitHub environment `production` if you create it (Step 3a.4). |
| **build-push.yml** | On **push to main** when `app/**` changes | Builds the Docker image from `app/`, pushes to **prod** ECR, and updates the SSM parameter `/bluegreen/prod/image_tag`. |
| **deploy.yml** | **After** "Build and Push Image" succeeds | **CodeDeploy path:** packages `deploy/`, uploads to S3, triggers **CodeDeploy** for prod. |
| **deploy-ansible.yml** | **After** "Build and Push Image" succeeds | **Ansible path:** runs `ansible-playbook` over SSM to prod EC2 (same as section 5a, but in CI). No CodeDeploy agent required. |

**Deploy:** You get **both** deploy workflows. After each successful build-push, **Deploy (CodeDeploy)** and **Deploy (Ansible)** both run. Use one or both depending on how you want to roll out (CodeDeploy blue/green vs Ansible over SSM). You can disable one in the repo **Settings → Actions → General** if you only want one.

You do **not** need to create these files; they are already in the repo. After you add the secrets (Step 3a.2), the next push or PR will trigger the right workflow.

---

### Step 3a.4 — Optional: Create GitHub environment "production" and protection rules

The **Terraform Apply** workflow uses `environment: production`. You can create this environment and optionally restrict which branches can deploy to it, or require someone to approve each run.

**Where to go:** Repo on GitHub → **Settings** (top bar) → under **Code and automation** click **Environments**.

---

**Create the environment**

1. Click **New environment** (if you don’t have one yet).
2. Name it **production** and click **Configure environment**. You’ll see **Environments / Configure production**.

---

**Deployment branches and tags (protection rules)**

This controls **which branches or tags** can deploy to the `production` environment.

- **Deployment branches and tags** — In "Configure production", find the section **"Limit which branches and tags can deploy to this environment..."** and the dropdown (default: **No restriction**).

  - **No restriction** — Any branch or tag can deploy. Easiest; no extra setup.
  - **Protected branches only** — Only branches that have **branch protection rules** can deploy. If you choose this, you must add a rule for the branch you use (e.g. `main`). Otherwise GitHub will show: *"No repository branch protection rules set: all branches are still allowed to deploy."*
  - **Selected branches and tags** — You choose exactly which branches/tags (e.g. only `main`). No branch protection needed.

**If you chose "Protected branches only"** — Add a branch protection rule or ruleset so that `main` (or your deploy branch) is protected:

- **Option A — Rulesets (newer UI):** **Settings → Code and automation → Rules** → **Rulesets** → **New ruleset**. Give it a name, set **Target branches** to e.g. `main`, then enable rules (e.g. **Restrict deletions**, **Block force pushes**, or **Require a pull request before merging**). Save.
- **Option B — Branch protection rule:** **Settings → Code and automation → Branches** → **Add branch protection rule**. In **Branch name pattern** enter `main` (or `*` for all). Enable at least one option (e.g. **Require a pull request before merging** or **Do not allow bypassing the above settings**). Click **Create**.

After that, only the protected branch(es) can deploy to `production`.

---

**Required reviewers (approval before run)**

To make Terraform Apply **wait for a person to approve** each run:

- On the same **Configure production** page, scroll down.
- Find **Environment protection rules** (or **Required reviewers**).
- Enable **Required reviewers** and add yourself (or your team). When a workflow job uses `environment: production`, it will pause in the **Actions** tab until someone approves it.

---

**Note:** On **private** repos, some protection rules may not be fully enforced until the repo is in a **GitHub Team** or **Enterprise** organization. The UI may show a warning; you can still configure the options above.

---

### Step 3a.5 — How to trigger workflows and where to see runs (absolute beginner)

**Where you always look for runs:** Open your repo on GitHub in the browser. Click the **Actions** tab (top bar, next to Pull requests). Every workflow run appears here. Click a run to see its jobs; click a job name to see the log output.

---

**1) Terraform Plan**

- **Where:** Your computer (terminal) and GitHub in the browser.
- **What to do:**
  1. In the terminal, from your repo folder, create a branch and change something under `infra/`:
     ```bash
     git checkout -b my-plan-branch
     ```
  2. Edit any file under `infra/` (e.g. add a comment in `infra/envs/dev/main.tf`), then:
     ```bash
     git add infra/
     git commit -m "test terraform plan"
     git push -u origin my-plan-branch
     ```
  3. In the **browser:** go to your repo on GitHub → click **Pull requests** → **New pull request**. Set **base** to `main`, **compare** to `my-plan-branch` → **Create pull request**. The "Terraform Plan" workflow starts automatically.
  4. To see the plan: click the **Actions** tab → click the running or completed "Terraform Plan" run → click the **plan** job → read the log (the Terraform plan text is in there).

---

**2) Terraform Apply**

- **Where:** Browser (and optionally terminal if you push from local).
- **What to do (option A — merge the PR):** In the repo, go to **Pull requests** → open the PR you created → click **Merge pull request** → **Confirm merge**. The "Terraform Apply" workflow runs.
- **What to do (option B — push directly to main):** In the terminal:
  ```bash
  git checkout main
  git pull origin main
  # make a small change under infra/, then:
  git add infra/
  git commit -m "apply infra change"
  git push origin main
  ```
- **Where to see it:** **Actions** tab → click the "Terraform Apply" run → open the **apply** job for logs. If you set up required reviewers for `production`, the run will wait; click the run and use the **Review deployments** button to approve.

---

**3) Build and Push Image**

- **Where:** Terminal, then GitHub Actions runs automatically.
- **What to do:** From the repo root on your machine, change something under `app/` (e.g. edit `app/server.js`), then:
  ```bash
  git add app/
  git commit -m "update app"
  git push origin main
  ```
- **What happens:** The "Build and Push Image" workflow runs (triggered by push to `main` with changes under `app/`). It builds the image, pushes to ECR, and updates the prod image tag.
- **Where to see it:** **Actions** tab → "Build and Push Image" → open the run and the build job for logs.

---

**4) Deploy (CodeDeploy)**

- **Where:** Nothing to type. This runs automatically after "Build and Push Image" succeeds.
- **What happens:** The "Deploy" workflow packages `deploy/`, uploads to S3, and triggers CodeDeploy.
- **Where to see it:** **Actions** tab → "Deploy" (or the run that follows the build). Open the run and the deploy job for logs.

---

**5) Deploy (Ansible)**

- **Where:** Nothing to type. This also runs automatically after "Build and Push Image" succeeds.
- **What happens:** The "Deploy (Ansible)" workflow installs Ansible and the Session Manager plugin, gets the prod bucket from Terraform, and runs the Ansible playbook over SSM to prod EC2.
- **Where to see it:** **Actions** tab → "Deploy (Ansible)" → open the run and the deploy job for logs.

---

### Summary (OIDC + GitHub Actions)

| Step | Where | What |
|------|--------|------|
| **3a.1** | **Bash** (from repo root) | `cd infra/oidc` → `terraform init` → `terraform apply -auto-approve -var="github_org=..." -var="github_repo=..."` → copy **role_arn**. |
| **3a.2** | **Browser** (GitHub repo Settings) | **Secrets and variables → Actions** → add `AWS_ROLE_TO_ASSUME` (role ARN) and `AWS_REGION` (e.g. `us-east-1`). |
| **3a.3** | — | Workflows already in `.github/workflows/`. No command. |
| **3a.4** | **Browser** (optional) | **Settings → Environments** → create **production**; set **Deployment branches and tags** (No restriction / Protected branches only / Selected branches); optionally add **Required reviewers**. If using "Protected branches only", add a ruleset or branch protection rule for `main` under **Rules** or **Branches**. |
| **3a.5** | **Bash** or GitHub UI | Push or open PRs; view runs under **Actions** tab. |

After this, **build-push** and **deploy** can replace manual build/push and CodeDeploy trigger. You can still deploy with **Ansible** manually (section 5a) if you prefer.

---

## 4) Build + push image (required before deploy)

**From:** repo root (example: dev)
```bash
docker build -t bluegreen-dev-app:<tag> app
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin 058264482067.dkr.ecr.us-east-1.amazonaws.com
docker tag bluegreen-dev-app:202602081206 058264482067.dkr.ecr.us-east-1.amazonaws.com/bluegreen-dev-app:202602081206
docker push 058264482067.dkr.ecr.us-east-1.amazonaws.com/bluegreen-dev-app:<tag>

eg:
docker build -t bluegreen-dev-app:202602081231 app
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin 058264482067.dkr.ecr.us-east-1.amazonaws.com
docker tag bluegreen-dev-app:202602081231 058264482067.dkr.ecr.us-east-1.amazonaws.com/bluegreen-dev-app:202602081231
docker push 058264482067.dkr.ecr.us-east-1.amazonaws.com/bluegreen-dev-app:202602081231

**From:** repo root (example: prod)
```bash
docker build -t bluegreen-prod-app:<tag> app
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin 058264482067.dkr.ecr.us-east-1.amazonaws.com
docker tag bluegreen-prod-app:202602081206 058264482067.dkr.ecr.us-east-1.amazonaws.com/bluegreen-prod-app:202602081206
docker push 058264482067.dkr.ecr.us-east-1.amazonaws.com/bluegreen-prod-app:<tag>

eg:
docker build -t bluegreen-prod-app:202602081140 app
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin 058264482067.dkr.ecr.us-east-1.amazonaws.com
docker tag bluegreen-prod-app:202602081140 058264482067.dkr.ecr.us-east-1.amazonaws.com/bluegreen-prod-app:202602081140
docker push 058264482067.dkr.ecr.us-east-1.amazonaws.com/bluegreen-prod-app:202602081140

# Set the tag in SSM (dev)
aws ssm put-parameter --name /bluegreen/dev/image_tag --value 202602081231 --type String --overwrite --region us-east-1
# Windows (Git Bash) fix for /bluegreen/... path
MSYS_NO_PATHCONV=1 aws ssm put-parameter --name "/bluegreen/dev/image_tag" --value 202602081231 --type String --overwrite --region us-east-1

# Set the tag in SSM (prod)
aws ssm put-parameter --name /bluegreen/prod/image_tag --value 202602081140 --type String --overwrite --region us-east-1
# Windows (Git Bash) fix for /bluegreen/... path
MSYS_NO_PATHCONV=1 aws ssm put-parameter --name "/bluegreen/prod/image_tag" --value 202602081140 --type String --overwrite --region us-east-1

# Note: image_tag defaults to "unset" until you update it

# For prod: use bluegreen-prod-app, push to prod ECR repo, then set SSM:
# aws ssm put-parameter --name /bluegreen/prod/image_tag --value <tag> --type String --overwrite --region us-east-1
```

## 5a) Deploy via Ansible (recommended alternative to CodeDeploy)

Uses Ansible over SSM (no SSH); instances must have SSM agent and IAM role. **From:** all Ansible commands below are run from **repo root** (in WSL that is `/mnt/c/My-Projects/CICD-With-AI`; on Linux/macOS use your repo path).

**Windows:** Native Windows is **not** a supported Ansible control node in 2.14+ (`OSError` / `os.get_blocking`). Use **WSL + Ubuntu** (below) or **Ansible 2.13** in PowerShell — see **ansible/README.md** for the 2.13 workaround.

---

### On Windows: start from WSL + Ubuntu

**Step 1 — Open Ubuntu (not the Docker Desktop WSL shell)**  
In PowerShell: `wsl -l -v` to list distros. If you only have `docker-desktop`, install Ubuntu: `wsl --install -d Ubuntu`. Then open Ubuntu (Start menu → Ubuntu, or `wsl -d Ubuntu`).

**Step 2 — One-time setup inside Ubuntu**

Install the venv package so `python3 -m venv` works (required on Ubuntu). Create the venv in your **WSL home** (not inside the repo on `/mnt/c`) to avoid ensurepip errors:

```bash
# Install venv support (enter your Ubuntu password when asked)
sudo apt update
sudo apt install -y python3-venv python3-pip
# Or if you have Python 3.12: sudo apt install -y python3.12-venv python3-pip

# Create venv in WSL home (repo on /mnt/c often fails with ensurepip)
python3 -m venv ~/venv-cicd-ansible
source ~/venv-cicd-ansible/bin/activate

# Go to repo and install Ansible, boto3 (required by EC2 inventory plugin), collections, and AWS CLI
cd /mnt/c/My-Projects/CICD-With-AI
pip install ansible boto3 awscli
ansible-galaxy collection install -r ansible/requirements.yml --force -p "$(python -c 'import site; print(site.getsitepackages()[0])')"
```

**Step 3 — Install Session Manager plugin (required for SSM)**  
The playbook connects to EC2 via SSM; the plugin must be installed in Ubuntu (one-time):

```bash
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o /tmp/session-manager-plugin.deb
sudo dpkg -i /tmp/session-manager-plugin.deb
```

**Step 4 — Configure AWS in this Ubuntu session**  
Copy your Windows `.aws` into WSL (replace `zak20` with your Windows username if different), or set env vars:

```bash
mkdir -p ~/.aws
cp /mnt/c/Users/zak20/.aws/credentials ~/.aws/
cp /mnt/c/Users/zak20/.aws/config ~/.aws/ 2>/dev/null || true
export AWS_PROFILE=default
aws sts get-caller-identity
```

**Step 5 — Run the Ansible deploy (in Ubuntu/WSL)**

Do this **only after** you have completed **§4** (Build + push image): build your Docker image, push it to ECR, and set the SSM parameter `/bluegreen/dev/image_tag` (or `/bluegreen/prod/image_tag` for prod). Then run the following **in order**, from repo root inside Ubuntu.

**Step 5.1 — Activate venv and go to repo**

```bash
source ~/venv-cicd-ansible/bin/activate
cd /mnt/c/My-Projects/CICD-With-AI
```

**Step 5.2 — Set Ansible config (required when repo is on /mnt/c)**

```bash
export ANSIBLE_CONFIG=/mnt/c/My-Projects/CICD-With-AI/ansible.cfg
```

**Step 5.3 — Get the S3 bucket name (required for SSM connection)**

The playbook needs the name of an S3 bucket (the same one Terraform uses for CodeDeploy artifacts). You need to get this bucket name and use it in Step 5.4.

**If you use WSL (Ubuntu):** In WSL, the command `terraform` often runs the **Windows** Terraform, which Linux cannot run, so you may see **"cannot execute binary file: Exec format error"**. You do **not** need to fix that to deploy. The easiest way is to get the bucket name from **Windows**, then run the playbook in **WSL** (below).

- **Recommended for WSL users — Get the bucket from Windows**
  1. On **Windows**, open **PowerShell** or **CMD**.
  2. Run (replace the path if your repo is elsewhere). Use **dev** or **prod** to match the environment you are deploying to:
     - **Dev:** `cd C:\My-Projects\CICD-With-AI\infra\envs\dev` then `terraform output -raw artifacts_bucket`
     - **Prod:** `cd C:\My-Projects\CICD-With-AI\infra\envs\prod` then `terraform output -raw artifacts_bucket`
  3. **Copy** the single line that is printed (e.g. `bluegreen-dev-codedeploy-...` or `bluegreen-prod-codedeploy-...`). You will paste it in Step 5.4.
  4. Go back to **WSL** and continue with Step 5.4, using that value for `-e ssm_bucket=...`. For **prod** also add `-e env=prod`.

- **If `terraform` works in your WSL terminal** (e.g. you installed Linux Terraform), you can get the bucket from WSL instead. From repo root:
  - **Dev:** `cd infra/envs/dev && terraform output -raw artifacts_bucket && cd ../..`
  - **Prod:** `cd infra/envs/prod && terraform output -raw artifacts_bucket && cd ../..`  
  Copy the printed bucket name for Step 5.4.

**Step 5.4 — Run the playbook with the bucket**

Replace `YOUR_ARTIFACTS_BUCKET` with the value from Step 5.3.

- **Dev (deploy to instances tagged Env=dev):**
  ```bash
  ansible-playbook -i ansible/inventory/ec2_dev.aws_ec2.yml ansible/playbooks/deploy.yml -e ssm_bucket=YOUR_ARTIFACTS_BUCKET
  ```
- **Prod (deploy to instances tagged Env=prod):**  
  Use the **prod** artifacts bucket from Step 5.3 and pass **`-e env=prod`** so the playbook uses SSM parameters `/bluegreen/prod/...` (image tag, ECR repo). Before deploying to prod, build and push the prod image, then set the SSM parameter:  
  `aws ssm put-parameter --name /bluegreen/prod/image_tag --value YOUR_TAG --type String --overwrite --region us-east-1`
  ```bash
  ansible-playbook -i ansible/inventory/ec2_prod.aws_ec2.yml ansible/playbooks/deploy.yml -e ssm_bucket=YOUR_ARTIFACTS_BUCKET -e env=prod
  ```

**Optional — Get bucket and run in one go:**  
Only works if `terraform` runs correctly in WSL (Linux Terraform installed). If you get "Exec format error", use the "Get the bucket from Windows" method above instead.

- **Dev:**  
  ```bash
  BUCKET=$(cd infra/envs/dev && terraform output -raw artifacts_bucket)
  ansible-playbook -i ansible/inventory/ec2_dev.aws_ec2.yml ansible/playbooks/deploy.yml -e ssm_bucket="$BUCKET"
  ```
- **Prod:**  
  ```bash
  BUCKET=$(cd infra/envs/prod && terraform output -raw artifacts_bucket)
  ansible-playbook -i ansible/inventory/ec2_prod.aws_ec2.yml ansible/playbooks/deploy.yml -e ssm_bucket="$BUCKET" -e env=prod
  ```

Full step-by-step (troubleshooting, paths, ensurepip, AWS) is in **ansible/README.md**.

**If the playbook fails:**  
- Use inventory files named **`*.aws_ec2.yml`** (e.g. `ec2_dev.aws_ec2.yml`). Plain `ec2_dev.yml` can cause "Plugin configuration YAML file, not YAML inventory" or "could not be verified".  
- (1) **"ignoring it as an ansible.cfg source" / Exec format error** → set `export ANSIBLE_CONFIG=/mnt/c/My-Projects/CICD-With-AI/ansible.cfg` before running the playbook.  
- (2) **"Failed to load inventory plugin" / "could not be verified"** → install boto3 and collections **into the venv**, then test:  
  `ansible-inventory -i ansible/inventory/ec2_dev.aws_ec2.yml --graph -vvv`  
  Full steps and minimal copy-paste sequence are in **ansible/README.md** → Troubleshooting.

---

### On Linux / macOS (or if you already have Ansible in WSL)

**One-time:** from repo root, create venv (or use `pip install --user ansible`), install Ansible and collections, then run the playbook from repo root as above. See **ansible/README.md** for venv vs user install.

**Optional: trigger deploy from Terraform**
```bash
cd infra/envs/dev
terraform apply -var-file=dev.tfvars -var="trigger_ansible_deploy=1"
# Runs Ansible deploy after apply (requires Ansible + collections installed)
```

---

## 5b) Deploy via CodeDeploy (manual option)

**From:** repo root (example: dev)
```bash
cd infra/envs/dev
terraform output -raw artifacts_bucket
# If outputs are missing:
terraform apply -refresh-only -auto-approve -var-file=dev.tfvars
terraform output -raw artifacts_bucket
```

```bash
# From repo root
zip -r deployment-202602081231.zip deploy
```

**Windows (PowerShell) alternative**
```powershell
Compress-Archive -Path deploy\* -DestinationPath deployment-202602081231.zip -Force
```

```bash
aws s3 cp deployment-202602081231.zip s3://<artifacts_bucket>/revisions/deployment-202602081231.zip
aws deploy create-deployment \
  --application-name bluegreen-dev-codedeploy-app \
  --deployment-group-name bluegreen-dev-dg \
  --s3-location bucket=<artifacts_bucket>,bundleType=zip,key=revisions/deployment-<tag>.zip
```
eg: in the root folder

aws s3 cp deployment-202602081231.zip s3://bluegreen-dev-codedeploy-20260208185936060600000001/revisions/deployment-202602081231.zip
aws deploy create-deployment \
  --application-name bluegreen-dev-codedeploy-app \
  --deployment-group-name bluegreen-dev-dg \
  --s3-location bucket=bluegreen-dev-codedeploy-20260208185936060600000001,bundleType=zip,key=revisions/deployment-202602081231.zip

---

## 6) Validate after deploy

**From:** anywhere
```bash
# Health check (dev example)
curl -i https://dev-app.my-iifb.click/health
```

**If health check fails:**
```bash
# Check target group health (dev)
aws --no-cli-pager elbv2 describe-target-health \
  --target-group-arn <dev_tg_arn>

# If using CodeDeploy (5b)
aws --no-cli-pager deploy list-deployments \
  --application-name bluegreen-dev-codedeploy-app \
  --deployment-group-name bluegreen-dev-dg
```

**Logs to check (CloudWatch):**
- `/${project}/${env}/docker`
- `/${project}/${env}/system`

---

## Destroy (tear down)

### A) Destroy dev

**From:** repo root
```bash
cd infra/envs/dev
terraform destroy -auto-approve -var-file=dev.tfvars
```

### B) Destroy prod

**From:** repo root
```bash
cd ../prod
terraform destroy -auto-approve -var-file=prod.tfvars
```

### C) Destroy bootstrap (optional, last)

**From:** repo root
```bash
cd ../bootstrap
terraform destroy -auto-approve
```

---

## EC2 User Data (Reference)

Paste this into **Advanced details → User data** when launching a manual instance.

```bash
#!/bin/bash
set -e
log() { echo "[$(date -u +%FT%TZ)] $*"; }
retry() {
  local n=0
  local max=12
  local delay=10
  until "$@"; do
    n=$((n+1))
    if [ "$n" -ge "$max" ]; then
      return 1
    fi
    log "retry $n/$max: $*"
    sleep "$delay"
  done
}
echo "dev" > /opt/bluegreen-env
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region || true)
if [ -z "$REGION" ]; then
  REGION="us-east-1"
fi
PKG_MGR="yum"
if command -v dnf >/dev/null 2>&1; then
  PKG_MGR="dnf"
fi
log "Refreshing package metadata"
retry $PKG_MGR clean all
retry $PKG_MGR makecache --setopt=skip_if_unavailable=true
log "Installing base packages"
retry $PKG_MGR update -y --setopt=skip_if_unavailable=true
retry $PKG_MGR install -y docker ruby wget amazon-cloudwatch-agent --setopt=skip_if_unavailable=true
systemctl enable docker
systemctl start docker
cd /home/ec2-user
wget https://aws-codedeploy-$REGION.s3.$REGION.amazonaws.com/latest/install
chmod +x ./install
./install auto
systemctl start codedeploy-agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 \
  -c ssm:/bluegreen/dev/cloudwatch/agent-config -s
```

**Adjust for prod**: change `echo "dev"` and the SSM path to `prod` (and `us-east-1` if different).
