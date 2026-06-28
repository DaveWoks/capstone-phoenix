provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "capstone-phoenix"
      Environment = "production"
      ManagedBy   = "Terraform"
    }
  }
}