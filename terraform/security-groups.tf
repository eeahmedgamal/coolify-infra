# --- Control Plane (EC2 #1) ---
resource "aws_security_group" "control_plane" {
  name        = "coolify-control-plane-sg"
  description = "Coolify Dashboard + inbound SSH from admin, outbound SSH to runtime servers"
  vpc_id      = aws_vpc.coolify.id

  ingress {
    description = "HTTP (cert issuance + redirect)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS (Dashboard)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.admin_ssh_cidr]
  }
  ingress {
    description = "Dashboard direct access by IP (temporary, until domain is finalized)"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.admin_ssh_cidr]
  }
  ingress {
    description = "SSH from admin only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ssh_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "coolify-control-plane-sg" }
}

# --- Runtime servers (EC2 #2/#3) ---
resource "aws_security_group" "runtime" {
  name        = "coolify-runtime-sg"
  description = "Deployed apps (public) + SSH only from the Control Plane"
  vpc_id      = aws_vpc.coolify.id

  ingress {
    description = "HTTP (cert issuance + redirect)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS (deployed apps)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description     = "SSH only from Control Plane"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.control_plane.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "coolify-runtime-sg" }
}

# --- RDS: only reachable from the Control Plane ---
resource "aws_security_group" "rds" {
  name        = "coolify-rds-sg"
  vpc_id      = aws_vpc.coolify.id
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.control_plane.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "coolify-rds-sg" }
}

# --- ElastiCache: only reachable from the Control Plane ---
resource "aws_security_group" "elasticache" {
  name        = "coolify-elasticache-sg"
  vpc_id      = aws_vpc.coolify.id
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.control_plane.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "coolify-elasticache-sg" }
}
