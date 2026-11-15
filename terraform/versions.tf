terraform {
  required_version = ">= 1.10"   # needed for S3-native state locking (use_lockfile)
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.70" }
  }
  # Partial config; bucket/key/region supplied with -backend-config (see README).
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region
  default_tags { tags = { Project = var.project, Environment = var.environment, ManagedBy = "terraform" } }
}
