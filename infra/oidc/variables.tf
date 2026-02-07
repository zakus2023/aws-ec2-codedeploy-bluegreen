variable "region" {
          type    = string
          default = "us-east-1"
        }

        variable "github_org" {
          type = string
        }

        variable "github_repo" {
          type = string
        }

        variable "role_name" {
          type    = string
          default = "github-actions-bluegreen"
        }