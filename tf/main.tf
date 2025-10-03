############################################################
# EDIT THESE FOR YOUR DOMAIN
############################################################
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.50.0"
    }
  }

  backend "s3" {
    bucket         = "my-tf-state-nikolai-12345"
    key            = "projectA/prod/terraform.tfstate" # path *inside* the bucket
    region         = "ca-central-1"
    encrypt        = true
  }
}

# Primary region for your account (any region you like)
provider "aws" {
  region = "ca-central-1"
}

# CloudFront/ACM certs MUST be in us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

############################################################
# VARIABLES (quick edit here)
############################################################
variable "domain_name" {
  description = "Root domain you own"
  type        = string
  default     = "timeandnotes.com"
}
variable "subdomain" {
  description = "Subdomain for the static site (e.g., 'www' or 'static')"
  type        = string
  default     = "www"
}

locals {
  fqdn = "${var.subdomain}.${var.domain_name}"
  fqdn_sanitized    = replace(local.fqdn, ".", "-") # dots → dashes
  policy_name_clean = "security-headers-${local.fqdn_sanitized}"
}

############################################################
# ROUTE 53 ZONE (assumes your domain is hosted in Route 53)
############################################################
data "aws_route53_zone" "this" {
  name         = var.domain_name
  private_zone = false
}

############################################################
# S3 BUCKET (private, OAC-only)
############################################################
resource "aws_s3_bucket" "site" {
  bucket = local.fqdn
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

############################################################
# ACM CERTIFICATE (us-east-1 for CloudFront)
############################################################
resource "aws_acm_certificate" "cf" {
  provider          = aws.us_east_1
  domain_name       = var.domain_name                  # apex, e.g., timeandnotes.com
  subject_alternative_names = [
    local.fqdn                                         # e.g., www.timeandnotes.com
  ]
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
  for dvo in aws_acm_certificate.cf.domain_validation_options : dvo.domain_name => {
    name  = dvo.resource_record_name
    type  = dvo.resource_record_type
    value = dvo.resource_record_value
  }
  }

  zone_id = data.aws_route53_zone.this.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.value]
}

resource "aws_acm_certificate_validation" "cf" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cf.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

############################################################
# CLOUDFRONT: OAC + Response Headers Policy (security)
############################################################
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "oac-${local.fqdn}"
  description                       = "OAC for ${local.fqdn}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Security headers (HSTS, X-Frame-Options, etc.)
resource "aws_cloudfront_response_headers_policy" "security" {
  name = local.policy_name_clean

  security_headers_config {
    content_type_options { override = true }
    frame_options        {
      frame_option = "DENY"
      override = true
    }
    referrer_policy      {
      referrer_policy = "strict-origin-when-cross-origin"
      override = true
    }
    strict_transport_security {
      access_control_max_age_sec = 63072000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
    xss_protection {
      mode_block = true
      protection = true
      override = true
    }
  }
}

# Use AWS managed "CachingOptimized" policy
data "aws_cloudfront_cache_policy" "managed_optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = local.fqdn
  default_root_object = "index.html"

  aliases = [local.fqdn, var.domain_name]

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "s3-${aws_s3_bucket.site.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-${aws_s3_bucket.site.id}"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]
    compress        = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.redirect_apex_to_www.arn
    }

    cache_policy_id            = data.aws_cloudfront_cache_policy.managed_optimized.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn            = aws_acm_certificate_validation.cf.certificate_arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2021"
  }
}

resource "aws_route53_record" "apex_a" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "apex_aaaa" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = var.domain_name
  type    = "AAAA"
  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_cloudfront_function" "redirect_apex_to_www" {
  name    = "redirect-apex-to-www"
  runtime = "cloudfront-js-1.0"
  comment = "301 redirect timeandnotes.com -> www.timeandnotes.com"
  publish = true
  code    = <<-EOF
function handler(event) {
  var req  = event.request;
  var host = req.headers.host.value.toLowerCase();

  var apex = "timeandnotes.com";
  var www  = "www.timeandnotes.com";

  // Build query string from the structured object
  function buildQuery(qs) {
    var parts = [];
    for (var k in qs) {
      if (!qs.hasOwnProperty(k)) continue;
      var entry = qs[k];
      if (entry.multiValue && entry.multiValue.length) {
        for (var i = 0; i < entry.multiValue.length; i++) {
          parts.push(k + "=" + entry.multiValue[i].value);
        }
      } else if (entry.value !== undefined) {
        parts.push(k + "=" + entry.value);
      }
    }
    return parts.length ? ("?" + parts.join("&")) : "";
  }

  if (host === apex) {
    var location = "https://" + www + req.uri + buildQuery(req.querystring || {});
    return {
      statusCode: 301,
      statusDescription: "Moved Permanently",
      headers: { location: { value: location } }
    };
  }
  return req;
}
EOF
}

############################################################
# S3 BUCKET POLICY (allow only CloudFront via OAC)
############################################################
data "aws_caller_identity" "current" {}

