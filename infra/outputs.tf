output "frontend_url" {
  value = "http://${aws_instance.app["frontend"].public_ip}"
}

output "frontend_ip" {
  value = aws_instance.app["frontend"].public_ip
}

output "frontend_base_domain" {
  value = "${replace(aws_instance.app["frontend"].public_ip, ".", "-")}.sslip.io"
}

output "frontend_demo_url" {
  value = "http://demo.${replace(aws_instance.app["frontend"].public_ip, ".", "-")}.sslip.io/"
}

output "backend_ip" {
  value = aws_instance.app["backend"].public_ip
}

output "backend_private_ip" {
  value = aws_instance.app["backend"].private_ip
}

output "instance_ids" {
  value = { for role, instance in aws_instance.app : role => instance.id }
}

output "deployment_name" {
  value = var.deployment_name
}
