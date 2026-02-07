terraform {
          required_version = ">= 1.6.0"
          required_providers {
            aws = { source = "hashicorp/aws", version = ">= 5.0" }
          }
        }

        provider "aws" {
          region = var.region
        }

        data "aws_iam_policy_document" "github_oidc_assume_role" {
          statement {
            actions = ["sts:AssumeRoleWithWebIdentity"]
            principals {
              type        = "Federated"
              identifiers = [aws_iam_openid_connect_provider.github.arn]
            }
            condition {
              test     = "StringEquals"
              variable = "token.actions.githubusercontent.com:aud"
              values   = ["sts.amazonaws.com"]
            }
            condition {
              test     = "StringLike"
              variable = "token.actions.githubusercontent.com:sub"
              values   = ["repo:${var.github_org}/${var.github_repo}:*"]
            }
          }
        }

        resource "aws_iam_openid_connect_provider" "github" {
          url             = "https://token.actions.githubusercontent.com"
          client_id_list  = ["sts.amazonaws.com"]
          thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
        }

        resource "aws_iam_role" "github_actions" {
          name               = var.role_name
          assume_role_policy = data.aws_iam_policy_document.github_oidc_assume_role.json
        }

        resource "aws_iam_role_policy" "github_actions" {
          name = "${var.role_name}-policy"
          role = aws_iam_role.github_actions.id
          policy = jsonencode({
            Version = "2012-10-17"
            Statement = [
              {
                Effect = "Allow"
                Action = [
                  "s3:*",
                  "dynamodb:*",
                  "iam:*",
                  "ec2:*",
                  "elasticloadbalancing:*",
                  "autoscaling:*",
                  "acm:*",
                  "route53:*",
                  "logs:*",
                  "cloudwatch:*",
                  "sns:*",
                  "ssm:*",
                  "ecr:*",
                  "codedeploy:*"
                ]
                Resource = "*"
              }
            ]
          })
        }