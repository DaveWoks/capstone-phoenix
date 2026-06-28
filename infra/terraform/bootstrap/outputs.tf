output "terraform_state_bucket" {
  description = "Terraform state bucket name"

  value = aws_s3_bucket.terraform_state.bucket
}