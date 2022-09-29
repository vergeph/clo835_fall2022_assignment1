#  Define the provider
provider "aws" {
  region = "us-east-1"
}

# Data source for AMI id
data "aws_ami" "latest_amazon_linux" {
  owners      = ["amazon"]
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}


# Data source for availability zones in us-east-1
data "aws_availability_zones" "available" {
  state = "available"
}

# Data block to retrieve the default VPC id
data "aws_vpc" "default" {
  default = true
}

# Define tags locally
locals {
  default_tags = merge(module.globalvars.default_tags, { "env" = var.env })
  prefix       = module.globalvars.prefix
  name_prefix  = "${local.prefix}-${var.env}"
}

# Retrieve global variables from the Terraform module
module "globalvars" {
  source = "../../modules/globalvars"
}

# Reference subnet provisioned by 01-Networking 
resource "aws_instance" "my_amazon" {
  ami                         = data.aws_ami.latest_amazon_linux.id
  instance_type               = lookup(var.instance_type, var.env)
  key_name                    = aws_key_pair.my_key.key_name
  vpc_security_group_ids      = [aws_security_group.my_sg.id]
  associate_public_ip_address = false
  iam_instance_profile        = data.aws_iam_instance_profile.lab_profile.name
  user_data  			= file("install_update.sh")
  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.default_tags,
    {
      "Name" = "${local.name_prefix}-Amazon-Linux"
    }
  )
}


# Adding SSH key to Amazon EC2
resource "aws_key_pair" "my_key" {
  key_name   = local.name_prefix
  public_key = file("${local.name_prefix}.pub")
}

# Security Group
resource "aws_security_group" "my_sg" {
  name        = "allow_ssh_web"
  description = "Allow SSH and Web inbound traffic"
  vpc_id      = data.aws_vpc.default.id

dynamic "ingress" {
    for_each = var.sg_ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      cidr_blocks = ["0.0.0.0/0"]
      protocol    = "tcp"
    }
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(local.default_tags,
    {
      "Name" = "${local.name_prefix}-sg"
    }
  )
}

# Elastic IP
resource "aws_eip" "static_eip" {
  instance = aws_instance.my_amazon.id
  tags = merge(local.default_tags,
    {
      "Name" = "${local.name_prefix}-eip"
    }
  )
}

# AWS ECR Repository Creation
resource "aws_ecr_repository" "ecr_repository" {
  for_each             = var.ecr_repo
  name                 = "${local.name_prefix}-${each.value}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

data "aws_iam_instance_profile" "lab_profile" {
  name = "LabInstanceProfile"
}

# Test ALB 
data "aws_subnet_ids" "public_sn" {
vpc_id = data.aws_vpc.default.id
}

#subnets = data.aws_subnet_ids.public_sn.ids

#ALB for App EC2 Container
 resource "aws_lb" "alb" {
  name               = "${local.name_prefix}-${var.env}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.my_sg.id]
  subnets = data.aws_subnet_ids.public_sn.ids
  enable_deletion_protection = false
}

resource "aws_lb_listener" "alb0" {
  load_balancer_arn = aws_lb.alb.arn
  port     = "80"
  protocol = "HTTP"
  
   default_action {
    target_group_arn = aws_lb_target_group.alb_tg.arn
    type             = "forward"
  }
}

resource "aws_lb_listener" "alb1" {
  load_balancer_arn = aws_lb.alb.arn
  port     = "8081"
  protocol = "HTTP"
  
   default_action {
    target_group_arn = aws_lb_target_group.alb_tg.arn
    type             = "forward"
  }
}

resource "aws_lb_listener" "alb2" {
  load_balancer_arn = aws_lb.alb.arn
  port     = "8082"
  protocol = "HTTP"
  
   default_action {
    target_group_arn = aws_lb_target_group.alb_tg.arn
    type             = "forward"
  }
}

resource "aws_lb_listener" "alb3" {
  load_balancer_arn = aws_lb.alb.arn
  port     = "8083"
  protocol = "HTTP"
  
   default_action {
    target_group_arn = aws_lb_target_group.alb_tg.arn
    type             = "forward"
  }
}
 resource "aws_lb_target_group" "alb_tg" {
  name     = "${local.name_prefix}-${var.env}-tg"
  port     = 80
  target_type = "instance"
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
 }
 
resource "aws_alb_target_group_attachment" "tga01" {
  target_group_arn = aws_lb_target_group.alb_tg.arn
  target_id        = aws_instance.my_amazon.id
  port             = 8081
}

resource "aws_alb_target_group_attachment" "tga02" {
  target_group_arn = aws_lb_target_group.alb_tg.arn
  target_id        = aws_instance.my_amazon.id
  port             = 8082
}

resource "aws_alb_target_group_attachment" "tga03" {
  target_group_arn = aws_lb_target_group.alb_tg.arn
  target_id        = aws_instance.my_amazon.id
  port             = 8083
}

