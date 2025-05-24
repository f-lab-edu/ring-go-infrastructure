output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "app_server_public_ip" {
  description = "Application server public IP"
  value       = module.compute.public_ip
}

output "app_server_url" {
  description = "Application server URL"
  value       = "http://${module.compute.public_ip}:8080"
}
