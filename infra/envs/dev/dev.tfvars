# Project and region (match bootstrap; region must be same as where bootstrap ran)
project = "bluegreen"
region  = "us-east-1"

# Domain and DNS: use a subdomain of your Route53 zone (e.g. my-iifb.com → dev-app.my-iifb.com)
# Get hosted_zone_id from Route53 → Hosted zones → click your zone (e.g. my-iifb.com) → copy "Hosted zone ID"
domain_name    = "dev-app.my-iifb.click"
hosted_zone_id = "Z04241223G31RGIMMIL2C"
alarm_email    = "idbsch2012@gmail.com"

# From bootstrap output: run "terraform output" in infra/bootstrap/ and copy cloudtrail_bucket
cloudtrail_bucket = "bluegreen-cloudtrail-20260208223709260100000001"

# VPC and subnets for dev (use a different CIDR than prod, e.g. 10.20.x for dev, 10.30.x for prod)
vpc_cidr       = "10.20.0.0/16"
public_subnets = ["10.20.1.0/24", "10.20.2.0/24"]
private_subnets = ["10.20.11.0/24", "10.20.12.0/24"]

# Instance size and ASG: dev = 1 instance, prod can be 2+ for HA
instance_type    = "t3.micro"
min_size         = 1
max_size         = 2
desired_capacity = 1

# Leave empty to use latest Amazon Linux 2; or set a specific AMI id
ami_id = "ami-0532be01f26a3de55"

# Disable deployment alarms in dev to allow initial bootstrap
enable_deployment_alarms = false