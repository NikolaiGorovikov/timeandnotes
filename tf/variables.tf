variable "domain_name" {
  description = "Root domain you own"
  type        = string
}

variable "subdomain" {
  description = "Subdomain for the static site (e.g., 'www' or 'static')"
  type        = string
  default     = "www"
}

variable "github_owner" {
  description = "GitHub org/user that owns the repo"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without owner)"
  type        = string
}

variable "github_branch" {
  description = "Branch that is allowed to assume the role (e.g., main)"
  type        = string
  default     = "main"
}

variable "s3_key_prefix" {
  description = "Optional key prefix within the bucket (no leading slash). Empty means bucket root."
  type        = string
  default     = ""
}

variable "region_primary" {
  type = string
  default = "ca-central-1"
}