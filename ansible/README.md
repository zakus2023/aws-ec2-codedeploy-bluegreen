# Ansible deploy (alternative to CodeDeploy)

Deploys the app to EC2 instances over **AWS Systems Manager (SSM)** — no SSH, no CodeDeploy agent required for this path.

## Prerequisites

- Python 3 and pip
- AWS credentials configured (e.g. `AWS_PROFILE` or `~/.aws/credentials`)
- **Session Manager plugin** installed on the machine that runs Ansible (required for `connection: community.aws.aws_ssm`). On WSL/Ubuntu see [Install Session Manager plugin (WSL/Ubuntu)](#install-session-manager-plugin-wslubuntu) below.
- EC2 instances have SSM agent and IAM role with SSM permissions (platform module provides this)

**CI (GitHub Actions):** To automate **build + push to ECR** and **CodeDeploy** deploy from GitHub, follow **RUN_COMMANDS_ORDER.md** section **3a) OIDC and GitHub Actions**. That section sets up the OIDC role and the workflow files (terraform-plan, terraform-apply, build-push, deploy). **Ansible** deploy (this readme) is still run manually from your machine (WSL or Linux) when you want to deploy without CodeDeploy.

## Ansible on Windows (control node)

**Native Windows is not a supported Ansible control node.** Ansible 2.14+ uses `os.get_blocking()` on stdin/stdout/stderr, which is not supported on Windows. You will see:

- `OSError: [WinError 1] Incorrect function` and `os.get_blocking` when running `ansible-galaxy` or `ansible-playbook` in **any** Windows shell (PowerShell, CMD, or Git Bash).

**Use one of these instead:**

