variable "github_owner"   {
  type = string
}

variable "github_repo"    {
  type = string
}

variable "github_branch"  {
  type = string
}

variable "s3_key_prefix"  {
  type = string
  default = ""
}

variable "cloudfront_arn" {
  type = string
}

variable "s3_bucket_name" {
  type = string
}