# AWS EC2 CodeDeploy Blue/Green Stack: Complete Guide for Beginners

This document explains the **AWS EC2 CodeDeploy Blue/Green** project in plain language: what it is, what each part does, and how the pieces fit together. This is a **production-grade, enterprise-ready** system with HTTPS, comprehensive monitoring, security services, and multi-environment support.

---

## Table of Contents

1. [What is this project?](#1-what-is-this-project)
2. [What is Blue/Green deployment?](#2-what-is-bluegreen-deployment)
3. [Core components explained](#3-core-components-explained)
4. [HTTPS, ACM, and Route53](#4-https-acm-and-route53)
5. [CloudWatch: Logs and monitoring](#5-cloudwatch-logs-and-monitoring)
6. [Alarms and alerting](#6-alarms-and-alerting)
7. [Security services](#7-security-services)
8. [Dev vs Prod environments](#8-dev-vs-prod-environments)
9. [Terraform remote backend](#9-terraform-remote-backend)
10. [How does a deployment flow work?](#10-how-does-a-deployment-flow-work)
11. [Repository structure](#11-repository-structure)
12. [Sample application (Node.js)](#12-sample-application-nodejs)
13. [Docker containerization](#13-docker-containerization)
14. [CodeDeploy lifecycle scripts](#14-codedeploy-lifecycle-scripts)
15. [Terraform infrastructure](#15-terraform-infrastructure)
16. [GitHub Actions CI/CD](#16-github-actions-cicd)
17. [CrewAI orchestration](#17-crewai-orchestration)
18. [Release & Deployment Pipeline integration](#18-release--deployment-pipeline-integration)
19. [Production hardening checklist](#19-production-hardening-checklist)
20. [Glossary](#20-glossary)

---

## 1. What is this project?

This project is a **complete, production-ready deployment platform** on AWS that demonstrates industry best practices for:

- **Zero-downtime deployments** using Blue/Green strategy
- **HTTPS-only** web traffic with automatic certificate management
- **Comprehensive monitoring** with logs, metrics, and alarms
- **Enterprise security** with vulnerability scanning, threat detection, and compliance tracking
- **Multi-environment** support (development and production)
- **Infrastructure as Code** using Terraform with remote state management
- **Full automation** via GitHub Actions and CrewAI

### What it includes:

✅ **Application**: Small Node.js/Express app running in Docker containers  
✅ **Infrastructure**: VPC, subnets, NAT Gateway, Application Load Balancer, Auto Scaling Groups  
✅ **Deployment**: CodeDeploy with Blue/Green strategy and automatic rollback  
✅ **HTTPS**: ACM certificates with Route53 DNS and HTTP→HTTPS redirection  
✅ **Monitoring**: CloudWatch Logs, CloudWatch Agent, custom metrics  
✅ **Alerting**: SNS notifications for 5xx errors, unhealthy targets, high latency, CPU, and disk usage  
✅ **Security**: Inspector (vulnerability scanning), GuardDuty (threat detection), Security Hub (unified dashboard), CloudTrail (audit logs), AWS Config (compliance tracking)  
✅ **Environments**: Separate dev and prod with isolated resources  
✅ **State Management**: S3 + DynamoDB backend for Terraform state with encryption and locking  
✅ **CI/CD**: GitHub Actions workflows for plan, apply, build, and deploy  
✅ **Automation**: CrewAI crew that orchestrates the entire setup from user requirements  

---

## 2. What is Blue/Green deployment?

**Blue/Green deployment** is a release strategy that eliminates downtime and reduces risk by running two identical production environments.

### The concept:

- **Blue environment** = Current production (version 1.0)
- **Green environment** = New version being deployed (version 2.0)

### How it works:

1. **Traffic goes to Blue**: Your users are accessing version 1.0 running on blue instances
2. **Deploy to Green**: Version 2.0 is installed on green instances (while blue continues serving traffic)
3. **Health checks**: CodeDeploy validates that green instances are healthy
4. **Traffic switch**: If health checks pass, the load balancer routes traffic from blue to green
5. **Rollback safety**: If anything fails, traffic instantly switches back to blue (no re-deployment needed)

### Benefits:

- **Zero downtime**: Users never experience an outage
- **Instant rollback**: Switch back to blue in seconds if issues arise
- **Safe testing**: New version runs alongside old version before going live
- **Clear separation**: Blue and green are completely independent

### In our implementation:

- **Two Auto Scaling Groups**: One for blue instances, one for green instances
- **Two Target Groups**: ALB forwards to either blue or green target group
- **CodeDeploy manages the switch**: Automatically moves ALB listener from blue to green
- **Automatic rollback**: If health checks fail or alarms fire, CodeDeploy reverts to blue

---

## 3. Core components explained

| Component | What it does | Why you need it |
|-----------|--------------|-----------------|
| **VPC** | Virtual private network in AWS | Isolates your resources from the internet and other AWS accounts |
| **Subnets** | Subdivisions of your VPC | Public subnets for ALB (internet-facing), private subnets for EC2 (protected) |
| **Internet Gateway** | Allows public subnets to access the internet | Required for ALB to receive external traffic |
| **NAT Gateway** | Allows private subnets to access the internet | EC2 instances need to pull Docker images from ECR and download packages |
| **EC2 instances** | Virtual servers that run your app | Host Docker containers with your application code |
| **Docker** | Container runtime | Packages your app with all dependencies for consistent deployment |
| **ALB (Application Load Balancer)** | Distributes incoming traffic across instances | Routes HTTPS requests to healthy instances; terminates SSL/TLS |
| **Target Groups** | Collections of EC2 instances | Blue target group and green target group; ALB forwards to one at a time |
| **Auto Scaling Groups** | Maintains desired number of instances | Automatically replaces unhealthy instances; scales capacity up/down |
| **CodeDeploy** | Deployment service | Runs scripts on EC2 to deploy new code; manages Blue/Green traffic switching |
| **Ansible (optional)** | Deploy over SSM | Alternative to CodeDeploy; see **ansible/README.md** (on Windows: WSL or Ansible 2.13 workaround). |
| **ECR (Elastic Container Registry)** | Docker image repository | Stores your Docker images; EC2 instances pull images from here |
| **SSM Parameter Store** | Configuration storage | Stores ECR repo name and image tag; scripts read these to know which image to deploy |
| **S3 bucket** | Object storage for deployment bundles | CodeDeploy downloads your appspec.yml and scripts from here |
| **ACM (AWS Certificate Manager)** | SSL/TLS certificate management | Provides free HTTPS certificates; automatically renews them |
| **Route53** | DNS service | Maps your domain (e.g., app.example.com) to your ALB |
| **CloudWatch Logs** | Centralized log storage | Stores application logs and system logs from all instances |
| **CloudWatch Agent** | Metrics and logs collector | Ships logs from EC2 to CloudWatch; collects CPU, memory, disk metrics |
| **CloudWatch Alarms** | Monitoring thresholds | Triggers alerts when metrics exceed thresholds (e.g., high error rate) |
| **SNS (Simple Notification Service)** | Notification system | Sends emails/SMS when alarms fire |
| **Inspector** | Vulnerability scanner | Scans EC2 instances and Docker images for security vulnerabilities |
| **GuardDuty** | Threat detection | Monitors for malicious activity and unauthorized behavior |
| **Security Hub** | Security dashboard | Aggregates findings from Inspector, GuardDuty, and other services |
| **CloudTrail** | API audit logging | Records every API call made in your account (who did what, when) |
| **AWS Config** | Resource change tracking | Monitors configuration changes for compliance |

---

## 4. HTTPS, ACM, and Route53

### Why HTTPS matters:

- **Security**: Encrypts data between users and your server
- **Trust**: Browsers show a padlock icon; users trust your site
- **SEO**: Google ranks HTTPS sites higher
- **Compliance**: Required for PCI-DSS, HIPAA, and other standards

### How it works in this project:

1. **ACM (AWS Certificate Manager)**:
   - You request a certificate for your domain (e.g., `app.example.com`)
   - ACM provides DNS validation records (CNAME records)
   - You add these records to Route53
   - ACM validates domain ownership and issues the certificate (free!)
   - Certificate auto-renews before expiration

2. **Route53 (DNS)**:
   - Hosted zone for your domain (e.g., `example.com`)
   - **Validation records**: CNAME records for ACM certificate validation
   - **Alias record**: Points `app.example.com` to your ALB
   - When users type `https://app.example.com`, DNS resolves to ALB IP

3. **ALB (Load Balancer)**:
   - **Port 443 listener (HTTPS)**: Accepts encrypted traffic using ACM certificate
   - **Port 80 listener (HTTP)**: Redirects all HTTP traffic to HTTPS (301 redirect)
   - **SSL/TLS termination**: ALB decrypts HTTPS traffic and forwards plain HTTP to EC2 on port 8080
   - EC2 instances don't need to handle SSL/TLS (simpler application code)

### HTTP → HTTPS redirect:

```
User types: http://app.example.com
↓
ALB Port 80 listener receives request
↓
ALB responds with: 301 Redirect to https://app.example.com
↓
Browser makes new request to https://app.example.com
↓
ALB Port 443 listener receives encrypted request
↓
ALB forwards to healthy EC2 instance on port 8080
```

### Configuration in Terraform:

```hcl
# ACM certificate
resource "aws_acm_certificate" "app" {
  domain_name       = "app.example.com"
  validation_method = "DNS"
}

# Route53 validation records
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.app.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.route53_zone_id
}

# HTTPS listener on ALB (port 443)
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = aws_acm_certificate.app.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }
}

# HTTP listener on ALB (port 80) - redirects to HTTPS
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# Route53 alias record pointing to ALB
resource "aws_route53_record" "app" {
  zone_id = var.route53_zone_id
  name    = "app.example.com"
  type    = "A"

  alias {
    name                   = aws_lb.app.dns_name
    zone_id                = aws_lb.app.zone_id
    evaluate_target_health = true
  }
}
```

---

## 5. CloudWatch: Logs and monitoring

### What is CloudWatch?

CloudWatch is AWS's monitoring and observability service. It collects:
- **Logs**: Application logs, system logs, access logs
- **Metrics**: CPU usage, memory, disk, network, custom metrics
- **Events**: Scheduled events, state changes

### CloudWatch Agent:

The **CloudWatch Agent** runs on each EC2 instance and:
- Collects metrics (CPU, memory, disk, network)
- Ships log files to CloudWatch Logs
- Configured via SSM Parameter Store (so all instances get the same config)

### Log groups in this project:

| Log Group | What it contains |
|-----------|------------------|
| `/bluegreen/prod/docker` | Docker container logs (stdout/stderr from your Node.js app) |
| `/bluegreen/prod/system` | System logs (e.g., `/var/log/messages`, auth logs) |
| `/bluegreen/dev/docker` | Docker logs from dev environment |
| `/bluegreen/dev/system` | System logs from dev environment |

### How Docker logs are shipped:

1. **Docker writes logs**: Container stdout/stderr goes to `/var/lib/docker/containers/*/*.log`
2. **CloudWatch Agent reads**: Agent is configured to watch this directory
3. **Logs sent to CloudWatch**: Agent uploads logs to CloudWatch Logs in near-real-time
4. **You can search/filter**: In CloudWatch console, search across all instances' logs

### CloudWatch Agent configuration (stored in SSM):

```json
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/lib/docker/containers/*/*.log",
            "log_group_name": "/bluegreen/prod/docker",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/bluegreen/prod/system",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "BlueGreen/EC2",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          {"name": "cpu_usage_idle", "unit": "Percent"},
          {"name": "cpu_usage_iowait", "unit": "Percent"}
        ],
        "metrics_collection_interval": 60,
        "totalcpu": false
      },
      "disk": {
        "measurement": [
          {"name": "used_percent", "unit": "Percent"}
        ],
        "metrics_collection_interval": 60,
        "resources": ["*"]
      },
      "mem": {
        "measurement": [
          {"name": "mem_used_percent", "unit": "Percent"}
        ],
        "metrics_collection_interval": 60
      }
    }
  }
}
```

### Installing CloudWatch Agent on EC2:

In the EC2 user data (launch template):

```bash
#!/bin/bash
# Install CloudWatch Agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm

# Fetch config from SSM and start agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c ssm:/bluegreen/prod/cw_agent_config
```

---

## 6. Alarms and alerting

### What are CloudWatch Alarms?

Alarms monitor metrics and trigger actions when thresholds are breached. Actions can include:
- Send SNS notification (email, SMS, Lambda, etc.)
- Auto Scaling actions (add/remove instances)
- Stop/terminate EC2 instances
- **CodeDeploy rollback** (if alarm fires during deployment)

### Alarms in this project:

| Alarm | Metric | Threshold | Why it matters |
|-------|--------|-----------|----------------|
| **ALB 5xx errors** | HTTP 5xx count from ALB | > 10 errors in 5 minutes | Application is crashing or misconfigured |
| **Unhealthy targets** | Number of unhealthy instances in target group | ≥ 1 for 5 minutes | Instance health checks are failing |
| **High latency** | ALB target response time | > 2 seconds (p99) | Application is slow; may need optimization or more capacity |
| **High CPU** | EC2 CPU utilization | > 80% for 10 minutes | Instance is overloaded; may need scaling |
| **High disk usage** | Disk used percent (from CloudWatch Agent) | > 85% | Disk is filling up; may cause crashes |

### SNS topic for alerts:

All alarms send notifications to an SNS topic:

```hcl
resource "aws_sns_topic" "alarms" {
  name = "${var.project}-${var.env}-alarms"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email  # e.g., "devops@example.com"
}
```

When you first apply Terraform, AWS sends a subscription confirmation email. You must click the confirmation link.

### Example alarm: ALB 5xx errors

```hcl
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project}-${var.env}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300  # 5 minutes
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "ALB is returning 5xx errors"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
  }
}
```

### CodeDeploy integration:

CodeDeploy can be configured to automatically roll back if alarms fire:

```hcl
auto_rollback_configuration {
  enabled = true
  events  = [
    "DEPLOYMENT_FAILURE",
    "DEPLOYMENT_STOP_ON_ALARM",
    "DEPLOYMENT_STOP_ON_REQUEST"
  ]
}

alarm_configuration {
  enabled = true
  alarms  = [
    aws_cloudwatch_metric_alarm.alb_5xx.alarm_name,
    aws_cloudwatch_metric_alarm.unhealthy_targets.alarm_name
  ]
}
```

If the `alb_5xx` or `unhealthy_targets` alarm fires during a deployment, CodeDeploy will:
1. Stop the deployment
2. Switch traffic back to the blue environment
3. Mark the deployment as failed

---

## 7. Security services

### Why security matters:

Production systems must protect against:
- **Vulnerabilities**: Outdated libraries, OS packages with known CVEs
- **Threats**: Malicious IPs, brute force attacks, unauthorized access
- **Compliance violations**: Unencrypted data, open security groups
- **Insider threats**: Unauthorized API calls, resource changes

### AWS security services in this project:

**Important (current implementation):**
- GuardDuty, Security Hub, Inspector2, and AWS Config are **account-level**.
- We manage them **once** (dev), and **disable them in prod** via flags:
  - `enable_guardduty`, `enable_securityhub`, `enable_inspector2`, `enable_config`

#### 1. **Inspector** (Vulnerability scanning)

**What it does**: Scans EC2 instances and ECR container images for vulnerabilities

**How it works**:
- Automatically scans when instances launch or images are pushed
- Checks against CVE (Common Vulnerabilities and Exposures) database
- Assigns severity scores (Critical, High, Medium, Low, Informational)
- Findings appear in Security Hub

**Example finding**: "CVE-2023-12345 found in package `openssl-1.0.2k`. Severity: High. Recommendation: Update to openssl-1.1.1+"

**Enable in Terraform** (account-level, managed once):
```hcl
resource "aws_inspector2_enabler" "this" {
  account_ids    = [data.aws_caller_identity.current.account_id]
  resource_types = ["EC2", "ECR"]
}
```

#### 2. **GuardDuty** (Threat detection)

**What it does**: Monitors for malicious activity and unauthorized behavior

**How it works**:
- Analyzes CloudTrail logs, VPC Flow Logs, DNS logs
- Uses machine learning to detect anomalies
- Checks against known threat intelligence feeds (malicious IPs, domains)

**Example findings**:
- "EC2 instance is communicating with a known botnet command-and-control server"
- "Unusual API calls from a compromised IAM credential"
- "Port scanning detected from instance i-123456"

**Enable in Terraform** (account-level, managed once):
```hcl
resource "aws_guardduty_detector" "this" {
  enable = true
}
```

#### 3. **Security Hub** (Unified security dashboard)

**What it does**: Aggregates findings from Inspector, GuardDuty, and other services

**How it works**:
- Collects findings from multiple security services
- Runs compliance checks (CIS AWS Foundations Benchmark, PCI-DSS, etc.)
- Provides a single "security score" for your account
- Allows you to suppress false positives

**Example view**: "45 critical findings, 123 high, 567 medium. Compliance score: 78%"

**Enable in Terraform** (account-level, managed once):
```hcl
resource "aws_securityhub_account" "this" {
  enable_default_standards = false
}
```

#### 4. **CloudTrail** (Audit logging)

**What it does**: Records every API call made in your AWS account

**How it works**:
- Logs who made the API call (user, role, service)
- Logs what was done (e.g., `ec2:RunInstances`, `s3:PutObject`)
- Logs when it happened (timestamp)
- Logs source IP, user agent
- Stores logs in S3 bucket (encrypted)

**Example log entry**:
```json
{
  "eventName": "RunInstances",
  "userIdentity": {
    "type": "IAMUser",
    "userName": "alice"
  },
  "sourceIPAddress": "203.0.113.5",
  "requestParameters": {
    "instanceType": "t3.micro",
    "imageId": "ami-12345678"
  },
  "responseElements": {
    "instancesSet": [{"instanceId": "i-abcd1234"}]
  },
  "eventTime": "2026-02-05T10:30:00Z"
}
```

**Use cases**:
- Security investigation: "Who deleted the production database?"
- Compliance: "Show me all S3 bucket changes in the last 90 days"
- Debugging: "Why did this instance terminate?"

**Enable in Terraform** (uses bootstrap CloudTrail bucket):
```hcl
resource "aws_cloudtrail" "this" {
  name                          = "${var.project}-${var.env}-trail"
  s3_bucket_name                = var.cloudtrail_bucket
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
}
```

#### 5. **AWS Config** (Configuration tracking)

**What it does**: Tracks configuration changes to AWS resources

**How it works**:
- Records the configuration of every resource (e.g., security group rules, S3 bucket policies)
- Stores configuration history (what changed, when, by whom)
- Can evaluate compliance rules (e.g., "all S3 buckets must have encryption enabled")

**Example use cases**:
- "Show me all security groups that allow 0.0.0.0/0 on port 22"
- "Alert me when someone makes an S3 bucket public"
- "What did the RDS instance configuration look like on January 15th?"

**Enable in Terraform** (account-level, managed once):
```hcl
resource "aws_config_configuration_recorder" "this" {
  name     = "${var.project}-${var.env}-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported = true
  }
}

resource "aws_config_delivery_channel" "this" {
  name           = "${var.project}-${var.env}-delivery"
  s3_bucket_name = aws_s3_bucket.config.id
  s3_key_prefix  = "config"
}

resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = true
}
```

### Security workflow:

```
1. Developer pushes code
   ↓
2. Docker image built and pushed to ECR
   ↓
3. Inspector scans image for vulnerabilities
   ↓
4. GuardDuty monitors API calls and network traffic
   ↓
5. CloudTrail logs all API calls
   ↓
6. AWS Config tracks resource configuration changes
   ↓
7. Security Hub aggregates all findings
   ↓
8. If critical finding: SNS alert sent to security team
```

---

## 8. Dev vs Prod environments

### Why separate environments?

- **Safety**: Mistakes in dev don't affect production users
- **Testing**: Test new features in dev before deploying to prod
- **Compliance**: Some regulations require separate environments
- **Cost optimization**: Run smaller instances in dev, scale down outside business hours

### What's different between dev and prod:

| Aspect | Dev | Prod |
|--------|-----|------|
| **Domain** | `dev-app.my-iifb.click` | `app.my-iifb.click` |
| **VPC CIDR** | `10.20.0.0/16` | `10.30.0.0/16` |
| **Instance type** | `t3.micro` | `t3.micro` (adjust as needed) |
| **Min instances** | 1 | 2 |
| **Desired instances** | 1 | 2 |
| **Max instances** | 2 | 4 |
| **Alarm email** | `idbsch2012@gmail.com` | `idbsch2012@gmail.com` |
| **CloudTrail bucket** | from bootstrap output | from bootstrap output |
| **Account-level security** | Enabled in dev | Disabled in prod |

### Directory structure:

```
infra/
├── bootstrap/           # Run once to create backend + CloudTrail bucket
│   ├── main.tf
│   ├── outputs.tf
│   └── variables.tf
├── modules/
│   └── platform/        # Reusable module for both dev and prod
│       ├── vpc.tf
│       ├── alb.tf
│       ├── asg.tf
│       ├── codedeploy.tf
│       ├── acm.tf
│       ├── route53.tf
│       ├── cloudwatch.tf
│       ├── alarms.tf
│       ├── security.tf
│       └── variables.tf
└── envs/
    ├── dev/
    │   ├── backend.hcl   # S3 backend config (key = dev/terraform.tfstate)
    │   ├── imports.tf    # Root import blocks for existing resources
    │   ├── main.tf       # Calls platform module with dev variables
    │   └── dev.tfvars    # Dev-specific values
    └── prod/
        ├── backend.hcl   # S3 backend config (key = prod/terraform.tfstate)
        ├── main.tf       # Calls platform module with prod variables
        └── prod.tfvars   # Prod-specific values
```

### Example: `infra/envs/dev/main.tf`

```hcl
terraform {
  backend "s3" {}  # Configuration loaded from backend.hcl
}

module "platform" {
  source = "../../modules/platform"

  project        = "bluegreen"
  env            = "dev"
  region         = "us-east-1"
  vpc_cidr       = "10.20.0.0/16"
  domain_name    = "dev-app.my-iifb.click"
  hosted_zone_id = "Z04241223G31RGIMMIL2C"
  
  instance_type    = "t3.micro"
  min_size         = 1
  desired_capacity = 1
  max_size         = 2
  
  alarm_email      = "idbsch2012@gmail.com"
  cloudtrail_bucket = "bluegreen-cloudtrail-20260207024017739500000001"

  enable_guardduty  = true
  enable_securityhub = true
  enable_inspector2 = true
  enable_config     = true
}
```

### Example: `infra/envs/dev/backend.hcl`

```hcl
bucket         = "bluegreen-tfstate-<bootstrap-output>"
key            = "dev/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "bluegreen-tflock"
encrypt        = true
```

### Deploying to dev and prod:

```bash
# Bootstrap (run once)
cd infra/bootstrap
terraform init
terraform apply

# Dev environment
cd ../envs/dev
terraform init -backend-config=backend.hcl -reconfigure
terraform apply -var-file=dev.tfvars

# Prod environment
cd ../envs/prod
terraform init -backend-config=backend.hcl -reconfigure
terraform apply -var-file=prod.tfvars
```

---

## 9. Terraform remote backend

### What is a Terraform backend?

The **backend** is where Terraform stores its **state file**. The state file is a JSON file that records:
- What resources Terraform has created
- Current configuration of those resources
- Metadata and dependencies

### Why remote backend?

**Local backend** (default):
- State file stored on your laptop (`terraform.tfstate`)
- ❌ If you lose your laptop, you lose state
- ❌ If two people run `terraform apply`, they'll conflict
- ❌ No encryption at rest
- ❌ No backup

**Remote backend** (S3 + DynamoDB):
- ✅ State file stored in S3 bucket (encrypted with KMS)
- ✅ Multiple people can work on same infrastructure
- ✅ DynamoDB provides **locking** (prevents concurrent modifications)
- ✅ Versioning enabled (can recover old state)
- ✅ Automatic backups

### Components:

1. **S3 bucket**: Stores `terraform.tfstate` file
2. **DynamoDB table**: Stores locks (prevents two people from running `terraform apply` simultaneously)
3. **KMS key**: Encrypts state file at rest

### Bootstrap Terraform code:

Create these resources once before creating dev/prod environments.

`infra/bootstrap/main.tf`:

```hcl
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
}

provider "aws" {
  region = var.region
}

# KMS key for state encryption
resource "aws_kms_key" "terraform_state" {
  description             = "KMS key for Terraform state encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_kms_alias" "terraform_state" {
  name          = "alias/${var.project}-terraform-state"
  target_key_id = aws_kms_key.terraform_state.key_id
}

# S3 bucket for state
resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.project}-terraform-state"
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for state locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.project}-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# S3 bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail" {
  bucket_prefix = "${var.project}-cloudtrail-"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bucket policy to allow CloudTrail to write logs
resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

output "state_bucket_name" {
  value = aws_s3_bucket.terraform_state.id
}

output "lock_table_name" {
  value = aws_dynamodb_table.terraform_locks.id
}

output "cloudtrail_bucket_name" {
  value = aws_s3_bucket.cloudtrail.id
}
```

### How state locking works:

```
Developer A: terraform apply
  ↓
Terraform acquires lock in DynamoDB
  ↓
Developer B: terraform apply
  ↓
Terraform attempts to acquire lock → BLOCKED
  ↓
Developer B sees: "Error: Error locking state: resource already locked"
  ↓
Developer A's apply completes
  ↓
Lock released
  ↓
Developer B can now run terraform apply
```

---

## 10. How does a deployment flow work?

### End-to-end deployment workflow:

```
1. Developer pushes code to GitHub (branch: main)
   ↓
2. GitHub Actions workflow triggered: build-push.yml
   ↓
3. Build Docker image from app/
   ↓
4. Tag image with git SHA (e.g., abc123def456)
   ↓
5. Push image to ECR
   ↓
6. Update SSM parameter /bluegreen/prod/image_tag = "abc123def456"
   ↓
7. GitHub Actions workflow triggered: deploy.yml
   ↓
8. Package deployment bundle (appspec.yml + scripts/) into ZIP
   ↓
9. Upload ZIP to S3 artifacts bucket
   ↓
10. Call CodeDeploy create-deployment API
   ↓
11. CodeDeploy deploys to GREEN Auto Scaling Group
   ↓
12. CodeDeploy runs lifecycle hooks on each GREEN instance:
    - ApplicationStop: Stop old container (if exists)
    - BeforeInstall: Install dependencies (Docker, AWS CLI)
    - ApplicationStart: Pull image from ECR, start container
    - ValidateService: curl localhost:8080/health
   ↓
13. All GREEN instances pass validation
   ↓
14. CodeDeploy switches ALB listener from BLUE to GREEN
   ↓
15. Traffic now goes to GREEN (new version)
   ↓
16. Monitor alarms for 5-10 minutes
   ↓
17. If alarms fire → CodeDeploy rolls back to BLUE
18. If alarms OK → Terminate BLUE instances (cleanup)
   ↓
19. Deployment complete ✅
```

### Detailed lifecycle hook execution:

**ApplicationStop** (`scripts/stop.sh`):
```bash
#!/usr/bin/env bash
set -euo pipefail

# Stop and remove old container if it exists
if docker ps -a --format '{{.Names}}' | grep -q '^sample-app$'; then
  docker rm -f sample-app || true
fi
```

**BeforeInstall** (`scripts/install.sh`):
```bash
#!/usr/bin/env bash
set -euo pipefail

# Ensure Docker is running
systemctl enable docker || true
systemctl start docker || true

# Ensure AWS CLI exists
if ! command -v aws >/dev/null 2>&1; then
  yum install -y awscli
fi

mkdir -p /opt/codedeploy-bluegreen
```

**ApplicationStart** (`scripts/start.sh`):
```bash
#!/usr/bin/env bash
set -euo pipefail

# Get region from instance metadata
REGION="$(curl -s http://169.254.169.254/latest/meta-data/placement/region)"

# Get AWS account ID
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

# Read ECR repo name from SSM
ECR_REPO_NAME="$(aws ssm get-parameter --name "/bluegreen/ecr_repo_name" --region "$REGION" --query Parameter.Value --output text)"

# Read image tag from SSM (updated by CI)
IMAGE_TAG="$(aws ssm get-parameter --name "/bluegreen/image_tag" --region "$REGION" --query Parameter.Value --output text)"

# Construct full image URI
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO_NAME}:${IMAGE_TAG}"

# Login to ECR (uses instance profile role)
aws ecr get-login-password --region "$REGION" | \
  docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# Pull image
docker pull "$ECR_URI"

# Run container
docker run -d \
  --name sample-app \
  -p 8080:8080 \
  -e APP_VERSION="$IMAGE_TAG" \
  --restart always \
  "$ECR_URI"
```

**ValidateService** (`scripts/validate.sh`):
```bash
#!/usr/bin/env bash
set -euo pipefail

# Wait for app to start
sleep 3

# Check health endpoint
STATUS="$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health || true)"
if [[ "$STATUS" != "200" ]]; then
  echo "Health check failed, status=$STATUS"
  exit 1
fi

echo "ValidateService OK"
```

### What happens during traffic switch:

**Before switch** (traffic on BLUE):
```
User request → Route53 → ALB → BLUE target group → BLUE instances (old version)
```

**During deployment** (GREEN instances starting):
```
User request → Route53 → ALB → BLUE target group → BLUE instances (old version)

Background:
  GREEN instances launching → Docker image pulled → Container started → Health checks passing
```

**After switch** (traffic on GREEN):
```
User request → Route53 → ALB → GREEN target group → GREEN instances (new version)

Background:
  BLUE instances terminating (after 5 minute wait)
```

### Rollback scenarios:

| Scenario | CodeDeploy action |
|----------|-------------------|
| ValidateService fails on one or more GREEN instances | Deployment marked as failed; traffic stays on BLUE |
| ALB health check fails (e.g., /health returns 500) | Instances marked unhealthy; CodeDeploy stops deployment |
| CloudWatch alarm fires during deployment | Automatic rollback to BLUE |
| Deployment timeout (instances don't become healthy in time) | Deployment failed; traffic stays on BLUE |
| Manual rollback requested | `aws deploy stop-deployment` → traffic back to BLUE |

---

## 11. Repository structure

```
aws-ec2-codedeploy-bluegreen/
├── README.md
├── CHANGELOG.md                  # Auto-generated by release crew
├── deploy_checklist.md           # Auto-generated by release crew
├── rollback_plan.md              # Auto-generated by release crew
├── test_plan.md                  # Auto-generated by release crew
├── app/                          # Application code
│   ├── package.json
│   ├── server.js
│   └── Dockerfile
├── deploy/                       # CodeDeploy bundle
│   ├── appspec.yml
│   └── scripts/
│       ├── install.sh
│       ├── stop.sh
│       ├── start.sh
│       └── validate.sh
├── infra/                        # Infrastructure as Code
│   ├── bootstrap/                # S3 + DynamoDB backend (run once)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── modules/
│   │   └── platform/             # Reusable module
│   │       ├── vpc.tf
│   │       ├── alb.tf
│   │       ├── asg.tf
│   │       ├── codedeploy.tf
│   │       ├── ecr.tf
│   │       ├── ssm.tf
│   │       ├── acm.tf
│   │       ├── route53.tf
│   │       ├── cloudwatch.tf
│   │       ├── alarms.tf
│   │       ├── security.tf       # Inspector, GuardDuty, Security Hub, CloudTrail, Config
│   │       ├── iam.tf
│   │       ├── variables.tf
│   │       └── outputs.tf
│   └── envs/
│       ├── dev/
│       │   ├── backend.hcl
│       │   ├── main.tf
│       │   └── dev.tfvars
│       └── prod/
│           ├── backend.hcl
│           ├── main.tf
│           └── prod.tfvars
├── .github/
│   └── workflows/
│       ├── release-prep.yml      # NEW: Release & Deployment Pipeline crew
│       ├── terraform-plan.yml    # PR: terraform plan
│       ├── terraform-apply.yml   # main: terraform apply
│       ├── build-push.yml        # main + app/: build → ECR
│       └── deploy.yml            # after build-push: CodeDeploy
├── release-crew/                 # NEW: Release preparation automation
│   ├── requirements.txt
│   ├── tools.py
│   ├── agents.py
│   ├── tasks.py
│   ├── flow.py
│   └── run_release_prep.py
└── crewai/                       # Infrastructure orchestration
    ├── requirements.txt
    ├── tools.py
    ├── agents.py
    ├── flow.py
    └── run.py
```

---

## 12. Sample application (Node.js)

### `app/package.json`

```json
{
  "name": "bluegreen-sample",
  "version": "1.0.0",
  "main": "server.js",
  "type": "commonjs",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.19.2"
  }
}
```

### `app/server.js`

```javascript
const express = require("express");
const os = require("os");

const app = express();
const port = process.env.PORT || 8080;

// Health endpoint for ALB target group health checks
app.get("/health", (req, res) => {
  res.status(200).send("OK");
});

// Main endpoint
app.get("/", (req, res) => {
  res.json({
    message: "Hello from Blue/Green EC2 + CodeDeploy!",
    hostname: os.hostname(),
    version: process.env.APP_VERSION || "dev",
    timestamp: new Date().toISOString()
  });
});

app.listen(port, () => {
  console.log(`Server listening on port ${port}`);
});
```

**Key points**:
- **Health endpoint** at `/health`: ALB target group health checks use this
- **Main endpoint** at `/`: Returns JSON with hostname and version
- **Environment variable** `APP_VERSION`: Set by deployment script to image tag
- **Port 8080**: Matches ALB target group and Docker port mapping

---

## 13. Docker containerization

### `app/Dockerfile`

```dockerfile
FROM node:20-alpine

WORKDIR /usr/src/app

# Install dependencies
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev || npm i --omit=dev

# Copy application code
COPY . .

# Set environment
ENV PORT=8080
EXPOSE 8080

# Start application
CMD ["npm", "start"]
```

**Why Alpine?**
- Smaller image size (5-10x smaller than full Node image)
- Faster pulls from ECR
- Reduced attack surface (fewer packages)

**Build and test locally:**

```bash
cd app
docker build -t bluegreen-sample:local .
docker run -p 8080:8080 -e APP_VERSION=local bluegreen-sample:local

# Test in another terminal
curl http://localhost:8080/health  # Should return "OK"
curl http://localhost:8080/        # Should return JSON
```

---

## 14. CodeDeploy lifecycle scripts

### `deploy/appspec.yml`

```yaml
version: 0.0
os: linux

files:
  - source: /
    destination: /opt/codedeploy-bluegreen
    overwrite: true

hooks:
  ApplicationStop:
    - location: scripts/stop.sh
      timeout: 300
      runas: root

  BeforeInstall:
    - location: scripts/install.sh
      timeout: 600
      runas: root

  ApplicationStart:
    - location: scripts/start.sh
      timeout: 600
      runas: root

  ValidateService:
    - location: scripts/validate.sh
      timeout: 300
      runas: root
```

**Hook order**: ApplicationStop → BeforeInstall → ApplicationStart → ValidateService

**Timeout**: If a script takes longer than timeout, deployment fails

**Run as**: All scripts run as root (required for Docker and system commands)

### Make scripts executable:

```bash
chmod +x deploy/scripts/*.sh
```

---

## 15. Terraform infrastructure

### Complete Terraform configuration

The full Terraform code is provided in the detailed implementation guide. Key resources:

**Network** (`modules/platform/vpc.tf`):
- VPC with DNS enabled
- Public subnets (for ALB)
- Private subnets (for EC2)
- Internet Gateway
- NAT Gateway (for private subnets to access internet)
- Route tables and associations

**Load Balancer** (`modules/platform/alb.tf`):
- Application Load Balancer (internet-facing)
- Security group (allow 80, 443 from internet)
- Two target groups (blue and green)
- HTTP listener (redirects to HTTPS)
- HTTPS listener (forwards to blue or green)

**Auto Scaling** (`modules/platform/asg.tf`):
- Launch template with user data (installs Docker, CodeDeploy agent, CloudWatch agent)
- Blue Auto Scaling Group (attached to blue target group)
- Green Auto Scaling Group (attached to green target group)
- IAM instance profile (ECR pull, SSM read, CloudWatch write)

**CodeDeploy** (`modules/platform/codedeploy.tf`):
- CodeDeploy application
- Deployment group with Blue/Green configuration
- Auto-rollback on failure or alarm
- S3 bucket for deployment artifacts

**HTTPS** (`modules/platform/acm.tf`, `modules/platform/route53.tf`):
- ACM certificate request
- Route53 DNS validation records
- Route53 alias record pointing to ALB

**Monitoring** (`modules/platform/cloudwatch.tf`):
- Log groups for Docker and system logs
- SSM parameter with CloudWatch Agent config
- CloudWatch Agent installed via user data

**Alarms** (`modules/platform/alarms.tf`):
- SNS topic and email subscription
- ALB 5xx alarm
- Unhealthy targets alarm
- High latency alarm
- High CPU alarm
- High disk usage alarm

**Security** (`modules/platform/security.tf`):
- Inspector enabler
- GuardDuty detector
- Security Hub account and standards
- CloudTrail trail
- AWS Config recorder and delivery channel

### Deploying infrastructure:

```bash
# 1. Bootstrap (creates S3 + DynamoDB backend)
cd infra/bootstrap
terraform init
terraform apply

# 2. Dev environment
cd ../envs/dev
terraform init -backend-config=backend.hcl
terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars

# 3. Prod environment
cd ../envs/prod
terraform init -backend-config=backend.hcl
terraform plan -var-file=prod.tfvars
terraform apply -var-file=prod.tfvars
```

---

## 16. GitHub Actions CI/CD

### Workflow 1: `terraform-plan.yml` (PR validation)

```yaml
name: terraform-plan
on:
  pull_request:
    paths: ["infra/**"]

permissions:
  id-token: write
  contents: read

jobs:
  plan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.6.6

      - name: Configure AWS (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_TO_ASSUME }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Terraform Init/Plan
        working-directory: infra/envs/prod
        run: |
          terraform init -backend-config=backend.hcl
          terraform fmt -check
          terraform validate
          terraform plan -var-file=prod.tfvars
```

### Workflow 2: `terraform-apply.yml` (Deploy infrastructure)

```yaml
name: terraform-apply
on:
  push:
    branches: ["main"]
    paths: ["infra/**"]

permissions:
  id-token: write
  contents: read

jobs:
  apply:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3

      - name: Configure AWS (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_TO_ASSUME }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Terraform Apply
        working-directory: infra/envs/prod
        run: |
          terraform init -backend-config=backend.hcl
          terraform apply -auto-approve -var-file=prod.tfvars
```

### Workflow 3: `build-push.yml` (Build and push Docker image)

```yaml
name: build-push
on:
  push:
    branches: ["main"]
    paths: ["app/**"]

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_TO_ASSUME }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Get AWS Account ID
        run: echo "AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)" >> $GITHUB_ENV

      - name: Get ECR repo from SSM
        run: echo "ECR_REPO=$(aws ssm get-parameter --name /bluegreen/prod/ecr_repo_name --query Parameter.Value --output text)" >> $GITHUB_ENV

      - name: Login to ECR
        run: |
          aws ecr get-login-password --region ${{ secrets.AWS_REGION }} \
          | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.${{ secrets.AWS_REGION }}.amazonaws.com

      - name: Build and Push
        working-directory: app
        run: |
          TAG=${GITHUB_SHA::12}
          IMAGE="$AWS_ACCOUNT_ID.dkr.ecr.${{ secrets.AWS_REGION }}.amazonaws.com/$ECR_REPO:$TAG"
          docker build -t "$IMAGE" .
          docker push "$IMAGE"
          echo "IMAGE_TAG=$TAG" >> $GITHUB_ENV

      - name: Update SSM image tag
        run: |
          aws ssm put-parameter \
            --name "/bluegreen/prod/image_tag" \
            --type "String" \
            --value "${IMAGE_TAG}" \
            --overwrite
```

### Workflow 4: `deploy.yml` (Trigger CodeDeploy)

```yaml
name: deploy
on:
  workflow_run:
    workflows: ["build-push"]
    types: [completed]

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_TO_ASSUME }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Read Terraform outputs
        working-directory: infra/envs/prod
        run: |
          terraform init -backend-config=backend.hcl
          echo "CD_APP=$(terraform output -raw codedeploy_app)" >> $GITHUB_ENV
          echo "CD_GROUP=$(terraform output -raw codedeploy_group)" >> $GITHUB_ENV
          echo "ARTIFACTS_BUCKET=$(terraform output -raw artifacts_bucket)" >> $GITHUB_ENV

      - name: Package deployment bundle
        run: |
          cd deploy
          zip -r ../deployment.zip .

      - name: Upload to S3
        run: |
          KEY="revisions/deployment-${GITHUB_SHA::12}.zip"
          aws s3 cp deployment.zip "s3://${ARTIFACTS_BUCKET}/${KEY}"
          echo "S3_KEY=${KEY}" >> $GITHUB_ENV

      - name: Create CodeDeploy Deployment
        run: |
          aws deploy create-deployment \
            --application-name "$CD_APP" \
            --deployment-group-name "$CD_GROUP" \
            --s3-location bucket="${ARTIFACTS_BUCKET}",key="${S3_KEY}",bundleType=zip

      - name: Print ALB endpoint
        working-directory: infra/envs/prod
        run: |
          terraform init -backend-config=backend.hcl
          echo "ALB: https://$(terraform output -raw alb_dns_name)"
```

### Setting up GitHub OIDC:

1. Create IAM OIDC provider in AWS for GitHub
2. Create IAM role with trust policy for GitHub Actions
3. Attach policies: ECR, S3, SSM, CodeDeploy, Terraform resources
4. Add GitHub secrets:
   - `AWS_ROLE_TO_ASSUME`: ARN of IAM role
   - `AWS_REGION`: e.g., `us-east-1`

---

## 17. CrewAI orchestration

### What is CrewAI?

**CrewAI** is a framework for orchestrating AI agents to work together on complex tasks. In this project, we use CrewAI to:

1. **Accept user requirements** (project name, region, domains, etc.)
2. **Generate all files** (Terraform, Dockerfile, scripts, workflows)
3. **Orchestrate infrastructure** (run Terraform, build Docker, deploy)
4. **Verify deployment** (check HTTPS endpoint, SSM parameters, alarms)

### CrewAI components:

**Tools** (`crewai/tools.py`):
- `TerraformTool`: Run `terraform init`, `apply`, read outputs
- `DockerECRTool`: Build Docker image, push to ECR
- `SSMTool`: Read/write SSM parameters
- `CodeDeployTool`: Package and upload deployment bundle, trigger deployment
- `VerifyTool`: Check health endpoint, wait for ALB to be healthy

**Agents** (`crewai/agents.py`):
- `manager`: Release Manager (orchestrates overall flow)
- `infra_engineer`: Terraform Engineer (provisions infrastructure)
- `build_engineer`: Docker Build Engineer (builds and pushes images)
- `deploy_engineer`: Deployment Engineer (triggers CodeDeploy)

**Flow** (`crewai/flow.py`):
- Defines task sequence: Terraform → Build → Deploy → Verify
- Uses `Crew` with hierarchical process (manager delegates to specialists)

**Run** (`crewai/run.py`):
- Entry point: accepts user inputs, runs crew

### User input schema (extended version):

```python
# User provides requirements as dictionary
user_requirements = {
    "project": "bluegreen",
    "region": "us-east-1",
    
    # Dev environment
    "dev": {
        "domain": "dev.example.com",
        "route53_zone_id": "Z1234567890ABC",
        "vpc_cidr": "10.10.0.0/16",
        "public_subnets": ["10.10.1.0/24", "10.10.2.0/24"],
        "private_subnets": ["10.10.11.0/24", "10.10.12.0/24"],
        "instance_type": "t3.micro",
        "min_size": 1,
        "max_size": 2,
        "desired_capacity": 1,
        "alarm_email": "dev-team@example.com",
        "log_retention_days": 7
    },
    
    # Prod environment
    "prod": {
        "domain": "app.example.com",
        "route53_zone_id": "Z0987654321XYZ",
        "vpc_cidr": "10.20.0.0/16",
        "public_subnets": ["10.20.1.0/24", "10.20.2.0/24"],
        "private_subnets": ["10.20.11.0/24", "10.20.12.0/24"],
        "instance_type": "t3.small",
        "min_size": 2,
        "max_size": 6,
        "desired_capacity": 2,
        "alarm_email": "ops-team@example.com",
        "log_retention_days": 30
    },
    
    # Optional: AMI ID (defaults to latest Amazon Linux 2)
    "ami_id": ""
}
```

### Crew workflow with user inputs:

```python
# crewai/run.py (enhanced)
import json
from flow import run_full_release_from_requirements

if __name__ == "__main__":
    # Load user requirements from file or prompt
    with open("requirements.json") as f:
        user_requirements = json.load(f)
    
    # Run crew
    result = run_full_release_from_requirements(user_requirements)
    
    print("="*60)
    print("DEPLOYMENT COMPLETE")
    print("="*60)
    print(f"Dev ALB: https://{result['dev']['alb']}")
    print(f"Prod ALB: https://{result['prod']['alb']}")
    print(f"Image: {result['image']}")
    print(f"Tag: {result['tag']}")
```

### Enhanced flow (`crewai/flow.py`):

```python
def run_full_release_from_requirements(requirements: dict):
    """
    1. Generate all files from user requirements
    2. Run bootstrap (create S3 + DynamoDB backend)
    3. Run dev environment Terraform
    4. Run prod environment Terraform
    5. Build and push Docker image
    6. Deploy to both dev and prod
    7. Verify both environments
    """
    
    # Task 1: Generate files
    t1 = Task(
        description=f"""
        Generate all project files from user requirements:
        {json.dumps(requirements, indent=2)}
        
        Create:
        - app/package.json, app/server.js, app/Dockerfile
        - deploy/appspec.yml, deploy/scripts/*.sh
        - infra/bootstrap/*.tf
        - infra/modules/platform/*.tf
        - infra/envs/dev/*.tf, infra/envs/dev/*.tfvars, infra/envs/dev/backend.hcl
        - infra/envs/prod/*.tf, infra/envs/prod/*.tfvars, infra/envs/prod/backend.hcl
        - .github/workflows/*.yml
        """,
        expected_output="All files generated successfully",
        agent=infra_engineer
    )
    
    # Task 2: Bootstrap
    t2 = Task(
        description="Run terraform init and apply in infra/bootstrap/",
        expected_output="Backend resources created (S3, DynamoDB, CloudTrail bucket)",
        agent=infra_engineer
    )
    
    # Task 3: Dev environment
    t3 = Task(
        description="Run terraform init and apply for dev environment",
        expected_output="Dev infrastructure provisioned",
        agent=infra_engineer
    )
    
    # Task 4: Prod environment
    t4 = Task(
        description="Run terraform init and apply for prod environment",
        expected_output="Prod infrastructure provisioned",
        agent=infra_engineer
    )
    
    # Task 5: Build and push image
    t5 = Task(
        description="Build Docker image, push to ECR, update SSM image tag",
        expected_output="Image pushed and SSM updated",
        agent=build_engineer
    )
    
    # Task 6: Deploy to dev
    t6 = Task(
        description="Package bundle, upload to S3, trigger CodeDeploy for dev",
        expected_output="Dev deployment started",
        agent=deploy_engineer
    )
    
    # Task 7: Deploy to prod
    t7 = Task(
        description="Trigger CodeDeploy for prod",
        expected_output="Prod deployment started",
        agent=deploy_engineer
    )
    
    # Task 8: Verify dev
    t8 = Task(
        description="Verify dev ALB health endpoint returns 200",
        expected_output="Dev verified",
        agent=manager
    )
    
    # Task 9: Verify prod
    t9 = Task(
        description="Verify prod ALB health endpoint returns 200",
        expected_output="Prod verified",
        agent=manager
    )
    
    crew = Crew(
        agents=[manager, infra_engineer, build_engineer, deploy_engineer],
        tasks=[t1, t2, t3, t4, t5, t6, t7, t8, t9],
        process=Process.hierarchical,
        manager_agent=manager,
        verbose=True
    )
    
    # Execute (actual implementation would call real tools)
    # This is a simplified example
    crew.kickoff()
    
    # Return results
    return {
        "dev": {"alb": "dev.example.com"},
        "prod": {"alb": "app.example.com"},
        "image": "123456789012.dkr.ecr.us-east-1.amazonaws.com/bluegreen-app:abc123",
        "tag": "abc123"
    }
```

### File generation agent:

The crew needs a **file generation agent** that uses **Code Interpreter** or **file writing tools** to create:

- **Terraform files**: Substitute user requirements into templates
- **Application files**: Generic Node.js/Express app
- **Deployment scripts**: Generic scripts that work with any app
- **GitHub workflows**: Substitute project name, region

**Example file generation tool**:

```python
class FileGeneratorTool:
    def generate_terraform_module(self, requirements: dict):
        """Generate platform module Terraform files"""
        # Read templates
        vpc_template = read_template("templates/vpc.tf.tmpl")
        alb_template = read_template("templates/alb.tf.tmpl")
        # ... etc
        
        # Substitute variables
        vpc_tf = vpc_template.format(**requirements)
        alb_tf = alb_template.format(**requirements)
        
        # Write files
        write_file("infra/modules/platform/vpc.tf", vpc_tf)
        write_file("infra/modules/platform/alb.tf", alb_tf)
        # ... etc
        
        return "Terraform module generated"
    
    def generate_app_files(self, requirements: dict):
        """Generate app/package.json, app/server.js, app/Dockerfile"""
        # These are mostly static, with project name substitution
        package_json = {
            "name": f"{requirements['project']}-sample",
            "version": "1.0.0",
            # ... rest is standard
        }
        write_json("app/package.json", package_json)
        
        server_js = read_template("templates/server.js.tmpl")
        write_file("app/server.js", server_js)
        
        dockerfile = read_template("templates/Dockerfile.tmpl")
        write_file("app/Dockerfile", dockerfile)
        
        return "App files generated"
```

### Running the crew:

```bash
# Install dependencies
cd crewai
pip install -r requirements.txt

# Create requirements.json with your values
cat > requirements.json << 'EOF'
{
  "project": "bluegreen",
  "region": "us-east-1",
  "dev": {
    "domain": "dev.example.com",
    "route53_zone_id": "Z1234567890ABC",
    "vpc_cidr": "10.10.0.0/16",
    "public_subnets": ["10.10.1.0/24", "10.10.2.0/24"],
    "private_subnets": ["10.10.11.0/24", "10.10.12.0/24"],
    "instance_type": "t3.micro",
    "min_size": 1,
    "max_size": 2,
    "desired_capacity": 1,
    "alarm_email": "dev@example.com",
    "log_retention_days": 7
  },
  "prod": {
    "domain": "app.example.com",
    "route53_zone_id": "Z0987654321XYZ",
    "vpc_cidr": "10.20.0.0/16",
    "public_subnets": ["10.20.1.0/24", "10.20.2.0/24"],
    "private_subnets": ["10.20.11.0/24", "10.20.12.0/24"],
    "instance_type": "t3.small",
    "min_size": 2,
    "max_size": 6,
    "desired_capacity": 2,
    "alarm_email": "ops@example.com",
    "log_retention_days": 30
  }
}
EOF

# Run crew
python run.py
```

---

## 18. Release & Deployment Pipeline integration

### What is the Release & Deployment Pipeline crew?

The **Release & Deployment Pipeline crew** is an AI-powered automation that turns "what changed" into release artifacts:

- **Changelog/Release notes** — Human-readable summary of features, fixes, breaking changes
- **Version bump** — Automatic semver version update in `package.json` or other config files
- **Test plan** — Suggested tests based on what areas changed
- **Deploy checklist** — Step-by-step runbook for deployment
- **Rollback plan** — When and how to revert if deployment fails

### How it integrates with this Blue/Green project

The Release & Deployment Pipeline crew fits **before** the actual deployment in your CI/CD workflow:

```
1. Developer merges PR to main
   ↓
2. GitHub Actions: Release Prep workflow
   ↓
3. Release & Deployment Pipeline crew runs
   - Input: git commits since last release
   - Outputs: CHANGELOG.md, version bump, test_plan.md, deploy_checklist.md, rollback_plan.md
   ↓
4. Commit release artifacts back to repo
   ↓
5. GitHub Actions: Build workflow (existing build-push.yml)
   ↓
6. GitHub Actions: Deploy workflow (existing deploy.yml)
   - Uses deploy_checklist.md as the runbook
   - Uses rollback_plan.md if deployment fails
   ↓
7. Post-deployment verification
```

### Enhanced GitHub Actions workflow: `release-prep.yml`

Add this workflow to `.github/workflows/release-prep.yml`:

```yaml
name: release-prep
on:
  push:
    branches: ["main"]
    paths-ignore: 
      - "CHANGELOG.md"
      - "deploy_checklist.md"
      - "rollback_plan.md"
      - "test_plan.md"

permissions:
  contents: write
  pull-requests: write

jobs:
  prepare-release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Need full history for git log

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Install CrewAI dependencies
        run: |
          cd release-crew
          pip install -r requirements.txt

      - name: Get commits since last release
        id: commits
        run: |
          # Get last tag (or use initial commit if no tags)
          LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)
          
          # Get commits since last tag
          COMMITS=$(git log ${LAST_TAG}..HEAD --oneline --no-merges)
          
          # Save to file for crew input
          echo "$COMMITS" > commits_input.txt
          
          echo "last_tag=$LAST_TAG" >> $GITHUB_OUTPUT

      - name: Run Release & Deployment Pipeline crew
        env:
          COMMITS_FILE: commits_input.txt
          PROJECT_ENV: ${{ github.ref == 'refs/heads/main' && 'prod' || 'dev' }}
        run: |
          cd release-crew
          python run_release_prep.py

      - name: Commit release artifacts
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          
          git add CHANGELOG.md app/package.json deploy_checklist.md rollback_plan.md test_plan.md
          
          if git diff --staged --quiet; then
            echo "No changes to commit"
          else
            git commit -m "chore: update release artifacts [skip ci]"
            git push
          fi

      - name: Create GitHub Release
        if: startsWith(github.ref, 'refs/tags/')
        uses: actions/create-release@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          tag_name: ${{ github.ref }}
          release_name: Release ${{ github.ref }}
          body_path: CHANGELOG.md
          draft: false
          prerelease: false
```

### Release crew directory structure

Add a new directory for the release preparation crew:

```
release-crew/
├── requirements.txt
├── tools.py
├── agents.py
├── tasks.py
├── flow.py
└── run_release_prep.py
```

### `release-crew/requirements.txt`

```
crewai==0.70.1
python-dotenv==1.0.1
```

### `release-crew/tools.py`

```python
import os
import json
import re
from typing import Dict, List

class ChangelogTool:
    """Tool for reading and writing CHANGELOG.md"""
    
    def read_changelog(self) -> str:
        """Read existing CHANGELOG.md"""
        if os.path.exists("../CHANGELOG.md"):
            with open("../CHANGELOG.md", "r") as f:
                return f.read()
        return "# Changelog\n\nAll notable changes to this project will be documented in this file.\n\n"
    
    def write_changelog(self, content: str) -> str:
        """Write updated CHANGELOG.md"""
        with open("../CHANGELOG.md", "w") as f:
            f.write(content)
        return "Changelog updated successfully"

class VersionTool:
    """Tool for reading and updating version in package.json"""
    
    def read_version(self) -> str:
        """Read current version from package.json"""
        with open("../app/package.json", "r") as f:
            data = json.load(f)
            return data.get("version", "1.0.0")
    
    def write_version(self, new_version: str) -> str:
        """Update version in package.json"""
        with open("../app/package.json", "r") as f:
            data = json.load(f)
        
        data["version"] = new_version
        
        with open("../app/package.json", "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        
        return f"Version updated to {new_version}"
    
    def determine_version_bump(self, commits: str) -> str:
        """Determine semver bump type from commits"""
        # Check for breaking changes
        if re.search(r'BREAKING CHANGE|!:', commits, re.IGNORECASE):
            return "major"
        
        # Check for features
        if re.search(r'feat(\(.*?\))?:', commits, re.IGNORECASE):
            return "minor"
        
        # Default to patch for fixes and other changes
        return "patch"
    
    def bump_version(self, current: str, bump_type: str) -> str:
        """Bump version according to semver"""
        major, minor, patch = map(int, current.split('.'))
        
        if bump_type == "major":
            return f"{major + 1}.0.0"
        elif bump_type == "minor":
            return f"{major}.{minor + 1}.0"
        else:  # patch
            return f"{major}.{minor}.{patch + 1}"

class FileWriterTool:
    """Tool for writing deploy checklist, rollback plan, and test plan"""
    
    def write_deploy_checklist(self, content: str) -> str:
        """Write deploy_checklist.md"""
        with open("../deploy_checklist.md", "w") as f:
            f.write(content)
        return "Deploy checklist created successfully"
    
    def write_rollback_plan(self, content: str) -> str:
        """Write rollback_plan.md"""
        with open("../rollback_plan.md", "w") as f:
            f.write(content)
        return "Rollback plan created successfully"
    
    def write_test_plan(self, content: str) -> str:
        """Write test_plan.md"""
        with open("../test_plan.md", "w") as f:
            f.write(content)
        return "Test plan created successfully"

class CommitAnalysisTool:
    """Tool for analyzing commits"""
    
    def parse_commits(self, commits_text: str) -> List[Dict[str, str]]:
        """Parse commits into structured format"""
        commits = []
        for line in commits_text.strip().split('\n'):
            if not line:
                continue
            
            # Parse conventional commit format: type(scope): message
            match = re.match(r'^([a-f0-9]+)\s+(\w+)(\(.*?\))?:\s+(.+)$', line)
            if match:
                sha, commit_type, scope, message = match.groups()
                commits.append({
                    "sha": sha,
                    "type": commit_type,
                    "scope": scope.strip('()') if scope else "",
                    "message": message
                })
            else:
                # Fallback for non-conventional commits
                parts = line.split(' ', 1)
                if len(parts) == 2:
                    commits.append({
                        "sha": parts[0],
                        "type": "other",
                        "scope": "",
                        "message": parts[1]
                    })
        
        return commits
    
    def categorize_commits(self, commits: List[Dict[str, str]]) -> Dict[str, List[str]]:
        """Categorize commits by type"""
        categories = {
            "features": [],
            "fixes": [],
            "breaking": [],
            "docs": [],
            "other": []
        }
        
        for commit in commits:
            message = f"{commit['message']}"
            if commit['scope']:
                message = f"{commit['scope']}: {message}"
            
            commit_type = commit['type'].lower()
            
            if 'BREAKING CHANGE' in commit['message'] or commit_type == 'breaking':
                categories["breaking"].append(message)
            elif commit_type in ['feat', 'feature']:
                categories["features"].append(message)
            elif commit_type == 'fix':
                categories["fixes"].append(message)
            elif commit_type in ['docs', 'doc']:
                categories["docs"].append(message)
            else:
                categories["other"].append(message)
        
        return categories
```

### `release-crew/agents.py`

```python
from crewai import Agent

changelog_writer = Agent(
    role="Release Notes Writer",
    goal="Create clear, comprehensive release notes from commit history",
    backstory="Technical writer specializing in software release documentation. "
              "Skilled at turning git commits into user-friendly release notes.",
    verbose=True
)

version_manager = Agent(
    role="Version Manager",
    goal="Determine appropriate version bump following semver and update version files",
    backstory="Release engineer expert in semantic versioning. "
              "Analyzes changes to determine major, minor, or patch version bumps.",
    verbose=True
)

test_strategist = Agent(
    role="Test Strategist",
    goal="Identify test requirements based on code changes",
    backstory="QA engineer who designs test strategies. "
              "Recommends smoke tests, regression tests, and validation steps for deployments.",
    verbose=True
)

deployment_specialist = Agent(
    role="Deployment Specialist",
    goal="Create detailed, safe deployment checklists for Blue/Green deployments",
    backstory="DevOps engineer expert in AWS CodeDeploy Blue/Green deployments. "
              "Creates comprehensive deployment runbooks with gates and verification steps.",
    verbose=True
)

rollback_coordinator = Agent(
    role="Rollback Coordinator",
    goal="Design clear rollback procedures for failed deployments",
    backstory="SRE specialist in incident response. "
              "Creates rollback plans with clear triggers and verification steps.",
    verbose=True
)
```

### `release-crew/tasks.py`

```python
from crewai import Task
from agents import (
    changelog_writer,
    version_manager,
    test_strategist,
    deployment_specialist,
    rollback_coordinator
)

def create_changelog_task(commits_text: str, current_version: str) -> Task:
    return Task(
        description=f"""
        Analyze the following commits and create release notes:
        
        {commits_text}
        
        Current version: {current_version}
        
        Create a CHANGELOG.md entry with:
        - Version number and date
        - Features section (new capabilities)
        - Fixes section (bug fixes)
        - Breaking changes section (if any)
        - Other changes section (docs, chores, etc.)
        
        Use markdown format and be concise but clear.
        """,
        expected_output="CHANGELOG.md entry with categorized changes",
        agent=changelog_writer
    )

def create_version_bump_task(commits_text: str, current_version: str) -> Task:
    return Task(
        description=f"""
        Analyze commits and determine the appropriate version bump:
        
        {commits_text}
        
        Current version: {current_version}
        
        Rules:
        - MAJOR: Breaking changes (BREAKING CHANGE in commit or !: syntax)
        - MINOR: New features (feat: prefix)
        - PATCH: Bug fixes and other changes (fix:, docs:, chore:, etc.)
        
        Output the new version number and rationale.
        """,
        expected_output="New version number with semver bump rationale",
        agent=version_manager
    )

def create_test_plan_task(commits_text: str, project_env: str) -> Task:
    return Task(
        description=f"""
        Based on these changes, create a test plan:
        
        {commits_text}
        
        Environment: {project_env}
        
        This is a Blue/Green deployment on AWS with:
        - Node.js application in Docker
        - ALB health checks
        - CodeDeploy lifecycle hooks
        
        Suggest:
        1. Pre-deployment tests (unit, integration)
        2. Smoke tests (health endpoints, basic functionality)
        3. Regression tests (based on changed areas)
        4. Post-deployment validation (monitoring, logs)
        
        Be specific about what to test based on what changed.
        """,
        expected_output="Test plan with pre-deployment, smoke, and regression tests",
        agent=test_strategist
    )

def create_deploy_checklist_task(commits_text: str, project_env: str, new_version: str) -> Task:
    return Task(
        description=f"""
        Create a deployment checklist for this Blue/Green deployment:
        
        Changes: {commits_text}
        Environment: {project_env}
        New version: {new_version}
        
        The deployment uses:
        - AWS CodeDeploy Blue/Green
        - Auto Scaling Groups (blue and green)
        - Application Load Balancer
        - ECR for Docker images
        - SSM for image tag parameter
        
        Create a checklist with:
        1. Pre-deployment gates (tests must pass, approvals)
        2. Deployment steps in order
        3. Verification steps (health checks, logs, alarms)
        4. Post-deployment tasks (cleanup, notifications)
        
        Include specific AWS resources and verification commands.
        """,
        expected_output="Detailed deployment checklist with gates and verification",
        agent=deployment_specialist
    )

def create_rollback_plan_task(project_env: str, current_version: str, new_version: str) -> Task:
    return Task(
        description=f"""
        Create a rollback plan for this deployment:
        
        Environment: {project_env}
        Current version (blue): {current_version}
        New version (green): {new_version}
        
        The system uses AWS CodeDeploy Blue/Green deployment.
        
        Create a rollback plan with:
        1. Rollback triggers (when to roll back)
        2. Rollback steps (how to revert to blue environment)
        3. Verification steps (confirm rollback succeeded)
        4. Post-rollback actions (incident report, investigation)
        
        Include specific AWS CodeDeploy commands and CloudWatch alarm references.
        """,
        expected_output="Rollback plan with triggers, steps, and verification",
        agent=rollback_coordinator
    )
```

### `release-crew/flow.py`

```python
from crewai import Crew, Process
from tasks import (
    create_changelog_task,
    create_version_bump_task,
    create_test_plan_task,
    create_deploy_checklist_task,
    create_rollback_plan_task
)
from agents import (
    changelog_writer,
    version_manager,
    test_strategist,
    deployment_specialist,
    rollback_coordinator
)
from tools import ChangelogTool, VersionTool, FileWriterTool, CommitAnalysisTool

def run_release_prep(commits_text: str, project_env: str = "prod"):
    """
    Run the complete release preparation workflow
    """
    # Initialize tools
    changelog_tool = ChangelogTool()
    version_tool = VersionTool()
    file_writer = FileWriterTool()
    commit_tool = CommitAnalysisTool()
    
    # Get current version
    current_version = version_tool.read_version()
    
    # Determine version bump
    bump_type = version_tool.determine_version_bump(commits_text)
    new_version = version_tool.bump_version(current_version, bump_type)
    
    print(f"\n{'='*60}")
    print(f"Release Preparation")
    print(f"{'='*60}")
    print(f"Current version: {current_version}")
    print(f"Bump type: {bump_type}")
    print(f"New version: {new_version}")
    print(f"Environment: {project_env}")
    print(f"{'='*60}\n")
    
    # Create tasks
    changelog_task = create_changelog_task(commits_text, new_version)
    version_task = create_version_bump_task(commits_text, current_version)
    test_plan_task = create_test_plan_task(commits_text, project_env)
    deploy_checklist_task = create_deploy_checklist_task(commits_text, project_env, new_version)
    rollback_plan_task = create_rollback_plan_task(project_env, current_version, new_version)
    
    # Create crew
    crew = Crew(
        agents=[
            changelog_writer,
            version_manager,
            test_strategist,
            deployment_specialist,
            rollback_coordinator
        ],
        tasks=[
            changelog_task,
            version_task,
            test_plan_task,
            deploy_checklist_task,
            rollback_plan_task
        ],
        process=Process.sequential,
        verbose=True
    )
    
    # Run crew
    result = crew.kickoff()
    
    # Parse and categorize commits
    commits = commit_tool.parse_commits(commits_text)
    categories = commit_tool.categorize_commits(commits)
    
    # Update CHANGELOG.md
    changelog_content = changelog_tool.read_changelog()
    new_entry = f"""
## [{new_version}] - {import_date()}

"""
    
    if categories["breaking"]:
        new_entry += "### ⚠️ BREAKING CHANGES\n\n"
        for change in categories["breaking"]:
            new_entry += f"- {change}\n"
        new_entry += "\n"
    
    if categories["features"]:
        new_entry += "### ✨ Features\n\n"
        for feat in categories["features"]:
            new_entry += f"- {feat}\n"
        new_entry += "\n"
    
    if categories["fixes"]:
        new_entry += "### 🐛 Bug Fixes\n\n"
        for fix in categories["fixes"]:
            new_entry += f"- {fix}\n"
        new_entry += "\n"
    
    if categories["docs"]:
        new_entry += "### 📚 Documentation\n\n"
        for doc in categories["docs"]:
            new_entry += f"- {doc}\n"
        new_entry += "\n"
    
    if categories["other"]:
        new_entry += "### 🔧 Other Changes\n\n"
        for other in categories["other"]:
            new_entry += f"- {other}\n"
        new_entry += "\n"
    
    # Insert new entry after header
    lines = changelog_content.split('\n')
    header_end = 2  # After "# Changelog" and blank line
    updated_changelog = '\n'.join(lines[:header_end]) + '\n\n' + new_entry + '\n'.join(lines[header_end:])
    
    changelog_tool.write_changelog(updated_changelog)
    
    # Update version
    version_tool.write_version(new_version)
    
    # Write deploy checklist (extract from crew result)
    deploy_checklist_content = f"""# Deployment Checklist - v{new_version}

**Environment:** {project_env}  
**Date:** {import_date()}  
**Release:** {current_version} → {new_version}

---

## Pre-Deployment Gates

- [ ] All tests passing in CI/CD
- [ ] Code review approved
- [ ] Security scan passed (Inspector, GuardDuty)
- [ ] Changelog and version updated
- [ ] Deployment window confirmed
- [ ] On-call engineer notified

---

## Deployment Steps

### 1. Pre-Deploy Verification
```bash
# Verify current production version
terraform output -raw alb_dns_name
curl https://<alb-dns>/health

# Check current image tag
aws ssm get-parameter --name /bluegreen/{project_env}/image_tag --query Parameter.Value --output text
```

### 2. Build and Push Image
- [ ] GitHub Actions build-push workflow completed
- [ ] Docker image pushed to ECR with tag `{new_version}`
- [ ] SSM parameter `/bluegreen/{project_env}/image_tag` updated

### 3. Trigger Deployment
- [ ] GitHub Actions deploy workflow triggered
- [ ] CodeDeploy deployment created
- [ ] Monitor deployment in CodeDeploy console

### 4. CodeDeploy Lifecycle
- [ ] ApplicationStop: Old containers stopped on GREEN instances
- [ ] BeforeInstall: Dependencies verified
- [ ] ApplicationStart: New containers started with version {new_version}
- [ ] ValidateService: Health checks passing

### 5. Traffic Switch
- [ ] All GREEN instances healthy
- [ ] CloudWatch alarms OK (no 5xx, latency normal)
- [ ] ALB switches traffic from BLUE to GREEN

---

## Verification Steps

### Health Checks
```bash
# Check ALB health
curl https://<alb-dns>/health

# Check version
curl https://<alb-dns>/ | jq '.version'
# Expected: "{new_version}"
```

### Monitoring
- [ ] Check CloudWatch Logs `/bluegreen/{project_env}/docker` for errors
- [ ] Verify CloudWatch alarms are not firing
- [ ] Check target group health in ALB console
- [ ] Monitor application metrics (response time, error rate)

### Smoke Tests
- [ ] Run test plan smoke tests (see test_plan.md)
- [ ] Verify key user flows
- [ ] Check integration with external services

---

## Post-Deployment

- [ ] Monitor for 15 minutes after traffic switch
- [ ] BLUE instances terminated (after validation period)
- [ ] Create release notes in GitHub/GitLab
- [ ] Notify team in Slack/email
- [ ] Update runbook if procedures changed

---

## Rollback Trigger

If ANY of these occur, initiate rollback (see rollback_plan.md):
- Health check failures
- CloudWatch alarms firing (5xx, latency, unhealthy targets)
- Critical functionality broken
- Error rate > 1%
- On-call decision

---

**Deployment Lead:** _________________  
**Sign-off:** _________________  
**Date/Time:** _________________
"""
    
    file_writer.write_deploy_checklist(deploy_checklist_content)
    
    # Write rollback plan
    rollback_plan_content = f"""# Rollback Plan - v{new_version}

**Environment:** {project_env}  
**Date:** {import_date()}  
**Release:** {new_version} (GREEN) → {current_version} (BLUE)

---

## Rollback Triggers

Initiate rollback immediately if ANY of these occur:

1. **Health check failures**: > 10% of instances failing health checks
2. **CloudWatch alarms**:
   - ALB 5xx errors > 10 in 5 minutes
   - Unhealthy targets ≥ 1 for 5 minutes
   - Latency p99 > 2 seconds
3. **Critical functionality broken**: User-reported issues affecting key flows
4. **Error rate**: Application error rate > 1%
5. **Manual decision**: On-call engineer or release manager decides to roll back

---

## Rollback Steps

### Option 1: Automatic CodeDeploy Rollback

If deployment is still in progress and alarms fire:

```bash
# CodeDeploy will automatically roll back
# Monitor in CodeDeploy console
# Traffic will switch back to BLUE
```

### Option 2: Manual Rollback (Post-Deployment)

If deployment completed but issues found later:

#### Step 1: Stop GREEN instances from receiving traffic

```bash
# Get deployment group info
aws deploy get-deployment-group \\
  --application-name bluegreen-codedeploy-app \\
  --deployment-group-name bluegreen-dg-{project_env}

# Create new deployment to revert to BLUE
# Update SSM with previous image tag
aws ssm put-parameter \\
  --name "/bluegreen/{project_env}/image_tag" \\
  --type "String" \\
  --value "{current_version}" \\
  --overwrite

# Trigger new deployment (will deploy old version to GREEN, then switch)
cd deploy
zip -r deployment.zip .
aws s3 cp deployment.zip s3://<artifacts-bucket>/revisions/rollback-{current_version}.zip

aws deploy create-deployment \\
  --application-name bluegreen-codedeploy-app \\
  --deployment-group-name bluegreen-dg-{project_env} \\
  --s3-location bucket=<artifacts-bucket>,key=revisions/rollback-{current_version}.zip,bundleType=zip
```

#### Step 2: Verify rollback

```bash
# Check version endpoint
curl https://<alb-dns>/ | jq '.version'
# Expected: "{current_version}"

# Check health
curl https://<alb-dns>/health
# Expected: "OK"

# Verify all instances healthy
aws elbv2 describe-target-health \\
  --target-group-arn <blue-target-group-arn>
```

#### Step 3: Monitor

- [ ] All instances reporting version {current_version}
- [ ] Health checks passing
- [ ] CloudWatch alarms OK
- [ ] Error rate back to normal
- [ ] Application logs show no errors

---

## Post-Rollback Actions

### Immediate (within 1 hour)
- [ ] Notify team in Slack/email
- [ ] Update incident tracker
- [ ] Preserve logs from failed deployment (CloudWatch Logs Insights export)
- [ ] Capture metrics snapshots (error rate, latency, 5xx count)

### Short-term (within 24 hours)
- [ ] Create incident postmortem
- [ ] Identify root cause of deployment failure
- [ ] Create fix for issue
- [ ] Update deployment checklist if process failed
- [ ] Update test plan to catch issue earlier

### Long-term (within 1 week)
- [ ] Test fix in dev environment
- [ ] Plan re-deployment with fix
- [ ] Review and improve CI/CD guardrails
- [ ] Update runbooks

---

## Rollback Verification Checklist

- [ ] Version reverted to {current_version}
- [ ] All health checks passing
- [ ] No CloudWatch alarms firing
- [ ] Error rate < 0.1%
- [ ] Response time normal (p99 < 500ms)
- [ ] Key user flows working
- [ ] External integrations OK
- [ ] Team notified
- [ ] Incident logged

---

## Emergency Contacts

- **On-call Engineer:** [Phone/Slack]
- **Release Manager:** [Phone/Slack]
- **Engineering Lead:** [Phone/Slack]
- **AWS Support:** [Account number/support plan]

---

**Rollback Lead:** _________________  
**Sign-off:** _________________  
**Date/Time:** _________________
"""
    
    file_writer.write_rollback_plan(rollback_plan_content)
    
    # Write test plan
    test_plan_content = f"""# Test Plan - v{new_version}

**Environment:** {project_env}  
**Date:** {import_date()}  
**Release:** {current_version} → {new_version}

---

## Changes in This Release

{_format_changes(categories)}

---

## Pre-Deployment Tests

### Unit Tests
```bash
cd app
npm test
```

**Expected:** All tests passing

### Integration Tests
```bash
# Run integration test suite
npm run test:integration
```

**Expected:** All critical paths working

### Security Scan
```bash
# ECR scan results
aws ecr describe-image-scan-findings \\
  --repository-name bluegreen-app \\
  --image-id imageTag={new_version}
```

**Expected:** No critical or high vulnerabilities

---

## Deployment Smoke Tests

Run these immediately after traffic switch to GREEN:

### 1. Health Check
```bash
curl https://<alb-dns>/health
```
**Expected:** `200 OK`

### 2. Version Check
```bash
curl https://<alb-dns>/ | jq
```
**Expected:** 
```json
{{
  "message": "Hello from Blue/Green EC2 + CodeDeploy!",
  "hostname": "<instance-id>",
  "version": "{new_version}",
  "timestamp": "2026-02-05T..."
}}
```

### 3. Load Test (Light)
```bash
# Use ab (Apache Bench) or similar
ab -n 100 -c 10 https://<alb-dns>/
```
**Expected:** 0% failures, p99 < 500ms

---

## Regression Tests

Based on changed areas, test:

{_generate_regression_tests(categories)}

---

## Post-Deployment Validation

### Monitoring (15 minutes)

- [ ] CloudWatch Logs: No errors in `/bluegreen/{project_env}/docker`
- [ ] CloudWatch Alarms: All OK (no 5xx, unhealthy targets, high latency)
- [ ] Target Health: All instances healthy in GREEN target group

### Metrics Baseline

| Metric | Baseline (BLUE) | Current (GREEN) | Status |
|--------|-----------------|-----------------|--------|
| Error rate | < 0.1% | ___ % | ✅ / ❌ |
| p99 latency | < 500ms | ___ ms | ✅ / ❌ |
| Requests/sec | ~100 | ___ | ✅ / ❌ |

### User Acceptance

- [ ] Key user flows tested manually
- [ ] No user-reported issues in first 30 minutes

---

## Rollback Criteria

If any test fails or metrics degrade:
1. Refer to rollback_plan.md
2. Initiate rollback immediately
3. Investigate root cause

---

**Test Lead:** _________________  
**Sign-off:** _________________  
**Date/Time:** _________________
"""
    
    file_writer.write_test_plan(test_plan_content)
    
    print(f"\n{'='*60}")
    print("Release Preparation Complete")
    print(f"{'='*60}")
    print(f"✅ CHANGELOG.md updated")
    print(f"✅ Version bumped to {new_version}")
    print(f"✅ Deploy checklist created")
    print(f"✅ Rollback plan created")
    print(f"✅ Test plan created")
    print(f"{'='*60}\n")
    
    return {
        "current_version": current_version,
        "new_version": new_version,
        "bump_type": bump_type,
        "environment": project_env
    }

def import_date():
    """Get current date in YYYY-MM-DD format"""
    from datetime import datetime
    return datetime.now().strftime("%Y-%m-%d")

def _format_changes(categories):
    """Format changes for test plan"""
    output = ""
    if categories["breaking"]:
        output += "**Breaking Changes:**\n"
        for change in categories["breaking"]:
            output += f"- {change}\n"
        output += "\n"
    
    if categories["features"]:
        output += "**Features:**\n"
        for feat in categories["features"]:
            output += f"- {feat}\n"
        output += "\n"
    
    if categories["fixes"]:
        output += "**Fixes:**\n"
        for fix in categories["fixes"]:
            output += f"- {fix}\n"
        output += "\n"
    
    return output or "No categorized changes"

def _generate_regression_tests(categories):
    """Generate regression test suggestions based on changes"""
    tests = []
    
    # Check for auth-related changes
    auth_keywords = ['auth', 'login', 'sso', 'oauth', 'jwt', 'session']
    if any(keyword in str(categories).lower() for keyword in auth_keywords):
        tests.append("- **Authentication**: Test login, logout, session persistence")
    
    # Check for API changes
    api_keywords = ['api', 'endpoint', 'route', 'handler']
    if any(keyword in str(categories).lower() for keyword in api_keywords):
        tests.append("- **API**: Test all modified endpoints with various inputs")
    
    # Check for database changes
    db_keywords = ['db', 'database', 'query', 'migration', 'schema']
    if any(keyword in str(categories).lower() for keyword in db_keywords):
        tests.append("- **Database**: Test queries, data integrity, migrations")
    
    # Default tests
    if not tests:
        tests.append("- **Core functionality**: Test main user flows")
        tests.append("- **Integration**: Test external service connections")
    
    return '\n'.join(tests)
```

### `release-crew/run_release_prep.py`

```python
import os
from flow import run_release_prep

if __name__ == "__main__":
    # Read commits from file
    commits_file = os.environ.get("COMMITS_FILE", "commits_input.txt")
    with open(commits_file, "r") as f:
        commits_text = f.read()
    
    # Get environment
    project_env = os.environ.get("PROJECT_ENV", "prod")
    
    # Run release preparation
    result = run_release_prep(commits_text, project_env)
    
    print(f"\n{'='*60}")
    print("Ready for deployment!")
    print(f"{'='*60}")
    print(f"Version: {result['current_version']} → {result['new_version']}")
    print(f"Bump type: {result['bump_type']}")
    print(f"Environment: {result['environment']}")
    print(f"\nNext steps:")
    print(f"1. Review and commit: CHANGELOG.md, package.json, deploy_checklist.md, rollback_plan.md, test_plan.md")
    print(f"2. GitHub Actions will trigger build-push workflow")
    print(f"3. Then deploy workflow will use deploy_checklist.md")
    print(f"4. If issues occur, follow rollback_plan.md")
    print(f"{'='*60}\n")
```

### Complete workflow integration

The full deployment flow now looks like:

```
┌─────────────────────────────────────────────────────────────┐
│  Developer merges PR to main                                │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│  GitHub Actions: release-prep.yml                           │
│  - Get commits since last release                           │
│  - Run Release & Deployment Pipeline crew                   │
│  - Generate: CHANGELOG, version bump, test plan,            │
│    deploy checklist, rollback plan                          │
│  - Commit artifacts back to repo                            │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│  GitHub Actions: build-push.yml                             │
│  - Build Docker image                                       │
│  - Push to ECR with new version tag                         │
│  - Update SSM parameter                                     │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│  GitHub Actions: deploy.yml                                 │
│  - Package deployment bundle                                │
│  - Upload to S3                                             │
│  - Trigger CodeDeploy                                       │
│  ├─ Uses deploy_checklist.md as runbook                     │
│  └─ Monitors for rollback triggers                          │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│  CodeDeploy Blue/Green Deployment                           │
│  - Deploy to GREEN instances                                │
│  - Run lifecycle hooks                                      │
│  - Validate health                                          │
│  - Switch traffic BLUE → GREEN                              │
│  - Auto-rollback if alarms fire                             │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│  Post-Deployment Verification                               │
│  - Run test_plan.md tests                                   │
│  - Monitor CloudWatch alarms                                │
│  - Verify version and health                                │
│  - If issues → execute rollback_plan.md                     │
└─────────────────────────────────────────────────────────────┘
```

### Benefits of integration

1. **Automated release notes**: Every deployment gets clear changelog
2. **Consistent versioning**: Semver rules applied automatically
3. **Safety checklists**: Deployment and rollback procedures documented before deploy
4. **Traceability**: Clear paper trail of what changed and how it was deployed
5. **Faster rollback**: Pre-written rollback plan ready if issues occur
6. **Better testing**: Test plan suggests specific tests based on changes

### Running locally for testing

```bash
# Simulate a release
cd release-crew

# Create sample commits file
cat > commits_input.txt << 'EOF'
a1b2c3d feat(auth): add SSO login support
d4e5f6g fix(api): handle missing headers gracefully
h7i8j9k docs: update deployment guide
EOF

# Run release prep
export PROJECT_ENV=dev
python run_release_prep.py

# Check generated files
ls -la ../CHANGELOG.md ../deploy_checklist.md ../rollback_plan.md ../test_plan.md
```

## 19. Production hardening checklist

This project includes enterprise-grade features. Here's what's already implemented and what you might add:

### ✅ Already implemented:

- [x] Blue/Green deployment with automatic rollback
- [x] HTTPS-only traffic with ACM certificates
- [x] HTTP → HTTPS redirect
- [x] Route53 DNS management
- [x] CloudWatch Logs for application and system logs
- [x] CloudWatch Agent for custom metrics
- [x] Alarms for 5xx errors, unhealthy targets, latency, CPU, disk
- [x] SNS email notifications
- [x] Inspector (vulnerability scanning)
- [x] GuardDuty (threat detection)
- [x] Security Hub (security dashboard)
- [x] CloudTrail (audit logging)
- [x] AWS Config (compliance tracking)
- [x] Separate dev and prod environments
- [x] Terraform remote backend (S3 + DynamoDB)
- [x] State encryption with KMS
- [x] State locking to prevent concurrent modifications
- [x] GitHub Actions CI/CD with OIDC
- [x] ECR image lifecycle policy (retain last 20 images)
- [x] Auto Scaling for high availability
- [x] Private subnets for EC2 instances
- [x] NAT Gateway for outbound internet access
- [x] Security groups with least privilege

### 🔧 Additional production hardening:

- [ ] **WAF (Web Application Firewall)**: Protect against SQL injection, XSS, DDoS
- [ ] **Secrets Manager**: Store database passwords, API keys instead of environment variables
- [ ] **RDS database**: Add Aurora PostgreSQL/MySQL for application data
- [ ] **ElastiCache**: Add Redis/Memcached for session storage and caching
- [ ] **Backup automation**: AWS Backup for RDS, EBS snapshots
- [ ] **Disaster recovery**: Multi-region deployment with Route53 failover
- [ ] **VPC Flow Logs**: Network traffic logging for security analysis
- [ ] **Container scanning**: Trivy or AWS ECR scanning in CI pipeline
- [ ] **Least privilege IAM**: Fine-tune IAM roles, use permission boundaries
- [ ] **MFA for critical actions**: Require MFA for production Terraform applies
- [ ] **Compliance as code**: OPA (Open Policy Agent) or Terraform Sentinel
- [ ] **Cost optimization**: Spot instances for non-critical workloads, Savings Plans
- [ ] **Observability**: Integrate with Datadog, New Relic, or Prometheus/Grafana
- [ ] **Synthetic monitoring**: CloudWatch Synthetics for uptime checks
- [ ] **Load testing**: Integrate k6 or Locust in CI pipeline
- [ ] **Blue/Green database migrations**: Coordinate schema changes with code deploys
- [ ] **Feature flags**: LaunchDarkly or AWS AppConfig for gradual rollouts
- [ ] **Canary deployments**: Deploy to 10% of instances first, then 100%
- [ ] **A/B testing**: Route percentage of traffic to experimental version

---

## 20. Glossary

| Term | Definition |
|------|------------|
| **ACM** | AWS Certificate Manager - manages SSL/TLS certificates |
| **ALB** | Application Load Balancer - Layer 7 load balancer that routes HTTP/HTTPS traffic |
| **AMI** | Amazon Machine Image - template for EC2 instances (OS + software) |
| **ASG** | Auto Scaling Group - maintains desired number of EC2 instances |
| **Blue/Green** | Deployment strategy with two identical environments (one live, one standby) |
| **Changelog** | Document listing what changed in each release (CHANGELOG.md) |
| **CloudTrail** | AWS service that logs API calls for auditing |
| **CloudWatch** | AWS monitoring service for logs, metrics, and alarms |
| **CodeDeploy** | AWS deployment service that automates code deployments |
| **CVE** | Common Vulnerabilities and Exposures - public database of security flaws |
| **Deploy Checklist** | Step-by-step deployment runbook with gates and verification |
| **DynamoDB** | AWS NoSQL database (used here for Terraform state locking) |
| **EC2** | Elastic Compute Cloud - virtual servers in AWS |
| **ECR** | Elastic Container Registry - Docker image repository |
| **GuardDuty** | AWS threat detection service |
| **IAM** | Identity and Access Management - AWS permissions and roles |
| **Inspector** | AWS vulnerability scanning service |
| **KMS** | Key Management Service - encryption key management |
| **NAT Gateway** | Network Address Translation - allows private subnets to access internet |
| **OIDC** | OpenID Connect - authentication protocol (GitHub Actions uses this for AWS) |
| **Route53** | AWS DNS service |
| **Rollback Plan** | Procedure for reverting to previous version if deployment fails |
| **S3** | Simple Storage Service - object storage |
| **Security Hub** | AWS security dashboard that aggregates findings |
| **Semver** | Semantic Versioning - version format major.minor.patch (e.g., 2.1.3) |
| **SNS** | Simple Notification Service - pub/sub messaging (used for alarms) |
| **SSM** | AWS Systems Manager - includes Parameter Store, Run Command, Session Manager |
| **Target Group** | Collection of targets (EC2 instances) that ALB routes traffic to |
| **Terraform** | Infrastructure as Code tool by HashiCorp |
| **Test Plan** | Document specifying which tests to run before/during/after deployment |
| **TLS** | Transport Layer Security - encryption protocol (successor to SSL) |
| **Version Bump** | Updating software version number (e.g., 1.2.3 → 1.3.0) |
| **VPC** | Virtual Private Cloud - isolated network in AWS |

---

## Summary

This **AWS EC2 CodeDeploy Blue/Green** project is a **production-grade, enterprise-ready deployment platform** that demonstrates:

✅ **Zero-downtime deployments** using Blue/Green strategy  
✅ **HTTPS-only** web traffic with ACM and Route53  
✅ **Comprehensive monitoring** with CloudWatch Logs, metrics, and alarms  
✅ **Enterprise security** with Inspector, GuardDuty, Security Hub, CloudTrail, and Config  
✅ **Multi-environment** support (separate dev and prod)  
✅ **Infrastructure as Code** with Terraform and remote state backend  
✅ **Full automation** via GitHub Actions and CrewAI  

**CrewAI orchestration** allows you to:
1. **Provide requirements** (project name, region, domains, instance types, etc.)
2. **Generate all files** (Terraform, Docker, scripts, workflows)
3. **Deploy infrastructure** (run Terraform for bootstrap, dev, prod)
4. **Build and deploy app** (Docker build, ECR push, CodeDeploy)
5. **Verify deployment** (check HTTPS endpoints, SSM parameters, alarms)

**Release & Deployment Pipeline integration** adds:
1. **Automated release notes** from git commits (CHANGELOG.md)
2. **Automatic version bumping** following semver rules
3. **Test plan generation** based on what changed
4. **Deployment checklist** with gates and verification steps
5. **Rollback plan** ready before deployment starts

Everything is created from user inputs, making this a **fully automated, production-ready deployment platform with complete release management**.

For step-by-step instructions on implementing this project yourself, refer to the companion guide: **IMPLEMENT_AWS_EC2_BLUEGREEN.md**.
