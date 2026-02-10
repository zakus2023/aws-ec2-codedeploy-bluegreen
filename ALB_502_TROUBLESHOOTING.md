# Troubleshooting 502 on ALB (Beginner CLI Steps)

Use this checklist to diagnose a 502 Bad Gateway from the ALB URL.

## 0) Check if AWS is already configured
```bash
aws configure list
aws sts get-caller-identity
```
If `aws sts get-caller-identity` returns your Account ID and ARN, you are configured.

### If you see: `aws: command not found`
You need to install the AWS CLI first.

**Windows (recommended MSI):**
1. Download: https://awscli.amazonaws.com/AWSCLIV2.msi
2. Run the installer (next → next → finish).
3. Close and reopen Git Bash.
4. Verify:
```bash
aws --version
```

**Windows (winget):**
```bash
winget install -e --id Amazon.AWSCLI
```
Then reopen Git Bash and verify:
```bash
aws --version
```

## 1) Configure AWS (if not already configured)
1. Create or locate an IAM user or role with access to your AWS account.
2. Generate **Access Key ID** and **Secret Access Key** (for CLI use).
3. Run the CLI setup:
```bash
aws configure
```
4. When prompted, enter:
   - **AWS Access Key ID**
   - **AWS Secret Access Key**
   - **Default region name**: `us-east-1`
   - **Default output format**: `json`
5. Verify:
```bash
aws sts get-caller-identity
```

### Where to find your Access Keys
You can only view the **Secret Access Key at creation time**.

**To create/retrieve keys:**
1. AWS Console → **IAM** → **Users** → select your user  
2. **Security credentials** tab  
3. Under **Access keys**, click **Create access key**  
4. Copy/save the **Access Key ID** and **Secret Access Key** immediately

If you already created one and didn’t save the secret, you must **create a new access key** (the old secret can’t be retrieved).

## 2) Set AWS region (explicitly)
```bash
aws configure set region us-east-1
```

## 3) Find the ALB ARN
```bash
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(DNSName, 'bluegreen-dev-alb')].LoadBalancerArn" \
  --output text
```
Copy the output ARN.

## 4) Find the target group ARNs
```bash
aws elbv2 describe-target-groups \
  --query "TargetGroups[?contains(TargetGroupName, 'bluegreen-dev-tg')].[TargetGroupName,TargetGroupArn]" \
  --output table
```
Copy the **blue** target group ARN.

## 5) Check target health
```bash
aws elbv2 describe-target-health \
  --target-group-arn <PASTE_BLUE_TARGET_GROUP_ARN>
```
If targets are `unhealthy`, that is the most common reason for 502s.

## 6) Check ALB listeners (HTTPS should forward to blue)
```bash
aws elbv2 describe-listeners \
  --load-balancer-arn arn:aws:elasticloadbalancing:us-east-1:058264482067:loadbalancer/app/bluegreen-dev-alb/57887f6d1b1847bc
```
Look for the **HTTPS listener** default action → blue target group ARN.

## 7) Find a blue ASG instance ID
```bash
aws autoscaling describe-auto-scaling-groups \
  --query "AutoScalingGroups[?AutoScalingGroupName=='bluegreen-dev-asg-blue'].Instances[].InstanceId" \
  --output text
```
Copy one instance ID.

## 8) Run health check on the instance (SSM)
```bash
aws ssm send-command \
  --instance-ids i-019ced50690fa86bd \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["curl -i http://localhost:8080/health","docker ps"]' \
  --output text
```

Then fetch the output:
```bash
aws ssm list-command-invocations --details \
  --query "CommandInvocations[0].CommandPlugins[0].Output" \
  --output text
```

## 9) Check CloudWatch logs (optional)
```bash
aws logs describe-log-streams \
  --log-group-name "/bluegreen/dev/docker" \
  --order-by LastEventTime --descending --limit 1
```

## What to share back
- Output from steps **3**, **4**, and **6**.
