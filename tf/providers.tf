provider "aws" {
  region = "ca-central-1"
}

# CloudFront/ACM certs MUST be in us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}