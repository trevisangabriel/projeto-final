terraform {
  backend "s3" {
    bucket         = "fornewstate-final"
    key            = "terraform.tfstate"
    region         = "sa-east-1"
    dynamodb_table = "for_state_lock"
    encrypt        = true
  }
}