1. **WSL (recommended on Windows)** — Same machine, same repo: WSL uses your existing repo (e.g. `C:\My-Projects\CICD-With-AI` → `/mnt/c/My-Projects/CICD-With-AI`). No copy needed. See [WSL setup (step-by-step)](#wsl-setup-step-by-step-for-beginners) below.
2. **Ansible 2.13 on Windows (workaround)** — The blocking-IO check was added in 2.14. Pinning to **Ansible 2.13** lets you run `ansible-galaxy` and `ansible-playbook` in PowerShell/CMD in this repo. See [Workaround: Ansible 2.13 on Windows](#workaround-ansible-213-on-windows) below. Not officially supported by Ansible.
3. **Linux host** — Run Ansible from a Linux machine (e.g. EC2, CI runner) that has access to this repo and AWS credentials.

## WSL setup (step-by-step, for beginners)

Ansible 2.14+ does not run on native Windows (you get `OSError` / `os.get_blocking`). Using **WSL** lets you run Ansible on the same machine, in the same repo—no copy. Follow these steps in order.

---

**Reference:** In this guide, **zak20** is used as the example Windows username and **ABDUL-RAZAK** as the hostname (e.g. `zak20@ABDUL-RAZAK`). Replace with your own if different.

### Why WSL and not "the WSL that opened when I clicked something"?

If you only have **docker-desktop** in your WSL list, that is the **Docker Desktop** WSL shell. It is a minimal environment and usually **does not mount your Windows C: drive**, so paths like `/mnt/c/My-Projects/...` do not exist and `cd` will fail. You need a **full Linux distro** (e.g. **Ubuntu**) so that `/mnt/c` is available and you can use your existing project folder.

---

### Step 1: See which WSL distros you have

Open **PowerShell** (or CMD) on Windows and run:

```powershell
wsl -l -v
```

You will see a table: **NAME**, **STATE**, **VERSION**.

- If you see **Ubuntu** (or another distro like Debian) in the list, you can use it—go to Step 3.
- If you **only** see **docker-desktop**, you need to install Ubuntu (Step 2).

---

### Step 2: Install Ubuntu (if you don’t have it)

In **PowerShell** (you may need to run it as Administrator):

```powershell
wsl --install -d Ubuntu
```

Wait for the install to finish. When it asks, create a **username** and **password** for Ubuntu (you will use this to run commands inside WSL).

**Alternative:** Install **Ubuntu** from the **Microsoft Store** (search for "Ubuntu"), then open it from the Start menu.

---

### Step 3: Open Ubuntu

- From the **Start menu**: type **Ubuntu** and open the **Ubuntu** app, or  
- From **PowerShell**: run  
  ```powershell
  wsl -d Ubuntu
  ```

You should get a terminal with a prompt like `zak20@ABDUL-RAZAK:~$` (replace with your own username@hostname). All following steps are run **inside this Ubuntu terminal**.

---

### Step 4: Find your project folder in WSL

Your Windows drives appear under `/mnt/` in WSL. The repo is usually in one of these places:

| On Windows (example)              | In WSL (Ubuntu)                          |
|----------------------------------|------------------------------------------|
| `C:\My-Projects\CICD-With-AI`    | `/mnt/c/My-Projects/CICD-With-AI`        |
| `C:\Users\zak20\...\CICD-With-AI` | `/mnt/c/Users/zak20/.../CICD-With-AI` |

**If you’re not sure**, run these in the Ubuntu terminal and adjust the path you use:

```bash
# See what’s on C:
ls /mnt/c/

# If your project is under your user folder (common):
ls /mnt/c/Users/
# Then (replace zak20 with your Windows username if different):
ls /mnt/c/Users/zak20/
```

Once you know the path, go to the repo (use the path that exists on your machine):

```bash
# Try one of these (only one will work on your machine):
cd /mnt/c/My-Projects/CICD-With-AI
# or, for example:
# cd /mnt/c/Users/zak20/My-Projects/CICD-With-AI   # if your repo is under your user folder
```

Check you’re in the right place (you should see `ansible`, `app`, `infra`, etc.):

```bash
ls
```

---

### Step 5: Install Python and venv (required on Ubuntu/Debian)

In the **same Ubuntu terminal**, still in the repo folder:

```bash
# Check if Python 3 is installed
python3 --version
```

If you get **"command not found"**, install Python and the venv package:

```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-pip
```

Even when Python 3 is already installed, **you must install the venv package** or `python3 -m venv` will fail with *"The virtual environment was not created successfully because ensurepip is not available"*. Install it with **sudo** (you will be asked for your Ubuntu password):

```bash
# Generic (usually pulls the right version for your Python)
sudo apt update
sudo apt install -y python3-venv python3-pip

# Or if the error message names a specific version (e.g. python3.12-venv):
# sudo apt install -y python3.12-venv python3-pip
```

Then run `python3 --version` again to confirm.

---

### Step 6: Create a venv and install Ansible + collections

**Recommended when your repo is on `/mnt/c/...`:** Create the venv in your **WSL home directory**, not inside the repo. Venvs created on the Windows drive (`/mnt/c`) often fail with *"ensurepip ... returned non-zero exit status 1"* due to filesystem differences. You will still run all playbooks from the repo folder.

**Option A — Venv in WSL home (recommended if repo is on /mnt/c):**

```bash
# Remove any broken .venv in the repo (if you tried there before)
rm -rf /mnt/c/My-Projects/CICD-With-AI/.venv

# Create venv in your Linux home (one-time)
python3 -m venv ~/venv-cicd-ansible

# Activate it (do this every time you open a new terminal to run Ansible)
source ~/venv-cicd-ansible/bin/activate

# Go to repo and install Ansible, boto3 (required by amazon.aws.aws_ec2 inventory plugin), and collections
cd /mnt/c/My-Projects/CICD-With-AI
pip install ansible boto3
ansible-galaxy collection install -r ansible/requirements.yml --force -p "$(python -c 'import site; print(site.getsitepackages()[0])')"
```

**Option B — Venv inside the repo (use only if your repo is on the Linux filesystem):**

If your repo were under `/home/zak20/...` (WSL home) instead of `/mnt/c/...`, you could create the venv in the repo:

```bash
cd /mnt/c/My-Projects/CICD-With-AI
rm -rf .venv
python3 -m venv .venv
source .venv/bin/activate
pip install ansible
ansible-galaxy collection install -r ansible/requirements.yml --force
```

On many WSL setups Option B fails with an ensurepip error when the repo is on `/mnt/c`; use Option A then.

**If venv creation fails** with *"ensurepip is not available"*: install the venv package with **sudo** (e.g. `sudo apt install -y python3.12-venv` or `sudo apt install -y python3-venv`). If you still get *"ensurepip ... returned non-zero exit status 1"*, use **Option A** (venv in WSL home). See Step 5 for installing python3-venv.

If `ansible-galaxy` runs without errors, Ansible and the AWS collections are ready.

---

### Step 7: Configure AWS credentials in WSL

Ansible needs AWS credentials to talk to EC2/SSM. You can use the same profile or keys you use on Windows.

**Option A — Use a named profile (e.g. `default`):**

WSL has its own home directory, so it does not automatically see `C:\Users\zak20\.aws`. Either:

- Copy your Windows `.aws` folder into WSL (one-time), then use the profile. Replace **zak20** with your Windows username if different:
  ```bash
  mkdir -p ~/.aws
  cp /mnt/c/Users/zak20/.aws/credentials ~/.aws/
  cp /mnt/c/Users/zak20/.aws/config ~/.aws/ 2>/dev/null || true
  export AWS_PROFILE=default
  ```
- Or set **access key** and **secret key** in WSL (see Option B) and use `AWS_PROFILE` if you also copy `config`.

**Option B — Use environment variables:**

```bash
export AWS_ACCESS_KEY_ID=your_access_key_here
export AWS_SECRET_ACCESS_KEY=your_secret_key_here
export AWS_DEFAULT_REGION=us-east-1
```

Replace with your real values. To test that AWS is visible from WSL:

```bash
aws sts get-caller-identity
```

(If `aws` is not found, install the AWS CLI in your venv: `pip install awscli`. On some Ubuntu versions `sudo apt install awscli` is not available; pip is the reliable option.)

---

### Step 7b: Install Session Manager plugin (WSL/Ubuntu)

The playbook connects to EC2 via **AWS Systems Manager (SSM)**. That requires the **Session Manager plugin** on the control node (your WSL). Install it once in Ubuntu:

```bash
# Download the .deb (use ubuntu_arm64 if you're on ARM)
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o /tmp/session-manager-plugin.deb
sudo dpkg -i /tmp/session-manager-plugin.deb
session-manager-plugin
```

If the last command prints usage/help, the plugin is installed. Then run the playbook (Step 8).

---

### Step 8: Run the Ansible deploy

**What this step does:** Ansible connects to your EC2 instances over **AWS Systems Manager (SSM)** (no SSH). On each instance it: stops the running app container, pulls the new image from ECR (using the tag stored in SSM), starts the container, and checks that `/health` responds. All of that is defined in `ansible/playbooks/deploy.yml`; you just run one command.

**Before you run it, you must have done the following in full:**

**1. Build and push your Docker image to ECR**

From your repo root (Windows PowerShell, CMD, or WSL). Pick a tag (e.g. `202602081231`); use the same tag everywhere below.

```bash
# Build the image (replace <tag> with your tag, e.g. 202602081231)
docker build -t bluegreen-dev-app:<tag> app
```

Log in to ECR and push. Replace `<account-id>` with your AWS account ID and `<region>` with your region (e.g. `us-east-1`). The ECR repo name is usually `bluegreen-dev-app` for dev or `bluegreen-prod-app` for prod (from Terraform).

```bash
aws ecr get-login-password --region <region> | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.<region>.amazonaws.com

docker tag bluegreen-dev-app:<tag> <account-id>.dkr.ecr.<region>.amazonaws.com/bluegreen-dev-app:<tag>
docker push <account-id>.dkr.ecr.<region>.amazonaws.com/bluegreen-dev-app:<tag>
```

Example with tag `202602081231`, account `058264482067`, region `us-east-1`:

```bash
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin 058264482067.dkr.ecr.us-east-1.amazonaws.com
docker tag bluegreen-dev-app:202602081231 058264482067.dkr.ecr.us-east-1.amazonaws.com/bluegreen-dev-app:202602081231
docker push 058264482067.dkr.ecr.us-east-1.amazonaws.com/bluegreen-dev-app:202602081231
```

**2. Set the SSM parameter so instances know which image to run**

Ansible and the app read the image tag from SSM. Set it to the **exact tag** you pushed.

- **Dev:** parameter name `/bluegreen/dev/image_tag`
- **Prod:** parameter name `/bluegreen/prod/image_tag`

Run from WSL (with AWS CLI and credentials) or Windows. Replace `<tag>` with your tag and `<region>` with your region (e.g. `us-east-1`).

```bash
# Dev
aws ssm put-parameter --name /bluegreen/dev/image_tag --value <tag> --type String --overwrite --region <region>

# Prod (when deploying to prod)
aws ssm put-parameter --name /bluegreen/prod/image_tag --value <tag> --type String --overwrite --region <region>
```

Example for dev with tag `202602081231` and region `us-east-1`:

```bash
aws ssm put-parameter --name /bluegreen/dev/image_tag --value 202602081231 --type String --overwrite --region us-east-1
```

On **Windows (Git Bash)** the path `/bluegreen/...` can be mangled; use:

```bash
MSYS_NO_PATHCONV=1 aws ssm put-parameter --name "/bluegreen/dev/image_tag" --value 202602081231 --type String --overwrite --region us-east-1
```

**3. AWS credentials in this WSL session**

Step 7 must be done in the same terminal (or re-run `export AWS_PROFILE=default` / your env vars). Check with:

```bash
aws sts get-caller-identity
```

Once 1–3 are done, run the Ansible deploy by following these steps **in order**.

**Step 8.1 — Activate venv and go to repo**

```bash
# Activate venv (Option A from Step 6)
source ~/venv-cicd-ansible/bin/activate
# Or if you used Option B:  source .venv/bin/activate

# Go to repo root (use your path from Step 4 if different)
cd /mnt/c/My-Projects/CICD-With-AI
```

**Step 8.2 — Set Ansible config (required when repo is on /mnt/c)**

```bash
export ANSIBLE_CONFIG=/mnt/c/My-Projects/CICD-With-AI/ansible.cfg
```

**Step 8.3 — Get the S3 bucket name (required for SSM connection)**

The playbook needs the name of an S3 bucket (the same one Terraform uses for CodeDeploy). You will pass this to the playbook in Step 8.4.

**If you use WSL:** In WSL, typing `terraform` often runs the **Windows** Terraform, which Linux cannot run. You will see **"cannot execute binary file: Exec format error"**. You do **not** need to fix that. The easiest way is to get the bucket name from **Windows**, then run the playbook in **WSL**.

- **Recommended for WSL — Get the bucket from Windows**
  1. On **Windows**, open **PowerShell** or **CMD** (not WSL).
  2. Run (change the path if your repo is elsewhere). Use **dev** or **prod** to match the environment you are deploying to:
     - **Dev:** `cd C:\My-Projects\CICD-With-AI\infra\envs\dev` then `terraform output -raw artifacts_bucket`
     - **Prod:** `cd C:\My-Projects\CICD-With-AI\infra\envs\prod` then `terraform output -raw artifacts_bucket`
  3. **Copy** the one line that is printed. You will paste it in Step 8.4 as `-e ssm_bucket=PASTE_HERE`. For **prod** you also need `-e env=prod`.
  4. Switch back to **WSL** and do Step 8.4 with that value.

- **If `terraform` already works in your WSL terminal** (e.g. you installed Linux Terraform), you can get the bucket from WSL. From repo root:
  - **Dev:** `cd infra/envs/dev && terraform output -raw artifacts_bucket && cd ../..`
  - **Prod:** `cd infra/envs/prod && terraform output -raw artifacts_bucket && cd ../..`  
  Copy the printed bucket name for Step 8.4.

**Step 8.4 — Run the playbook with the bucket**

Replace `YOUR_ARTIFACTS_BUCKET` with the value from Step 8.3.

- **Dev (instances tagged Env=dev):**  
  ```bash
  ansible-playbook -i ansible/inventory/ec2_dev.aws_ec2.yml ansible/playbooks/deploy.yml -e ssm_bucket=YOUR_ARTIFACTS_BUCKET
  ```

- **Prod (instances tagged Env=prod):**  
  Before deploying to prod: (1) build and push the **prod** image to the prod ECR repo, (2) set the SSM parameter:  
  `aws ssm put-parameter --name /bluegreen/prod/image_tag --value YOUR_TAG --type String --overwrite --region us-east-1`  
  Get the **prod** artifacts bucket (from Windows: `cd ...\infra\envs\prod` then `terraform output -raw artifacts_bucket`). Then run the playbook with **`-e env=prod`** so it uses `/bluegreen/prod/` SSM parameters:
  ```bash
  ansible-playbook -i ansible/inventory/ec2_prod.aws_ec2.yml ansible/playbooks/deploy.yml -e ssm_bucket=YOUR_PROD_ARTIFACTS_BUCKET -e env=prod
  ```
  eg:

  ansible-playbook -i ansible/inventory/ec2_prod.aws_ec2.yml ansible/playbooks/deploy.yml -e ssm_bucket=bluegreen-prod-codedeploy-20260209043202936700000001 -e env=prod

**Optional — Get bucket and run in one go:**  
Only works if `terraform` runs in WSL (you have Linux Terraform). If you see "Exec format error", use the "Get the bucket from Windows" method in Step 8.3 instead.

- **Dev:** `BUCKET=$(cd infra/envs/dev && terraform output -raw artifacts_bucket)` then `ansible-playbook -i ansible/inventory/ec2_dev.aws_ec2.yml ansible/playbooks/deploy.yml -e ssm_bucket="$BUCKET"`
- **Prod:** `BUCKET=$(cd infra/envs/prod && terraform output -raw artifacts_bucket)` then `ansible-playbook -i ansible/inventory/ec2_prod.aws_ec2.yml ansible/playbooks/deploy.yml -e ssm_bucket="$BUCKET" -e env=prod`

- **`-e ssm_bucket=...`** — Required. The SSM connection plugin uses this S3 bucket to transfer module files. Use the same bucket as CodeDeploy artifacts (Step 8.3).
- **`-i ansible/inventory/ec2_dev.aws_ec2.yml`** — inventory: which hosts to run on (dev EC2 instances). The `.aws_ec2.yml` suffix lets Ansible accept the file as an aws_ec2 inventory source.
- **`ansible/playbooks/deploy.yml`** — the playbook: stop container, pull image, start, check `/health`.

You should see Ansible list the instances, run tasks, and end with a summary. If a task fails, the output will show which host and which step failed.

---

### Quick reference (after you’ve done the steps once)

1. **Open Ubuntu:** Start menu → Ubuntu, or `wsl -d Ubuntu` in PowerShell.
2. **Activate venv:** `source ~/venv-cicd-ansible/bin/activate` (or `source .venv/bin/activate` if you used Option B in Step 6).
3. **Go to repo:** `cd /mnt/c/My-Projects/CICD-With-AI` (or your path from Step 4).
4. **Set AWS:** `export AWS_PROFILE=default` (or your profile / env vars from Step 7).
5. **Set Ansible config (repo on /mnt/c):** `export ANSIBLE_CONFIG=/mnt/c/My-Projects/CICD-With-AI/ansible.cfg`
6. **Get S3 bucket:** In WSL, `terraform` often fails with "Exec format error" (Windows binary). Easiest: on **Windows** (PowerShell), run `cd C:\My-Projects\CICD-With-AI\infra\envs\dev` (or `\prod` for prod) then `terraform output -raw artifacts_bucket`, and copy the result.
7. **Deploy dev:** `ansible-playbook -i ansible/inventory/ec2_dev.aws_ec2.yml ansible/playbooks/deploy.yml -e ssm_bucket=YOUR_ARTIFACTS_BUCKET` (replace with the bucket from Step 6). **Deploy prod:** use `ec2_prod.aws_ec2.yml`, get bucket from `infra\envs\prod`, and add **`-e env=prod`** so the playbook uses `/bluegreen/prod/` SSM parameters; set `/bluegreen/prod/image_tag` in SSM before deploying.

## Troubleshooting

Common errors and causes:

| Error | Cause | Fix |
|-------|--------|-----|
| **Plugin configuration YAML file, not YAML inventory** / **could not be verified by inventory plugin 'amazon.aws.aws_ec2'** | (A) Inventory filename not ending in `.aws_ec2.yml`, (B) collection/plugin not in venv, (C) `ansible.cfg` not loaded or plugin not enabled, (D) AWS creds missing or wrong region. | Use inventory files named `*.aws_ec2.yml`, set `ANSIBLE_CONFIG`, install collection + boto3 in venv, confirm `aws sts get-caller-identity` (see below). |
| **Unknown plugin 'amazon.aws.ec2'** | Collection not installed (or not in the venv Ansible uses). | Install collections **into the WSL venv** with `-p` (see below). |
| **Exec format error** / **world writable directory** | Repo on `/mnt/c` is world-writable so Ansible ignores `ansible.cfg`. | Set `export ANSIBLE_CONFIG=/mnt/c/My-Projects/CICD-With-AI/ansible.cfg` before running the playbook. |
| **expected string or bytes-like object, got 'NoneType'** (on "Stop existing container" or first task) | SSM connection plugin requires an S3 bucket; `ssm_bucket` was not passed. | Pass the artifacts bucket: `-e ssm_bucket=BUCKET`. Get it with `cd infra/envs/dev && terraform output -raw artifacts_bucket` (or `infra/envs/prod` for prod). See Step 8.3 and Step 8.4. |

### Inventory must use `.aws_ec2.yml` filename

Ansible verifies dynamic inventory sources by **filename suffix**. Use:

- `ansible/inventory/ec2_dev.aws_ec2.yml` for dev
- `ansible/inventory/ec2_prod.aws_ec2.yml` for prod
- `ansible/inventory/ec2.aws_ec2.yml` for both (then use `--limit env_dev` or `--limit env_prod`)

Do **not** use `ec2_dev.yml` or `ec2.yml` — the plugin will not accept them and you will see "Plugin configuration YAML file, not YAML inventory".

### "Failed to load inventory plugin" / "Unknown plugin" / "could not be verified"

The **amazon.aws.aws_ec2** plugin can fail because: (1) **boto3** missing in the venv, (2) collection installed to `~/.ansible/collections` instead of the venv, (3) **ansible.cfg** not loaded (world-writable dir) so the plugin isn’t enabled, (4) **AWS credentials** not available in WSL (inventory needs them to verify).

**1) Confirm collection + plugin in this venv (WSL):**

```bash
source ~/venv-cicd-ansible/bin/activate
ansible --version
ansible-galaxy collection list | grep -E 'amazon.aws|community.aws'
ansible-doc -t inventory amazon.aws.aws_ec2 | head -n 20
python -c "import boto3, botocore; print('boto ok')"
```

If `ansible-doc ... aws_ec2` fails, the collection isn’t visible. Install into the venv:

```bash
cd /mnt/c/My-Projects/CICD-With-AI
ansible-galaxy collection install -r ansible/requirements.yml --force -p "$(python -c 'import site; print(site.getsitepackages()[0])')"
pip install boto3 botocore
```

**2) Confirm ansible.cfg is loaded and enables the plugin:**

