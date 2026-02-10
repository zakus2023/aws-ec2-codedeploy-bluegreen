# Optional: trigger Ansible deploy from Terraform (local-exec)..
# Requires Ansible + amazon.aws and community.aws collections installed.
# Run: terraform apply -var-file=dev.tfvars -var="trigger_ansible_deploy=1"
# Or run Ansible manually: see RUN_COMMANDS_ORDER.md §5b.

resource "null_resource" "ansible_deploy" {
  count = var.trigger_ansible_deploy != "" ? 1 : 0

  triggers = {
    run = var.trigger_ansible_deploy
  }

  provisioner "local-exec" {
    command     = "ansible-playbook -i ansible/inventory/ec2_dev.aws_ec2.yml ansible/playbooks/deploy.yml"
    working_dir = "${path.module}/../../.."
  }

  depends_on = [module.platform]
}
