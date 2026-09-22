resource "aws_elasticache_subnet_group" "coolify" {
  name       = "coolify-cache-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "random_password" "redis_auth" {
  length  = 32
  special = false
}

resource "aws_elasticache_replication_group" "coolify" {
  replication_group_id       = "coolify-prod-redis"
  description                 = "Coolify queue/cache"
  engine                      = "redis"
  engine_version              = "7.1"
  node_type                   = var.cache_node_type
  num_cache_clusters           = 1
  port                        = 6379
  subnet_group_name           = aws_elasticache_subnet_group.coolify.name
  security_group_ids          = [aws_security_group.elasticache.id]
  # AWS does not allow an AUTH token without transit encryption enabled, and
  # Coolify's Redis client doesn't support TLS (rediss://) here - so both are
  # disabled together. Access is protected entirely by the Security Group
  # (only reachable from the Control Plane), not by AUTH.
  transit_encryption_enabled  = false
  apply_immediately           = true
  tags = { Name = "coolify-prod-redis" }
}

resource "aws_secretsmanager_secret" "redis_endpoint" {
  name                    = "coolify/elasticache-endpoint"
  recovery_window_in_days = 0
}
resource "aws_secretsmanager_secret_version" "redis_endpoint" {
  secret_id     = aws_secretsmanager_secret.redis_endpoint.id
  secret_string = aws_elasticache_replication_group.coolify.primary_endpoint_address
}

# NOTE: kept for reference only - not passed as an AUTH token (see comment
# above), since AWS requires transit_encryption_enabled=true for AUTH to be
# usable, which Coolify's Redis client doesn't support here.
resource "aws_secretsmanager_secret" "redis_auth_token" {
  name                    = "coolify/redis-auth-token"
  recovery_window_in_days = 0
}
resource "aws_secretsmanager_secret_version" "redis_auth_token" {
  secret_id     = aws_secretsmanager_secret.redis_auth_token.id
  secret_string = random_password.redis_auth.result
}
