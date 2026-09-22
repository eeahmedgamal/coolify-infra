# One independent SSH key per runtime server (see conversation: never shared).
resource "tls_private_key" "runtime" {
  for_each  = toset(var.runtime_server_names)
  algorithm = "ED25519"
}

resource "aws_key_pair" "runtime" {
  for_each   = toset(var.runtime_server_names)
  key_name   = "coolify-${each.key}-key"
  public_key = tls_private_key.runtime[each.key].public_key_openssh
}

resource "aws_secretsmanager_secret" "runtime_ssh_key" {
  for_each                = toset(var.runtime_server_names)
  name                    = "coolify/ssh-keys/${each.key}"
  recovery_window_in_days = 0
}
resource "aws_secretsmanager_secret_version" "runtime_ssh_key" {
  for_each      = toset(var.runtime_server_names)
  secret_id     = aws_secretsmanager_secret.runtime_ssh_key[each.key].id
  secret_string = tls_private_key.runtime[each.key].private_key_openssh
}

resource "aws_instance" "runtime" {
  for_each                = toset(var.runtime_server_names)
  ami                     = local.ami_id
  instance_type           = var.runtime_instance_type
  subnet_id               = aws_subnet.public[index(var.runtime_server_names, each.key) % length(aws_subnet.public)].id
  vpc_security_group_ids  = [aws_security_group.runtime.id]
  key_name                = aws_key_pair.runtime[each.key].key_name
  iam_instance_profile    = aws_iam_instance_profile.runtime.name

  root_block_device {
    volume_size = 40
    volume_type = "gp3"
    encrypted   = true
  }

  # Runtime servers only need Docker - Coolify itself is not installed here.
  # They get registered as Coolify "Servers" afterward via
  # Coolify's own Dashboard (Security -> Private Keys, then Servers -> New
  # Server), using the private key from Secrets Manager (manual, one time
  # per server).
  user_data = <<-EOF
    #!/usr/bin/env bash
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
  EOF

  tags = { Name = "coolify-${each.key}" }
}

resource "aws_eip" "runtime" {
  for_each = toset(var.runtime_server_names)
  instance = aws_instance.runtime[each.key].id
  domain   = "vpc"
  tags     = { Name = "coolify-${each.key}-eip" }
}