```bash
export ANSIBLE_CONFIG=/mnt/c/My-Projects/CICD-With-AI/ansible.cfg
ansible-config dump --only-changed | head -30
```

You should see your `enable_plugins` (e.g. `amazon.aws.aws_ec2, auto`).

**3) Confirm AWS creds in WSL:**

```bash
aws sts get-caller-identity
aws ec2 describe-instances --region us-east-1 --max-items 5 >/dev/null && echo "ec2 api ok"
```

If `sts` fails, the aws_ec2 plugin often fails verification and Ansible falls back to YAML/INI parsing.

**4) Test inventory parsing directly:**

```bash
export ANSIBLE_CONFIG=/mnt/c/My-Projects/CICD-With-AI/ansible.cfg
ansible-inventory -i ansible/inventory/ec2_dev.aws_ec2.yml --graph -vvv
```

If this prints EC2 instances/groups, run the playbook the same way. If it still fails, paste the first ~50 lines of that output for debugging.

### Minimal copy-paste sequence (WSL, from repo root)

```bash
source ~/venv-cicd-ansible/bin/activate
cd /mnt/c/My-Projects/CICD-With-AI
ansible-galaxy collection install -r ansible/requirements.yml --force -p "$(python -c 'import site; print(site.getsitepackages()[0])')"
pip install boto3 botocore
export ANSIBLE_CONFIG=/mnt/c/My-Projects/CICD-With-AI/ansible.cfg
ansible-inventory -i ansible/inventory/ec2_dev.aws_ec2.yml --graph -vvv
# Get bucket: cd infra/envs/dev && terraform output -raw artifacts_bucket
ansible-playbook -i ansible/inventory/ec2_dev.aws_ec2.yml ansible/playbooks/deploy.yml -e ssm_bucket=YOUR_ARTIFACTS_BUCKET -vv
```

