terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
  backend "s3" {}
}

provider "aws" {
  region = var.region
}

module "platform" {
  source = "../../modules/platform"

  project        = var.project
  region         = var.region
  env            = "prod"
  domain_name    = var.domain_name
  hosted_zone_id = var.hosted_zone_id
  alarm_email    = var.alarm_email

  vpc_cidr        = var.vpc_cidr
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets

  instance_type    = var.instance_type
  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  ami_id = var.ami_id

  cloudtrail_bucket = var.cloudtrail_bucket

  enable_guardduty  = var.enable_guardduty
  enable_securityhub = var.enable_securityhub
  enable_inspector2 = var.enable_inspector2
  enable_config     = var.enable_config
}