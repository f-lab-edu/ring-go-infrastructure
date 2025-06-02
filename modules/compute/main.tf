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
      # 로그 파일 생성 (디버깅용)
      exec > /var/log/user-data.log 2>&1

      echo "=== User Data 스크립트 시작: $(date) ==="

      # 스왑 파일 생성 (메모리 부족 해결)
      echo "스왑 파일 생성 중..."
      dd if=/dev/zero of=/swapfile bs=1M count=1024
      chmod 600 /swapfile
      mkswap /swapfile
      swapon /swapfile
      echo '/swapfile swap swap defaults 0 0' >> /etc/fstab
      echo "✅ 스왑 파일 생성 완료"

      # 기본 패키지 설치
      echo "패키지 업데이트 및 설치 중..."
      yum update -y
      yum install -y docker aws-cli telnet
      systemctl start docker
      systemctl enable docker
      usermod -a -G docker ec2-user

      # Nginx 설치
      echo "Nginx 설치 중..."
      NGINX_INSTALLED=false
      RETRY_COUNT=0
      MAX_RETRIES=3

      while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$NGINX_INSTALLED" = false ]; do
          RETRY_COUNT=$((RETRY_COUNT + 1))
          echo "Nginx 설치 시도 $RETRY_COUNT/$MAX_RETRIES..."

          if amazon-linux-extras install nginx1 -y; then
              echo "✅ Nginx 설치 성공"
              NGINX_INSTALLED=true
          else
              echo "❌ Nginx 설치 실패 (시도 $RETRY_COUNT/$MAX_RETRIES)"
              if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                  echo "30초 후 재시도..."
                  sleep 30
              fi
          fi
      done

      if [ "$NGINX_INSTALLED" = true ]; then
          systemctl start nginx
          systemctl enable nginx
          echo "✅ Nginx 서비스 시작 완료"
      else
          echo "❌ Nginx 설치 최종 실패 - 스크립트 계속 진행"
      fi

      # Docker 설치 완료
      echo "Docker 설치 완료: $(date)"

      # Oracle Cloud DB 연결 테스트
      echo "Oracle Cloud DB 연결 테스트 시작 (${var.database_server_ip}:3306)..."
      DB_REACHABLE=false

      if timeout 30 bash -c "</dev/tcp/${var.database_server_ip}/3306" 2>/dev/null; then
          echo "✅ Oracle Cloud DB 연결 성공"
          DB_REACHABLE=true
      else
          echo "❌ Oracle Cloud DB 연결 실패 (30초 타임아웃)"
          DB_REACHABLE=false
      fi

      # Parameter Store에서 값 가져오기
      export AWS_DEFAULT_REGION=${var.aws_region}
      echo "Parameter Store에서 설정값 가져오는 중..."

      # 함수: Parameter Store에서 안전하게 값 가져오기
      get_parameter() {
          local param_name="$1"
          local value=$(timeout 30 aws ssm get-parameter --name "$param_name" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "FAILED")
          echo "$value"
      }

      MYSQL_PASSWORD=$(get_parameter "/ringgo/mysql/root-password")
      JWT_SECRET=$(get_parameter "/ringgo/jwt/secret")
      KAKAO_CLIENT_ID=$(get_parameter "/ringgo/oauth/kakao/client-id")
      KAKAO_CLIENT_SECRET=$(get_parameter "/ringgo/oauth/kakao/client-secret")
      NAVER_CLIENT_ID=$(get_parameter "/ringgo/oauth/naver/client-id")
      NAVER_CLIENT_SECRET=$(get_parameter "/ringgo/oauth/naver/client-secret")
      GOOGLE_CLIENT_ID=$(get_parameter "/ringgo/oauth/google/client-id")
      GOOGLE_CLIENT_SECRET=$(get_parameter "/ringgo/oauth/google/client-secret")

      # 퍼블릭 IP 가져오기
      echo "퍼블릭 IP 가져오는 중..."
      PUBLIC_IP=$(timeout 10 curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "UNKNOWN")

      echo "=== 설정 확인 ==="
      echo "DB 연결 가능: $DB_REACHABLE"
      echo "MySQL 패스워드: $([ "$MYSQL_PASSWORD" != "FAILED" ] && [ -n "$MYSQL_PASSWORD" ] && echo "OK" || echo "FAILED")"
      echo "JWT Secret: $([ "$JWT_SECRET" != "FAILED" ] && [ -n "$JWT_SECRET" ] && echo "OK" || echo "FAILED")"
      echo "Public IP: $PUBLIC_IP"
      echo "Nginx 설치 상태: $NGINX_INSTALLED"

      # Spring Boot 컨테이너 실행
      if [ "$DB_REACHABLE" = true ] && [ "$MYSQL_PASSWORD" != "FAILED" ] && [ "$JWT_SECRET" != "FAILED" ]; then
          echo "✅ 필수 조건 충족 - Spring Boot 컨테이너 시작"

          # 기존 컨테이너 정리
          if docker ps -aq -f name=ringgo | grep -q .; then
              echo "기존 컨테이너 정리 중..."
              docker stop ringgo 2>/dev/null || true
              docker rm ringgo 2>/dev/null || true
          fi

          # 컨테이너 실행
          if docker run -d --name ringgo \
            --restart unless-stopped \
            --memory=500m \
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
            -e SERVER_BASE_URL=https://api-dev.ring-go.kr \
            -e OAUTH_KAKAO_CLIENT_ID="$KAKAO_CLIENT_ID" \
            -e OAUTH_KAKAO_CLIENT_SECRET="$KAKAO_CLIENT_SECRET" \
            -e OAUTH_NAVER_CLIENT_ID="$NAVER_CLIENT_ID" \
            -e OAUTH_NAVER_CLIENT_SECRET="$NAVER_CLIENT_SECRET" \
            -e OAUTH_GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID" \
            -e OAUTH_GOOGLE_CLIENT_SECRET="$GOOGLE_CLIENT_SECRET" \
            -e JWT_SECRET="$JWT_SECRET" \
            h2jinee/ringgo:latest; then

              echo "✅ Spring Boot 컨테이너 시작 완료: $(date)"

              # 컨테이너 상태 확인
              sleep 10
              if docker ps | grep ringgo > /dev/null; then
                  echo "✅ 컨테이너 정상 실행 중"
              else
                  echo "❌ 컨테이너 실행 실패 - 로그 확인:"
                  docker logs ringgo 2>/dev/null || echo "로그 조회 실패"
              fi
          else
              echo "❌ Docker 컨테이너 시작 실패"
          fi
      fi

      # SSL 인증서 설치 (nginx가 설치된 경우에만)
      if [ "$NGINX_INSTALLED" = true ]; then
          echo "SSL 인증서 설치 시작..."

          # EPEL 저장소 설치
          if amazon-linux-extras install epel -y; then
              echo "✅ EPEL 저장소 설치 성공"

              # certbot 설치
              if yum install -y certbot python2-certbot-nginx; then
                  echo "✅ certbot 설치 성공"

                  # 기본 nginx 설정 생성 (SSL 인증서 발급용)
                  cat > /etc/nginx/conf.d/temp.conf << 'TEMP_EOF'
      server {
          listen 80;
          server_name api-dev.ring-go.kr;

          location /.well-known/acme-challenge/ {
              root /var/www/html;
          }

          location / {
              proxy_pass http://127.0.0.1:8080;
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-Host $host;
          }
      }
      TEMP_EOF

                  # nginx 재시작
                  nginx -t && systemctl restart nginx

                  # 60초 대기 후 SSL 인증서 발급
                  sleep 60
                  mkdir -p /var/www/html

                  echo "SSL 인증서 발급 시도..."
                  if certbot --nginx -d api-dev.ring-go.kr --non-interactive --agree-tos --email wjsgmlwls97@gmail.com --redirect; then
                      echo "✅ SSL 인증서 발급 성공"

                      # API 개발 서버 설정 적용
                      cat > /etc/nginx/conf.d/temp.conf << 'FINAL_EOF'
      # API 개발 서버
      server {
          listen 443 ssl;
          server_name api-dev.ring-go.kr;

          ssl_certificate /etc/letsencrypt/live/api-dev.ring-go.kr/fullchain.pem;
          ssl_certificate_key /etc/letsencrypt/live/api-dev.ring-go.kr/privkey.pem;
          include /etc/letsencrypt/options-ssl-nginx.conf;
          ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

          # 모든 요청을 Spring Boot로 프록시
          location / {
              proxy_pass http://127.0.0.1:8080;
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-Host $host;
              
              # 타임아웃 설정
              proxy_connect_timeout 30s;
              proxy_send_timeout 30s;
              proxy_read_timeout 30s;
              
              # WebSocket 지원 (향후 필요시)
              proxy_http_version 1.1;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection "upgrade";
          }
          
          # 헬스체크용 (로드밸런서에서 사용)
          location /health {
              access_log off;
              return 200 "healthy\\n";
              add_header Content-Type text/plain;
          }
      }

      # HTTP to HTTPS 리다이렉트
      server {
          listen 80;
          server_name api-dev.ring-go.kr;
          
          location /.well-known/acme-challenge/ {
              root /var/www/html;
          }
          
          location / {
              return 301 https://$host$request_uri;
          }
      }
      FINAL_EOF

                      # 설정 재로드
                      nginx -t && systemctl reload nginx
                      echo "✅ 도메인별 설정 완료"
                  else
                      echo "❌ SSL 인증서 발급 실패"
                  fi
              else
                  echo "❌ certbot 설치 실패"
              fi
          else
              echo "❌ EPEL 저장소 설치 실패"
          fi
      else
          echo "⚠️ nginx 미설치로 인해 SSL 설정 스킵"
      fi

      echo "=== User Data 스크립트 완료: $(date) ==="
      echo "로그 파일 위치: /var/log/user-data.log"
      echo "🚀 서버 준비 완료!"
  EOF

  tags = {
    Name = "${var.project_name}-${var.environment}-app-server"
    Type = "application"
  }
}
