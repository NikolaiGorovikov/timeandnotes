terraform {
  backend "s3" {
    bucket         = "nikolai-playground-terraform-states"
    key            = "www.timeandnotes.com" # this should be changed
    region         = "ca-central-1"
    encrypt        = true
  }
}