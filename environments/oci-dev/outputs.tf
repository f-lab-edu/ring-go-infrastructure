output "database_server_public_ip" {
  description = "Public IP of database server"
  value       = oci_core_instance.database_server.public_ip
}

output "database_server_private_ip" {
  description = "Private IP of database server"
  value       = oci_core_instance.database_server.private_ip
}