### "Exec format error" or "Failed to parse inventory with 'script' plugin"

When the repo is on **`/mnt/c/...`** (Windows drive in WSL), the directory is **world-writable**, so Ansible **does not load** `ansible.cfg` from it ("Ansible is being run in a world writable directory ... ignoring it as an ansible.cfg source"). Without that config, the script plugin runs first and tries to execute the inventory YAML → **Exec format error**.

**Fix:** Before running the playbook, set `ANSIBLE_CONFIG` so Ansible loads the repo’s config:

```bash
export ANSIBLE_CONFIG=/mnt/c/My-Projects/CICD-With-AI/ansible.cfg
ansible-playbook -i ansible/inventory/ec2_dev.aws_ec2.yml ansible/playbooks/deploy.yml -e ssm_bucket=YOUR_ARTIFACTS_BUCKET
```

Use the same `export` in every new terminal (or add to `~/.bashrc`). The repo also keeps `ansible/inventory/*.yml` in LF (`.gitattributes`); if you still see Exec format error after this, convert those files to LF:

**Option A — from WSL (Ubuntu):**
```bash
cd /mnt/c/My-Projects/CICD-With-AI
sed -i 's/\r$//' ansible/inventory/ec2_dev.aws_ec2.yml ansible/inventory/ec2_prod.aws_ec2.yml ansible/inventory/ec2.aws_ec2.yml
```

