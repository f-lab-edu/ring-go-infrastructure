variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "ring-go"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "mysql_root_password" {
  description = "MySQL root password"
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "JWT secret key"
  type        = string
  sensitive   = true
}

variable "oauth_kakao_client_id" {
  description = "OAuth Kakao Client ID"
  type        = string
  sensitive   = true
}

variable "oauth_kakao_client_secret" {
  description = "OAuth Kakao Client Secret"
  type        = string
  sensitive   = true
}

variable "oauth_naver_client_id" {
  description = "OAuth Naver Client ID"
  type        = string
  sensitive   = true
}

variable "oauth_naver_client_secret" {
  description = "OAuth Naver Client Secret"
  type        = string
  sensitive   = true
}

variable "oauth_google_client_id" {
  description = "OAuth Google Client ID"
  type        = string
  sensitive   = true
}

variable "oauth_google_client_secret" {
  description = "OAuth Google Client Secret"
  type        = string
  sensitive   = true
}

variable "database_server_ip" {
  description = "Oracle Cloud Database Server Public IP"
  type        = string
}
