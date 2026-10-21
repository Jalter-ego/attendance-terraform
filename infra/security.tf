resource "aws_security_group" "frontend" {
  name        = "${var.deployment_name}-frontend"
  description = "Public HTTP and operator-only SSH"
  vpc_id      = aws_vpc.lab.id
  tags        = { Name = "${var.deployment_name}-frontend" }
}

resource "aws_security_group" "backend" {
  name        = "${var.deployment_name}-backend"
  description = "API from frontend only; operator-only SSH; no public PostgreSQL"
  vpc_id      = aws_vpc.lab.id
  tags        = { Name = "${var.deployment_name}-backend" }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  description       = "Allow public HTTP access to the frontend on port 80"
  security_group_id = aws_security_group.frontend.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each          = { frontend = aws_security_group.frontend.id, backend = aws_security_group.backend.id }
  description       = "Allow operator SSH access to ${each.key} from the primary authorized CIDR"
  security_group_id = each.value
  cidr_ipv4         = var.ssh_allowed_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "api" {
  description                  = "Allow the frontend to access the backend API on TCP port 5000"
  security_group_id            = aws_security_group.backend.id
  referenced_security_group_id = aws_security_group.frontend.id
  from_port                    = 5000
  to_port                      = 5000
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "additional_ssh" {
  for_each = {
    for pair in setproduct(["frontend", "backend"], setsubtract(var.additional_ssh_allowed_cidrs, toset([var.ssh_allowed_cidr]))) :
    "${pair[0]}:${pair[1]}" => { role = pair[0], cidr = pair[1] }
  }
  description       = "Allow operator SSH access to ${each.value.role} from an additional authorized CIDR"
  security_group_id = each.value.role == "frontend" ? aws_security_group.frontend.id : aws_security_group.backend.id
  cidr_ipv4         = each.value.cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "outbound" {
  for_each          = { frontend = aws_security_group.frontend.id, backend = aws_security_group.backend.id }
  description       = "Allow all IPv4 outbound traffic from ${each.key}"
  security_group_id = each.value
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
