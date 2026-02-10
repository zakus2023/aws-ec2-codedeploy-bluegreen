# Optional: trigger Ansible deploy from Terraform (local-exec).
resource "null_resource" "ansible_deploy" {
  count = var.trigger_ansible_deploy != "" ? 1 : 0

  triggers = {
    run = var.trigger_ansible_deploy
  }

  provisioner "local-exec" {
    command     = "ansible-playbook -i ansible/inventory/ec2_prod.aws_ec2.yml ansible/playbooks/deploy.yml"
    working_dir = "${path.module}/../../.."
  }

  depends_on = [module.platform]
}
