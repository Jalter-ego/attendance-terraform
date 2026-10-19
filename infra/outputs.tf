output "frontend_url" {
  value = try("http://${aws_instance.app["frontend"].public_ip}", null)
}

output "frontend_ip" {
  value = try(aws_instance.app["frontend"].public_ip, null)
}

output "frontend_base_domain" {
  value = try("${replace(aws_instance.app["frontend"].public_ip, ".", "-")}.sslip.io", null)
}

output "frontend_demo_url" {
  value = try("http://demo.${replace(aws_instance.app["frontend"].public_ip, ".", "-")}.sslip.io/", null)
}

output "backend_ip" {
  value = try(aws_instance.app["backend"].public_ip, null)
}

output "backend_private_ip" {
  value = try(aws_instance.app["backend"].private_ip, null)
}

output "instance_ids" {
  value = { for role, instance in aws_instance.app : role => instance.id }
}

output "deployment_name" {
  value = var.deployment_name
}
