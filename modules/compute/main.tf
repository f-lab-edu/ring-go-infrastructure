# IAM 역할 생성 (Parameter Store 접근용)
resource "aws_iam_role" "ec2_parameter_store_role" {
  name = "${var.project_name}-${var.environment}-ec2-parameter-store-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-ec2-role"
  }
}

# Parameter Store 접근 정책
resource "aws_iam_role_policy" "parameter_store_policy" {
  name = "${var.project_name}-${var.environment}-parameter-store-policy"
  role = aws_iam_role.ec2_parameter_store_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/ringgo/*"
      }
    ]
  })
}

# IAM 인스턴스 프로파일
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-${var.environment}-ec2-profile"
  role = aws_iam_role.ec2_parameter_store_role.name

  tags = {
    Name = "${var.project_name}-${var.environment}-ec2-profile"
  }
}

# 보안 그룹 생성
resource "aws_security_group" "app_server" {
  name_prefix = "${var.project_name}-${var.environment}-app-"
  vpc_id      = var.vpc_id

  # HTTPS 접속 허용 (포트 443)
  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP 접속 허용 (포트 80)
  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH 접속 허용 (포트 22)
  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Spring Boot 직접 접속 허용 (포트 8080)
  ingress {
    from_port = 8080
    to_port   = 8080
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 모든 아웃바운드 허용
  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-app-sg"
  }
}

# 최신 Amazon Linux 2 AMI 찾기
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners = ["amazon"]

  filter {
    name = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# EC2 서버 생성
resource "aws_instance" "app_server" {
  ami                  = data.aws_ami.amazon_linux.id
  instance_type        = "t2.micro"
  vpc_security_group_ids = [aws_security_group.app_server.id]
  subnet_id            = var.public_subnet_ids[0]
  key_name             = "ring-go-keypair"
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  user_data = templatefile("${path.module}/user-data.sh", {
    database_server_ip = var.database_server_ip
    aws_region         = var.aws_region
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-app-server"
    Type = "application"
  }
}
