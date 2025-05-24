output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.app_server.id
}

output "public_ip" {
  description = "EC2 public IP"
  value       = aws_instance.app_server.public_ip
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.app_server.id
}