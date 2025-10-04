resource "aws_route53_record" "a_alias" {
  zone_id = var.aws_route53_zone.zone_id
  name    = var.fqdn
  type    = "A"
  alias {
    name                   = var.aws_cloudfront_distribution.domain_name
    zone_id                = var.aws_cloudfront_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "aaaa_alias" {
  zone_id = var.aws_route53_zone.zone_id
  name    = var.fqdn
  type    = "AAAA"
  alias {
    name                   = var.aws_cloudfront_distribution.domain_name
    zone_id                = var.aws_cloudfront_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "apex_a" {
  zone_id = var.aws_route53_zone.zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = var.aws_cloudfront_distribution.domain_name
    zone_id                = var.aws_cloudfront_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "apex_aaaa" {
  zone_id = var.aws_route53_zone.zone_id
  name    = var.domain_name
  type    = "AAAA"
  alias {
    name                   = var.aws_cloudfront_distribution.domain_name
    zone_id                = var.aws_cloudfront_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}