**Option B — in VS Code / Cursor:** Open each file under `ansible/inventory/`, click the "CRLF" or "LF" indicator in the status bar (bottom right), choose **LF**, then save.

**Option C — dos2unix (if installed in WSL):**
```bash
dos2unix ansible/inventory/ec2_dev.aws_ec2.yml ansible/inventory/ec2_prod.aws_ec2.yml ansible/inventory/ec2.aws_ec2.yml
```

Then run the playbook again.

### "Failed to find required executable session-manager-plugin"

The playbook uses `connection: community.aws.aws_ssm` to run tasks on EC2 via SSM. That requires the **Session Manager plugin** on the machine where you run Ansible (your WSL). Install it in Ubuntu:

```bash
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o /tmp/session-manager-plugin.deb
sudo dpkg -i /tmp/session-manager-plugin.deb
```

On ARM (e.g. some Windows ARM devices): use `ubuntu_arm64` in the URL instead of `ubuntu_64bit`. Then run the playbook again.

### "terraform: cannot execute binary file: Exec format error" (when getting S3 bucket in WSL)

**Why this happens:** In WSL you are running **Linux**. When you type `terraform`, the shell looks for that command and may find the **Windows** Terraform (e.g. under `C:\Terraform`). Linux cannot run Windows programs, so you see "Exec format error". You do **not** need to install anything extra to deploy — just get the bucket name from Windows and run the playbook in WSL.

