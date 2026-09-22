variable "aws_region" {
  default = "us-east-1"
}

variable "account_id" {
  description = "AWS account ID, used to build ECR image URIs."
  type        = string
}

variable "vpc_cidr" {
  default = "10.60.0.0/16"
}

variable "public_subnet_cidrs" {
  default = ["10.60.0.0/24", "10.60.1.0/24"]
}

variable "private_subnet_cidrs" {
  default = ["10.60.10.0/24", "10.60.11.0/24"]
}

variable "admin_ssh_cidr" {
  description = "Your own IP range, for SSH/dashboard access to EC2 #1. Example: 203.0.113.4/32"
  type        = string
}

variable "tag_product" {
  description = "Value for the 'product' tag applied to every resource."
  type        = string
  default     = "coolify"
}

variable "tag_environment" {
  description = "Value for the 'environment' tag applied to every resource."
  type        = string
  default     = "production"
}

variable "tag_owner" {
  description = "Value for the 'owner' tag applied to every resource - typically the responsible person's email or team name. No default on purpose: set this to your own value."
  type        = string
}

variable "control_plane_instance_type" {
  default = "t3.medium"
}

variable "runtime_instance_type" {
  default = "t3.medium"
}

variable "runtime_server_names" {
  description = "Logical names for the runtime (deployment) servers."
  default     = ["runtime-2", "runtime-3"]
}

variable "coolify_versions" {
  description = "sentinel is kept here for reference (mirrored to ECR in case it's needed manually on a runtime server later) but is not used by compose/docker-compose.yml - Sentinel is not run on the Control Plane (see docker-compose.yml's notes)."
  default = {
    coolify   = "4.3.19"
    realtime  = "1.0.17"
    sentinel  = "0.0.22"
    traefik   = "v3.6"
  }
}

variable "db_instance_class" {
  default = "db.t3.small"
}

variable "postgres_engine_version" {
  description = "Verified available in us-east-1 as of this repo's last test run. Re-check with: aws rds describe-db-engine-versions --engine postgres --region <your-region> --query \"DBEngineVersions[].EngineVersion\" --output table"
  type        = string
  default     = "16.15"
}

variable "cache_node_type" {
  default = "cache.t3.micro"
}

variable "ami_id" {
  description = "Override the auto-detected Ubuntu 24.04 LTS AMI if needed. Leave empty (\"\") to auto-detect the correct one for whatever aws_region is set."
  type        = string
  default     = ""
}
