output "artifacts_bucket" {
  value = module.platform.artifacts_bucket
}

output "codedeploy_app" {
  value = module.platform.codedeploy_app
}

output "codedeploy_group" {
  value = module.platform.codedeploy_group
}

output "https_url" {
  value = module.platform.https_url
}
