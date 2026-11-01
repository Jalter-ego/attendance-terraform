data "aws_ami" "ubuntu" {
  owners = ["099720109477"]

  filter {
    name   = "image-id"
    values = [var.ubuntu_ami_id]
  }

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_key_pair" "operator" {
  key_name   = "${var.deployment_name}-operator"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

locals {
  # IP fija: el frontend la recibe en su user_data sin depender de la otra instancia.
  backend_private_ip = cidrhost(aws_subnet.public.cidr_block, 10)
}

resource "aws_instance" "app" {
  for_each = { frontend = aws_security_group.frontend.id, backend = aws_security_group.backend.id }

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  ebs_optimized               = true
  monitoring                  = true
  subnet_id                   = aws_subnet.public.id
  private_ip                  = each.key == "backend" ? local.backend_private_ip : null
  associate_public_ip_address = true
  vpc_security_group_ids      = [each.value]
  key_name                    = aws_key_pair.operator.key_name
  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/templates/cloud-init-${each.key}.yaml.tftpl", {
    node_version       = var.node_version
    pnpm_version       = var.pnpm_version
    backend_repo       = var.backend_repo
    backend_ref        = var.backend_ref
    frontend_repo      = var.frontend_repo
    frontend_ref       = var.frontend_ref
    backend_private_ip = local.backend_private_ip
  })

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  credit_specification {
    cpu_credits = "standard"
  }

  tags = { Name = "${var.deployment_name}-${each.key}", Role = each.key }

  depends_on = [aws_route_table_association.public]
}
