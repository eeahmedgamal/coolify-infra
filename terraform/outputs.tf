output "control_plane_public_ip" {
  value = aws_eip.control_plane.public_ip
}

output "control_plane_private_ip" {
  value = aws_instance.control_plane.private_ip
}

output "runtime_public_ips" {
  value = { for k, v in aws_eip.runtime : k => v.public_ip }
}

output "runtime_private_ips" {
  value = { for k, v in aws_instance.runtime : k => v.private_ip }
}

output "rds_endpoint" {
  value = aws_db_instance.coolify.address
}

output "rds_port" {
  value = aws_db_instance.coolify.port
}

output "elasticache_endpoint" {
  value = aws_elasticache_replication_group.coolify.primary_endpoint_address
}

output "elasticache_port" {
  value = 6379
}

output "vpc_id" {
  value = aws_vpc.coolify.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "control_plane_security_group_id" {
  value = aws_security_group.control_plane.id
}

output "runtime_security_group_id" {
  value = aws_security_group.runtime.id
}

output "runtime_ssh_key_secret_names" {
  description = "Secrets Manager secret names holding each runtime server's private SSH key."
  value       = { for k, v in aws_secretsmanager_secret.runtime_ssh_key : k => v.name }
}

output "control_plane_ssh_key_secret_name" {
  value = aws_secretsmanager_secret.control_plane_ssh_key.name
}

output "db_password_secret_name" {
  value = aws_secretsmanager_secret.db_password.name
}

output "redis_auth_token_secret_name" {
  value = aws_secretsmanager_secret.redis_auth_token.name
}
