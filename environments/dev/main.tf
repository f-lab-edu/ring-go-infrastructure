terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "dev"
      Project     = "ring-go"
      ManagedBy   = "terraform"
    }
  }
}

# Parameter Store에 시크릿 값들 저장
resource "aws_ssm_parameter" "mysql_root_password" {
  name  = "/ringgo/mysql/root-password"
  type  = "SecureString"
  value = var.mysql_root_password

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_ssm_parameter" "jwt_secret" {
  name  = "/ringgo/jwt/secret"
  type  = "SecureString"
  value = var.jwt_secret

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_ssm_parameter" "oauth_kakao_client_id" {
  name  = "/ringgo/oauth/kakao/client-id"
  type  = "SecureString"
  value = var.oauth_kakao_client_id

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_ssm_parameter" "oauth_kakao_client_secret" {
  name  = "/ringgo/oauth/kakao/client-secret"
  type  = "SecureString"
  value = var.oauth_kakao_client_secret

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_ssm_parameter" "oauth_naver_client_id" {
  name  = "/ringgo/oauth/naver/client-id"
  type  = "SecureString"
  value = var.oauth_naver_client_id

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_ssm_parameter" "oauth_naver_client_secret" {
  name  = "/ringgo/oauth/naver/client-secret"
  type  = "SecureString"
  value = var.oauth_naver_client_secret

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_ssm_parameter" "oauth_google_client_id" {
  name  = "/ringgo/oauth/google/client-id"
  type  = "SecureString"
  value = var.oauth_google_client_id

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_ssm_parameter" "oauth_google_client_secret" {
  name  = "/ringgo/oauth/google/client-secret"
  type  = "SecureString"
  value = var.oauth_google_client_secret

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# VPC 모듈 사용
module "vpc" {
  source = "../../modules/vpc"

  environment = "dev"
  project_name = "ring-go"
}

# Compute 모듈
module "compute" {
  source = "../../modules/compute"

  project_name        = var.project_name
  environment         = var.environment
  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = module.vpc.public_subnet_ids
  aws_region          = var.aws_region
  database_server_ip  = var.database_server_ip
}
