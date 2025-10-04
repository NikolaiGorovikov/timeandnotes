output "site_domain" {
  value = local.fqdn
}
output "cloudfront_domain" {
  value = module.cloudfront_site.aws_cloudfront_distribution.domain_name
}

output "github_actions_role_arn" {
  value       = module.ci_github_oidc.role_arn
  description = "Use this as role-to-assume in GitHub Actions"
}

output "github_oidc_provider_arn" {
  value       = module.ci_github_oidc.provider_arn
  description = "OIDC provider ARN"
}