**Option A — Get the bucket from Windows, then run the playbook in WSL (easiest)**

1. On **Windows**, open **PowerShell** or **CMD** (Start menu → type "PowerShell" or "cmd").
2. Run (use **dev** or **prod** to match the environment you are deploying to; change the path if your repo is elsewhere):
   - **Dev:** `cd C:\My-Projects\CICD-With-AI\infra\envs\dev` then `terraform output -raw artifacts_bucket`
   - **Prod:** `cd C:\My-Projects\CICD-With-AI\infra\envs\prod` then `terraform output -raw artifacts_bucket`
3. **Copy** the one line that is printed (the bucket name).
4. In **WSL**, go to the repo and run the playbook. Replace `PASTE_BUCKET_NAME_HERE` with what you copied. For **prod** add `-e env=prod`:
   ```bash
   cd /mnt/c/My-Projects/CICD-With-AI
   export ANSIBLE_CONFIG=/mnt/c/My-Projects/CICD-With-AI/ansible.cfg
   ansible-playbook -i ansible/inventory/ec2_dev.aws_ec2.yml ansible/playbooks/deploy.yml -e ssm_bucket=PASTE_BUCKET_NAME_HERE
   ```
   For **prod** use `ec2_prod.aws_ec2.yml`, the prod bucket, and add `-e env=prod`.

