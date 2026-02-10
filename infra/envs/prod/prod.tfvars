project = "bluegreen"
region  = "us-east-1"

domain_name       = "app.my-iifb.click"
hosted_zone_id    = "Z04241223G31RGIMMIL2C"
alarm_email       = "idbsch2012@gmail.com"
cloudtrail_bucket = "bluegreen-cloudtrail-20260208223709260100000001"

vpc_cidr        = "10.30.0.0/16"
public_subnets  = ["10.30.1.0/24", "10.30.2.0/24"]
private_subnets = ["10.30.11.0/24", "10.30.12.0/24"]

instance_type    = "t3.micro"
min_size         = 2
max_size         = 4
desired_capacity = 2

ami_id = "ami-0532be01f26a3de55"

# Account-level services already enabled in this account
enable_guardduty         = false
enable_securityhub       = false
enable_inspector2        = false
enable_config            = false
enable_deployment_alarms = true
