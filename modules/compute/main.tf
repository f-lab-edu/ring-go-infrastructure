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

  # HTTP 접속 허용 (포트 80)
  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Spring Boot 포트 (8080)
  ingress {
    from_port = 8080
    to_port   = 8080
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

  user_data = <<-EOF
    #!/bin/bash
    set -e  # 심각한 오류 발생 시에만 중단

    # 로그 파일 생성 (디버깅용)
    exec > >(tee /var/log/user-data.log)
    exec 2>&1

    echo "=== User Data 스크립트 시작: $(date) ==="

    # 기본 패키지 설치
    echo "패키지 업데이트 및 설치 중..."
    yum update -y
    yum install -y docker aws-cli telnet
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ec2-user

    echo "Docker 설치 완료: $(date)"

    # Oracle Cloud DB 연결 테스트 (30초 타임아웃)
    echo "Oracle Cloud DB 연결 테스트 시작 (${var.database_server_ip}:3306)..."
    DB_REACHABLE=false

    if timeout 30 bash -c "</dev/tcp/${var.database_server_ip}/3306" 2>/dev/null; then
        echo "✅ Oracle Cloud DB 연결 성공"
        DB_REACHABLE=true
    else
        echo "❌ Oracle Cloud DB 연결 실패 (30초 타임아웃)"
        DB_REACHABLE=false
    fi

    # Parameter Store에서 값 가져오기 (각각 30초 타임아웃)
    export AWS_DEFAULT_REGION=${var.aws_region}
    echo "Parameter Store에서 설정값 가져오는 중..."

    MYSQL_PASSWORD=""
    JWT_SECRET=""
    KAKAO_CLIENT_ID=""
    KAKAO_CLIENT_SECRET=""
    NAVER_CLIENT_ID=""
    NAVER_CLIENT_SECRET=""
    GOOGLE_CLIENT_ID=""
    GOOGLE_CLIENT_SECRET=""

    # Parameter Store 접근 (타임아웃 포함)
    echo "MySQL 패스워드 가져오는 중..."
    MYSQL_PASSWORD=$(timeout 30 aws ssm get-parameter --name "/ringgo/mysql/root-password" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "FAILED")

    echo "JWT Secret 가져오는 중..."
    JWT_SECRET=$(timeout 30 aws ssm get-parameter --name "/ringgo/jwt/secret" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "FAILED")

    echo "OAuth 설정 가져오는 중..."
    KAKAO_CLIENT_ID=$(timeout 30 aws ssm get-parameter --name "/ringgo/oauth/kakao/client-id" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "FAILED")
    KAKAO_CLIENT_SECRET=$(timeout 30 aws ssm get-parameter --name "/ringgo/oauth/kakao/client-secret" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "FAILED")
    NAVER_CLIENT_ID=$(timeout 30 aws ssm get-parameter --name "/ringgo/oauth/naver/client-id" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "FAILED")
    NAVER_CLIENT_SECRET=$(timeout 30 aws ssm get-parameter --name "/ringgo/oauth/naver/client-secret" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "FAILED")
    GOOGLE_CLIENT_ID=$(timeout 30 aws ssm get-parameter --name "/ringgo/oauth/google/client-id" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "FAILED")
    GOOGLE_CLIENT_SECRET=$(timeout 30 aws ssm get-parameter --name "/ringgo/oauth/google/client-secret" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "FAILED")

    # 퍼블릭 IP 가져오기 (10초 타임아웃)
    echo "퍼블릭 IP 가져오는 중..."
    PUBLIC_IP=$(timeout 10 curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "UNKNOWN")

    echo "=== 설정 확인 ==="
    echo "DB 연결 가능: $DB_REACHABLE"
    echo "MySQL 패스워드: $([ "$MYSQL_PASSWORD" != "FAILED" ] && echo "OK" || echo "FAILED")"
    echo "JWT Secret: $([ "$JWT_SECRET" != "FAILED" ] && echo "OK" || echo "FAILED")"
    echo "Public IP: $PUBLIC_IP"

    # Spring Boot 컨테이너 실행 (조건부)
    if [ "$DB_REACHABLE" = true ] && [ "$MYSQL_PASSWORD" != "FAILED" ] && [ "$JWT_SECRET" != "FAILED" ]; then
        echo "✅ 모든 조건 충족 - Spring Boot 컨테이너 시작"

        docker run -d --name ringgo \
          --restart unless-stopped \
          --memory=400m \
          --cpus=0.8 \
          -p 8080:8080 \
          -e SPRING_PROFILES_ACTIVE=dev \
          -e SPRING_DATASOURCE_URL=jdbc:mysql://${var.database_server_ip}:3306/ringgo \
          -e SPRING_DATASOURCE_USERNAME=root \
          -e SPRING_DATASOURCE_PASSWORD="$MYSQL_PASSWORD" \
          -e SPRING_DATA_REDIS_HOST=${var.database_server_ip} \
          -e SPRING_DATA_REDIS_PORT=6379 \
          -e SPRING_KAFKA_BOOTSTRAP_SERVERS=localhost:9092 \
          -e SPRING_KAFKA_CONSUMER_GROUP_ID=ringgo-group \
          -e SERVER_BASE_URL=http://$PUBLIC_IP:8080 \
          -e OAUTH_KAKAO_CLIENT_ID="$KAKAO_CLIENT_ID" \
          -e OAUTH_KAKAO_CLIENT_SECRET="$KAKAO_CLIENT_SECRET" \
          -e OAUTH_NAVER_CLIENT_ID="$NAVER_CLIENT_ID" \
          -e OAUTH_NAVER_CLIENT_SECRET="$NAVER_CLIENT_SECRET" \
          -e OAUTH_GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID" \
          -e OAUTH_GOOGLE_CLIENT_SECRET="$GOOGLE_CLIENT_SECRET" \
          -e JWT_SECRET="$JWT_SECRET" \
          h2jinee/ringgo:latest

        echo "✅ Spring Boot 컨테이너 시작 완료: $(date)"

        # 컨테이너 상태 확인
        sleep 10
        docker ps | grep ringgo && echo "✅ 컨테이너 정상 실행 중" || echo "❌ 컨테이너 실행 실패"

    else
        echo "❌ 조건 미충족 - Spring Boot 시작하지 않음"
        echo "   - DB 연결: $DB_REACHABLE"
        echo "   - MySQL PW: $([ "$MYSQL_PASSWORD" != "FAILED" ] && echo "OK" || echo "FAILED")"
        echo "   - JWT Secret: $([ "$JWT_SECRET" != "FAILED" ] && echo "OK" || echo "FAILED")"
        echo "⚠️  SSH 접속은 여전히 가능합니다."
    fi

    echo "=== User Data 스크립트 완료: $(date) ==="
    echo "로그 파일 위치: /var/log/user-data.log"
  EOF

  tags = {
    Name = "${var.project_name}-${var.environment}-app-server"
    Type = "application"
  }
}
