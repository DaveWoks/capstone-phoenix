terraform {
  backend "s3" {
    bucket  = "phoenix-terraform-state-116248808150"
    key     = "terraform.tfstate"
    region  = "eu-west-1"
    encrypt = true
  }
}