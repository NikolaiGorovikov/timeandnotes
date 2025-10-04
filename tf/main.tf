data "aws_route53_zone" "this" {
  name         = var.domain_name
  private_zone = false
}

resource "aws_s3_bucket" "site" {
  bucket = local.fqdn
  force_destroy = true
}

data "aws_caller_identity" "current" {}
data "aws_caller_identity" "this" {}

module "ci_github_oidc" {
  source = "./modules/ci-github-oidc"

  github_owner  = var.github_owner
  github_repo   = var.github_repo
  github_branch = var.github_branch
  s3_bucket_name = local.fqdn

  s3_key_prefix = var.s3_key_prefix
  cloudfront_arn = local.cloudfront_arn
}

module "certificate" {
  source = "./modules/certificate"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  domain_name = var.domain_name
  fqdn = local.fqdn
  aws_route53_zone = data.aws_route53_zone.this
}

module "s3_site" {
  source = "./modules/s3-site"

  aws_cloudfront_distribution = module.cloudfront_site.aws_cloudfront_distribution
  aws_s3_bucket = aws_s3_bucket.site
  aws_caller_identity = data.aws_caller_identity.current
}

module "cloudfront_site" {
  source = "./modules/cloudfront-site"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  domain_name = var.domain_name
  subdomain = var.subdomain
  fqdn = local.fqdn
  policy_name_clean = local.policy_name_clean
  aws_s3_bucket = aws_s3_bucket.site
  aws_acm_certificate_validation = module.certificate.aws_acm_certificate_validation
}

module "dns" {
  source = "./modules/dns"

  domain_name = var.domain_name
  fqdn = local.fqdn

  aws_route53_zone = data.aws_route53_zone.this
  aws_cloudfront_distribution = module.cloudfront_site.aws_cloudfront_distribution
}