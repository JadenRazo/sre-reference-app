terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.name_prefix
      ManagedBy = "terraform"
      Owner     = "JadenRazo"
      Repo      = "https://github.com/JadenRazo/sre-reference-app"
    }
  }
}

# Some AWS services (CloudWatch billing metrics, certain global IAM operations
# tied to the OIDC provider) live in us-east-1 regardless of the deploy region.
# This aliased provider exists so the cicd module can use it for those resources.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = var.name_prefix
      ManagedBy = "terraform"
      Owner     = "JadenRazo"
      Repo      = "https://github.com/JadenRazo/sre-reference-app"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
