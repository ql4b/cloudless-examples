provider "aws" {
  # NOT NEEDED if AWS_REGION is set
  # region = "us-east-1" 
}

terraform {
  required_version = ">= 1.4.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.5.0"
    }
  }
}