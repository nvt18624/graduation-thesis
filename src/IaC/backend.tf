terraform {
  backend "s3" {
    bucket        = "thien-sa-terraform-backend"
    key           = "terraform/state"
    region        = "ap-southeast-1"
    use_lockfile  = true
  }
}

