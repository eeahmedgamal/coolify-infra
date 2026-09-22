terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  backend "s3" {
    # LIMITATION: Terraform's `backend` block cannot reference variables at
    # all (a hard restriction of Terraform itself, not something this repo
    # can work around). If you change the region for a different case, this
    # line must be updated by hand, or overridden at `terraform init` time:
    #   terraform init -backend-config="region=<new-region>"
    bucket = "coolify-terraform-state-333596351046"
    key    = "production/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      product     = var.tag_product
      environment = var.tag_environment
      owner       = var.tag_owner
    }
  }
}
