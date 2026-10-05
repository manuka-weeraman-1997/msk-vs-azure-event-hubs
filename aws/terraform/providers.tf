terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Local state is used by default so the example runs with no extra setup.
  # REQUIRES ACCOUNT CONFIGURATION: for shared use, configure a remote backend
  # (for example an S3 bucket you own) before running `terraform init`.
}

provider "aws" {
  region = var.aws_region

  # Tags applied to every taggable resource created by this configuration.
  default_tags {
    tags = local.common_tags
  }
}