**Option B — Install Linux Terraform in WSL (optional)**

If you prefer to run `terraform` inside WSL, install the **Linux** Terraform. Then `terraform output -raw artifacts_bucket` will work from WSL:

```bash
# One-time: install Terraform in WSL (Ubuntu)
sudo apt update && sudo apt install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform
# Ensure WSL uses this terraform (not Windows): which terraform should show /usr/bin/terraform
```

If your Windows `PATH` is inherited in WSL and finds `C:\Terraform` first, run Terraform by full path in WSL: `/usr/bin/terraform output -raw artifacts_bucket` (from `infra/envs/dev`), or adjust WSL `PATH` so `/usr/bin` comes before `/mnt/c/...`.

### "No inventory was parsed, only implicit localhost" / "provided hosts list is empty"

Usually caused by: (1) inventory file **not** named `*.aws_ec2.yml`, (2) collections/boto3 not in the venv, (3) `ansible.cfg` not loaded (set `ANSIBLE_CONFIG` when repo is on `/mnt/c`), or (4) AWS credentials not set in WSL. Fix those first; then the EC2 inventory plugin can run and discover your instances (ensure instances are tagged `Env=dev` or `Env=prod` in the same region).

## Workaround: Ansible 2.13 on Windows

If you want to run everything in the **same repo on native Windows** (PowerShell or CMD) without WSL, pin Ansible to **2.13**, which does not use `os.get_blocking()` and can run on Windows.

