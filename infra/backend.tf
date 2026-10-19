terraform {
  backend "s3" {
    bucket              = "attendance-tfstate-929571213233-us-east-2"
    key                 = "attendance/equipo/terraform.tfstate"
    region              = "us-east-2"
    encrypt             = true
    use_lockfile        = true
    allowed_account_ids = ["929571213233"]
  }
}
