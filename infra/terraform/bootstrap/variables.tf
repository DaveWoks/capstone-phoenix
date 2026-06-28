variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "eu-west-1"
}

variable "state_bucket_name" {
  description = "Terraform state bucket name"
  type        = string
  default     = "phoenix-terraform-state-116248808150"
}