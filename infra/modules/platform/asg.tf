data "aws_ami" "al2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

locals {
  ami = var.ami_id != "" ? var.ami_id : data.aws_ami.al2.id
  user_data = <<-EOF
    #!/bin/bash
    set -e
    yum update -y
    yum install -y docker ruby wget amazon-cloudwatch-agent
    systemctl enable docker
    systemctl start docker
    REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
    cd /home/ec2-user
    wget https://aws-codedeploy-${var.region}.s3.${var.region}.amazonaws.com/latest/install
    chmod +x ./install
    ./install auto
    systemctl start codedeploy-agent
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 \
      -c ssm:/${var.project}/${var.env}/cloudwatch/agent-config -s
  EOF
}

resource "aws_launch_template" "lt" {
  name_prefix   = "${var.project}-${var.env}-lt-"
  image_id      = local.ami
  instance_type = var.instance_type
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  user_data              = base64encode(local.user_data)
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project}-${var.env}-app"
      Env  = var.env
    }
  }
}

resource "aws_autoscaling_group" "blue" {
  name                = "${var.project}-${var.env}-asg-blue"
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns   = [aws_lb_target_group.blue.arn]
  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }
  tag {
    key                 = "Name"
    value               = "${var.project}-${var.env}-blue"
    propagate_at_launch = true
  }
  tag {
    key                 = "Env"
    value               = var.env
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_group" "green" {
  name                = "${var.project}-${var.env}-asg-green"
  min_size            = 0
  max_size            = var.max_size
  desired_capacity    = 0
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns   = [aws_lb_target_group.green.arn]
  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }
  tag {
    key                 = "Name"
    value               = "${var.project}-${var.env}-green"
    propagate_at_launch = true
  }
  tag {
    key                 = "Env"
    value               = var.env
    propagate_at_launch = true
  }
}