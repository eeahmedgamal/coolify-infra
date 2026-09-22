resource "tls_private_key" "control_plane" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "control_plane" {
  key_name   = "coolify-control-plane-key"
  public_key = tls_private_key.control_plane.public_key_openssh
}

resource "aws_secretsmanager_secret" "control_plane_ssh_key" {
  name                    = "coolify/ssh-keys/control-plane"
  recovery_window_in_days = 0
}
resource "aws_secretsmanager_secret_version" "control_plane_ssh_key" {
  secret_id     = aws_secretsmanager_secret.control_plane_ssh_key.id
  secret_string = tls_private_key.control_plane.private_key_openssh
}

resource "aws_instance" "control_plane" {
  ami                     = local.ami_id
  instance_type          = var.control_plane_instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.control_plane.id]
  key_name               = aws_key_pair.control_plane.key_name
  iam_instance_profile   = aws_iam_instance_profile.control_plane.name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  # The docker-compose.yml and .env.template contents are read by Terraform
  # (via file()) and embedded directly into user_data below - no separate
  # file transfer/provisioner is needed, and no inbound SSH access from the
  # pipeline is required for provisioning to work.
  user_data = templatefile("${path.module}/../scripts/install-coolify.sh.tftpl", {
    aws_region              = var.aws_region
    account_id              = var.account_id
    versions                = var.coolify_versions
    docker_compose_content  = file("${path.module}/../compose/docker-compose.yml")
    env_template_content    = file("${path.module}/../compose/.env.template")
  })

  tags = { Name = "coolify-control-plane" }

  # Explicit dependencies on every secret this instance's user_data script
  # actually reads at boot (see install-coolify.sh.tftpl's get_secret
  # calls) - without these, Terraform's graph only guarantees RDS/
  # ElastiCache themselves exist first, not that the secret *values*
  # derived from them have been written yet, which is a narrow but real
  # race the script could otherwise hit.
  depends_on = [
    aws_db_instance.coolify,
    aws_elasticache_replication_group.coolify,
    aws_iam_role_policy.control_plane_ecr_and_secrets,
    aws_secretsmanager_secret_version.app_key,
    aws_secretsmanager_secret_version.db_endpoint,
    aws_secretsmanager_secret_version.db_username,
    aws_secretsmanager_secret_version.db_password,
    aws_secretsmanager_secret_version.redis_endpoint,
  ]
}

resource "aws_eip" "control_plane" {
  instance = aws_instance.control_plane.id
  domain   = "vpc"
  tags     = { Name = "coolify-control-plane-eip" }
}
