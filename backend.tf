terraform {
  backend "s3" {
    bucket       = "terraform-state-omar-2026"
    key          = "global/s3/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}
