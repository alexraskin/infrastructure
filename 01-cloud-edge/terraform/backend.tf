terraform {
  backend "s3" {
    bucket       = "alexraskin-tfstate"
    key          = "infrastructure/edge/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
