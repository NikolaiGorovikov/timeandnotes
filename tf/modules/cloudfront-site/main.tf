resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "oac-${var.fqdn}"
  description                       = "OAC for ${var.fqdn}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "redirect_apex_to_www" {
  name    = "redirect-apex-to-www"
  runtime = "cloudfront-js-1.0"
  comment = "301 redirect ${var.domain_name} -> ${var.subdomain}.${var.domain_name}"
  publish = true
  code    = <<-EOF
function handler(event) {
  var req  = event.request;
  var host = req.headers.host.value.toLowerCase();

  var apex = "${var.domain_name}";
  var www  = "${var.subdomain}.${var.domain_name}";

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

# Security headers (HSTS, X-Frame-Options, etc.)
resource "aws_cloudfront_response_headers_policy" "security" {
  name = var.policy_name_clean

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
  comment             = var.fqdn
  default_root_object = "index.html"

  aliases = [var.fqdn, var.domain_name]

  origin {
    domain_name              = var.aws_s3_bucket.bucket_regional_domain_name
    origin_id                = "s3-${var.aws_s3_bucket.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-${var.aws_s3_bucket.id}"
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
    acm_certificate_arn            = var.aws_acm_certificate_validation.certificate_arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2021"
  }
}