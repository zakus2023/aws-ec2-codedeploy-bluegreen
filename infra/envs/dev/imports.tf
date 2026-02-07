data "aws_caller_identity" "current" {}

data "aws_guardduty_detector" "current" {}

import {
  to = module.platform.aws_cloudwatch_log_group.docker
  id = "/${var.project}/dev/docker"
}

import {
  to = module.platform.aws_cloudwatch_log_group.system
  id = "/${var.project}/dev/system"
}

import {
  to = module.platform.aws_codedeploy_app.app
  id = "${var.project}-dev-codedeploy-app"
}

import {
  to = module.platform.aws_codedeploy_deployment_group.dg
  id = "${var.project}-dev-codedeploy-app:${var.project}-dev-dg"
}

import {
  to = module.platform.aws_iam_role.ec2_role
  id = "${var.project}-dev-ec2-role"
}

import {
  to = module.platform.aws_iam_instance_profile.ec2_profile
  id = "${var.project}-dev-ec2-profile"
}

import {
  to = module.platform.aws_cloudtrail.trail
  id = "arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/${var.project}-dev-trail"
}

import {
  to = module.platform.aws_guardduty_detector.gd
  id = data.aws_guardduty_detector.current.id
}

import {
  to = module.platform.aws_securityhub_account.sh
  id = data.aws_caller_identity.current.account_id
}
