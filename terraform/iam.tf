# --- Control Plane: pull-only ECR access + read-only access to exactly the 5 secrets it needs ---
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "control_plane" {
  name               = "coolify-control-plane-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy" "control_plane_ecr_and_secrets" {
  name = "ecr-pull-and-secrets-read"
  role = aws_iam_role.control_plane.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid      = "ECRPullOnly"
        Effect   = "Allow"
        Action   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
        Resource = "arn:aws:ecr:${var.aws_region}:${var.account_id}:repository/coolify/*"
      },
      {
        Sid    = "ReadCoolifySecretsOnly"
        Effect = "Allow"
        Action = "secretsmanager:GetSecretValue"
        # Explicit list of only the 5 secrets install-coolify.sh.tftpl
        # actually reads - NOT a coolify/* wildcard. This deliberately
        # excludes coolify/ssh-keys/* (fetched by the admin manually for
        # the Coolify GUI) and coolify/redis-auth-token (no longer read -
        # ElastiCache runs without AUTH, see elasticache.tf's notes).
        Resource = [
          aws_secretsmanager_secret.app_key.arn,
          aws_secretsmanager_secret.db_endpoint.arn,
          aws_secretsmanager_secret.db_username.arn,
          aws_secretsmanager_secret.db_password.arn,
          aws_secretsmanager_secret.redis_endpoint.arn,
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "control_plane" {
  name = "coolify-control-plane-profile"
  role = aws_iam_role.control_plane.name
}

# --- Runtime servers: no AWS permissions needed by default (SSH-driven, not API-driven) ---
resource "aws_iam_role" "runtime" {
  name               = "coolify-runtime-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_instance_profile" "runtime" {
  name = "coolify-runtime-profile"
  role = aws_iam_role.runtime.name
}