**One-time setup (from repo root in PowerShell):**

```powershell
cd C:\My-Projects\CICD-With-AI
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install "ansible>=2.13,<2.14"
ansible-galaxy collection install -r ansible/requirements.yml --force
```

Then deploy from the same repo in PowerShell (get bucket from `terraform output -raw artifacts_bucket` in `infra/envs/dev`):

```powershell
ansible-playbook -i ansible/inventory/ec2_dev.aws_ec2.yml ansible/playbooks/deploy.yml -e ssm_bucket=YOUR_ARTIFACTS_BUCKET
```

**Caveats:** Ansible does not officially support Windows as a control node; 2.13 is older and may miss fixes or features from 2.14+. Use for local convenience; for CI or production automation, prefer WSL or a Linux runner.

## Install Ansible and collections (Linux / macOS)

On **Windows** use the [WSL setup](#wsl-setup-step-by-step-for-beginners) above. On **Linux/macOS**: run `ansible-playbook` from the **repo root**; install Ansible and collections in a venv (`python3 -m venv .venv` then `pip install ansible` and `ansible-galaxy collection install -r ansible/requirements.yml --force -p "$(python -c 'import site; print(site.getsitepackages()[0])')"`) or with `pip install --user ansible` plus the same galaxy command. See **RUN_COMMANDS_ORDER.md** §5a for the exact command order.
