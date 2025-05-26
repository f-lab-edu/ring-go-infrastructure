# Remote State Backend 설정
terraform {
  backend "s3" {
    bucket         = "ring-go-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "ring-go-terraform-lock"
    encrypt        = true
  }
}
