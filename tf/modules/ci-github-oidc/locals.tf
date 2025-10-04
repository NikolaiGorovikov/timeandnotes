locals {
  repo_sub      = "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/${var.github_branch}"
  bucket_objs   = var.s3_key_prefix == "" ? "${local.bucket_arn}/*" : "${local.bucket_arn}/${var.s3_key_prefix}/*"
  bucket_arn    = "arn:aws:s3:::${var.s3_bucket_name}"
}