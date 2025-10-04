locals {
  fqdn = "${var.subdomain}.${var.domain_name}"
  fqdn_sanitized    = replace(local.fqdn, ".", "-")
  policy_name_clean = "security-headers-${local.fqdn_sanitized}"
  cloudfront_distribution_id = module.cloudfront_site.aws_cloudfront_distribution.id
  cloudfront_arn = "arn:aws:cloudfront::${data.aws_caller_identity.this.account_id}:distribution/${local.cloudfront_distribution_id}"
}