terraform {
  required_version = ">= 1.15.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100"
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
