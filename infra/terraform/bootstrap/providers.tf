provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "capstone-phoenix"
      Environment = "bootstrap"
      ManagedBy   = "Terraform"
    }
  }
}