# Allow GetObject ONLY when the request comes through *this* CloudFront distribution
resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid      = "AllowCloudFrontServicePrincipalReadOnly"
        Effect   = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action = ["s3:GetObject"]
        Resource = [
          "${aws_s3_bucket.site.arn}/*"
        ]
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/${aws_cloudfront_distribution.this.id}"
          }
        }
      }
    ]
  })
}

############################################################
# ROUTE 53 DNS -> CloudFront
############################################################
resource "aws_route53_record" "a_alias" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = local.fqdn
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "aaaa_alias" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = local.fqdn
  type    = "AAAA"
  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}


# ---- Inputs you should set (via *.tfvars or -var) ----
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

variable "s3_bucket_name" {
  description = "Target S3 bucket for the built site (e.g., www.timeandnotes.com)"
  type        = string
}

variable "cloudfront_distribution_id" {
  description = "CloudFront distribution ID to invalidate (leave empty if none)"
  type        = string
  default     = ""
}

# Optional: Narrow S3 permissions to a specific prefix (e.g., 'site/')
variable "s3_key_prefix" {
  description = "Optional key prefix within the bucket (no leading slash). Empty means bucket root."
  type        = string
  default     = ""
}

# ------------------------------------------------------

data "aws_caller_identity" "this" {}

# 1) GitHub OIDC Provider (well-known, global)
#    Thumbprint is for DigiCert Global Root G2 (GitHub OIDC).
#    Ref: https://docs.github.com/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# Helper locals
locals {
  repo_sub      = "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/${var.github_branch}"
  bucket_arn    = "arn:aws:s3:::${var.s3_bucket_name}"
  bucket_objs   = var.s3_key_prefix == "" ? "${local.bucket_arn}/*" : "${local.bucket_arn}/${var.s3_key_prefix}/*"

  # CloudFront ARNs use account id + distribution id
  cloudfront_arn = var.cloudfront_distribution_id == "" ? null : "arn:aws:cloudfront::${data.aws_caller_identity.this.account_id}:distribution/${var.cloudfront_distribution_id}"
}

# 2) Trust policy: allow GitHub Actions (this repo/branch) to assume the role via OIDC
data "aws_iam_policy_document" "assume_role" {
  statement {
    sid     = "GitHubOIDCAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Lock to a single repo + branch (pushes to that branch)
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.repo_sub]
    }

    # Examples if you later want to allow more (uncomment & adjust):
     condition {
       test     = "StringLike"
       variable = "token.actions.githubusercontent.com:sub"
       values   = [
         "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/main",
         "repo:${var.github_owner}/${var.github_repo}:ref:refs/tags/*",
         "repo:${var.github_owner}/${var.github_repo}:pull_request",
         "repo:${var.github_owner}/${var.github_repo}:environment:prod"
       ]
     }
  }
}

# 3) Permissions policy: S3 sync + CloudFront invalidation
data "aws_iam_policy_document" "deploy_policy" {
  statement {
    sid     = "S3ListBucket"
    effect  = "Allow"
    actions = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [local.bucket_arn]
    # If prefix specified, scope ListBucket to that prefix
    condition {
      test     = "StringEqualsIfExists"
      variable = "s3:prefix"
      values   = [var.s3_key_prefix]
    }
  }

  statement {
    sid     = "S3ObjectRW"
    effect  = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:PutObjectTagging",
      "s3:DeleteObjectTagging",
      "s3:AbortMultipartUpload",
      "s3:ListBucketMultipartUploads",
      "s3:ListMultipartUploadParts"
    ]
    resources = [local.bucket_objs]
  }

  # CloudFront invalidation (optional)
  dynamic "statement" {
    for_each = local.cloudfront_arn == null ? [] : [1]
    content {
      sid     = "CloudFrontInvalidate"
      effect  = "Allow"
      actions = [
        "cloudfront:CreateInvalidation",
        "cloudfront:GetInvalidation"
      ]
      resources = [local.cloudfront_arn]
    }
  }
}

resource "aws_iam_policy" "deploy" {
  name        = "GithubActionsS3DeployPolicy"
  description = "Allow S3 sync to site bucket and optional CloudFront invalidation"
  policy      = data.aws_iam_policy_document.deploy_policy.json
}

resource "aws_iam_role" "github_actions_deploy" {
  name               = "GithubActionsDeployRole"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags = {
    ManagedBy = "Terraform"
    Purpose   = "GitHubActionsDeploy"
  }
}

resource "aws_iam_role_policy_attachment" "attach_deploy" {
  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = aws_iam_policy.deploy.arn
}

# ---- Outputs ----
output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions_deploy.arn
  description = "Use this as role-to-assume in GitHub Actions"
}

output "github_oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.github.arn
  description = "OIDC provider ARN"
}


############################################################
# OUTPUTS
############################################################
output "site_domain" {
  value = local.fqdn
}
output "cloudfront_domain" {
  value = aws_cloudfront_distribution.this.domain_name
}