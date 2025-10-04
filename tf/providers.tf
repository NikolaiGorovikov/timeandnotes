provider "aws" {
  region = var.region_primary
}

# CloudFront/ACM certs MUST be in us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}