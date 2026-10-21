output "frontend_url" {
  description = "Public HTTP URL of the frontend application."
  value       = try("http://${aws_instance.app["frontend"].public_ip}", null)
}

output "frontend_ip" {
  description = "Public IPv4 address of the frontend instance."
  value       = try(aws_instance.app["frontend"].public_ip, null)
}

output "frontend_base_domain" {
  description = "Base sslip.io domain derived from the frontend public IPv4 address."
  value       = try("${replace(aws_instance.app["frontend"].public_ip, ".", "-")}.sslip.io", null)
}

output "frontend_demo_url" {
  description = "Public HTTP URL of the demo tenant on the frontend."
  value       = try("http://demo.${replace(aws_instance.app["frontend"].public_ip, ".", "-")}.sslip.io/", null)
}

output "backend_ip" {
  description = "Public IPv4 address of the backend instance for operator SSH access."
  value       = try(aws_instance.app["backend"].public_ip, null)
}

output "backend_private_ip" {
  description = "Private IPv4 address used by the frontend to reach the backend API."
  value       = try(aws_instance.app["backend"].private_ip, null)
}

output "instance_ids" {
  description = "EC2 instance IDs keyed by application role: frontend and backend."
  value       = { for role, instance in aws_instance.app : role => instance.id }
}

output "deployment_name" {
  description = "Shared deployment name used to identify the team's resources."
  value       = var.deployment_name
}
