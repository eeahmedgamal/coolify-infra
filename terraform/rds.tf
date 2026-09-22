resource "aws_db_subnet_group" "coolify" {
  name       = "coolify-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id
  tags       = { Name = "coolify-db-subnet-group" }
}

# Forces TLS at the server level - RDS itself rejects any unencrypted
# connection attempt, rather than relying on the client (Coolify) to
# request encryption. PostgreSQL's standard client library negotiates
# TLS automatically when the server requires it, so this works
# transparently with Coolify's Postgres connection - unlike ElastiCache,
# where Coolify's Redis client has no TLS support at all (see
# elasticache.tf's notes).
resource "aws_db_parameter_group" "coolify_force_ssl" {
  name   = "coolify-postgres-force-ssl"
  family = "postgres16"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
}

resource "random_password" "db" {
  length  = 24
  special = false
}

resource "random_bytes" "app_key" {
  length = 32
}

resource "aws_secretsmanager_secret" "app_key" {
  name                    = "coolify/app-key"
  recovery_window_in_days = 0
}
resource "aws_secretsmanager_secret_version" "app_key" {
  secret_id     = aws_secretsmanager_secret.app_key.id
  secret_string = "base64:${random_bytes.app_key.base64}"
}

# Generates once per deployment and stays stable across every future
# `terraform plan` (unlike timestamp(), which re-evaluates - and shows as
# a "change" - on every single plan). A fresh value only appears after a
# full destroy + recreate, which is exactly when a new unique name is
# actually needed to avoid colliding with the previous deployment's
# final snapshot.
resource "random_id" "final_snapshot_suffix" {
  byte_length = 4
}

resource "aws_db_instance" "coolify" {
  identifier             = "coolify-prod-db"
  engine                 = "postgres"
  engine_version         = var.postgres_engine_version
  instance_class         = var.db_instance_class
  allocated_storage      = 30
  storage_type           = "gp3"
  storage_encrypted      = true
  # kms_key_id intentionally omitted - AWS uses the default "aws/rds"
  # managed key automatically. Free, and sufficient for this setup.
  db_name                = "coolify"
  username               = "coolify"
  password               = random_password.db.result
  db_subnet_group_name   = aws_db_subnet_group.coolify.name
  parameter_group_name   = aws_db_parameter_group.coolify_force_ssl.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false
  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  # Blocks any accidental `terraform destroy` (or a manual console
  # deletion) from taking down the production database - AWS refuses the
  # delete outright while this is true. To genuinely destroy this instance
  # on purpose, first set this to false, `terraform apply` that change
  # alone, and only then run `terraform destroy` (or delete it manually).
  deletion_protection    = true
  # A final snapshot is created on destroy, with a name unique to this
  # deployment (see random_id.final_snapshot_suffix above) so it never
  # collides with a snapshot left over from a previous destroy.
  skip_final_snapshot    = false
  final_snapshot_identifier = "coolify-prod-db-final-${random_id.final_snapshot_suffix.hex}"
  tags = { Name = "coolify-prod-db" }
}

resource "aws_secretsmanager_secret" "db_password" {
  name                    = "coolify/db-password"
  recovery_window_in_days = 0
}
resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db.result
}

resource "aws_secretsmanager_secret" "db_endpoint" {
  name                    = "coolify/rds-endpoint"
  recovery_window_in_days = 0
}
resource "aws_secretsmanager_secret_version" "db_endpoint" {
  secret_id     = aws_secretsmanager_secret.db_endpoint.id
  secret_string = aws_db_instance.coolify.address
}

resource "aws_secretsmanager_secret" "db_username" {
  name                    = "coolify/db-username"
  recovery_window_in_days = 0
}
resource "aws_secretsmanager_secret_version" "db_username" {
  secret_id     = aws_secretsmanager_secret.db_username.id
  secret_string = "coolify"
}
