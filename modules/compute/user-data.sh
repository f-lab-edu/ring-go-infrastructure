#!/bin/bash

# 로그 파일 설정
LOG_FILE="/var/log/user-data.log"
exec 1>>${LOG_FILE}
exec 2>&1

echo "=== User Data 스크립트 시작: $(date) ==="

# 시스템 업데이트
echo "시스템 업데이트 중..."
yum update -y

# Docker 설치
echo "Docker 설치 중..."
amazon-linux-extras install docker -y
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# Docker Compose 설치
echo "Docker Compose 설치 중..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Nginx 설치
echo "Nginx 설치 중..."
amazon-linux-extras install nginx1 -y

# Nginx 설정 (CORS 및 Swagger 수정 포함)
echo "Nginx 설정 중..."
cat > /etc/nginx/conf.d/ringgo.conf << 'EOF'
server {
    listen 80;
    server_name api-dev.ring-go.kr;

    # 헬스체크
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    # Swagger API docs 응답 수정
    location = /v3/api-docs {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # 응답 압축 해제
        proxy_set_header Accept-Encoding "";
        
        # localhost를 실제 도메인으로 변경
        sub_filter '"url":"http://localhost:8080"' '"url":"https://api-dev.ring-go.kr"';
        sub_filter_types application/json;
        sub_filter_once off;
    }

    # 모든 요청을 Spring Boot로 프록시
    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        
        # 타임아웃 설정
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
        
        # 버퍼 설정
        proxy_buffering off;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
        proxy_busy_buffers_size 8k;
        
        # WebSocket 지원
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # CORS 헤더 설정
        # Preflight 요청 처리
        if ($request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*' always;
            add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS, PATCH' always;
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization' always;
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
        }
        
        # 실제 요청에 대한 CORS 헤더
        add_header 'Access-Control-Allow-Origin' '*' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS, PATCH' always;
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization' always;
        add_header 'Access-Control-Expose-Headers' 'Authorization,Content-Type,X-Total-Count' always;
    }
}
EOF

# Nginx 시작
echo "Nginx 시작 중..."
systemctl start nginx
systemctl enable nginx

# certbot 설치 (SSL 인증서용)
echo "Certbot 설치 중..."
yum install -y certbot python3-certbot-nginx

# Application 디렉토리 생성
echo "애플리케이션 디렉토리 생성 중..."
mkdir -p /home/ec2-user/app
mkdir -p /home/ec2-user/scripts

# Docker Compose 파일 생성
echo "Docker Compose 파일 생성 중..."
cat > /home/ec2-user/app/docker-compose.yml << 'EOF'
version: '3.8'

services:
  app:
    image: h2jinee/ringgo:latest
    container_name: ringgo
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      - SPRING_PROFILES_ACTIVE=dev
      - SPRING_DATASOURCE_URL=jdbc:mysql://${database_server_ip}:3306/ringgo?useSSL=false&allowPublicKeyRetrieval=true
      - SPRING_DATASOURCE_USERNAME=root
      - SPRING_DATASOURCE_PASSWORD=$${mysql_password}
      - SPRING_DATA_REDIS_HOST=${database_server_ip}
      - SPRING_DATA_REDIS_PORT=6379
      - JWT_SECRET=$${jwt_secret}
      - OAUTH_KAKAO_CLIENT_ID=$${oauth_kakao_client_id}
      - OAUTH_KAKAO_CLIENT_SECRET=$${oauth_kakao_client_secret}
      - OAUTH_NAVER_CLIENT_ID=$${oauth_naver_client_id}
      - OAUTH_NAVER_CLIENT_SECRET=$${oauth_naver_client_secret}
      - OAUTH_GOOGLE_CLIENT_ID=$${oauth_google_client_id}
      - OAUTH_GOOGLE_CLIENT_SECRET=$${oauth_google_client_secret}
      - SERVER_BASE_URL=https://api-dev.ring-go.kr
      - API_BASE_URL=https://api-dev.ring-go.kr
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/actuator/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF

# 환경 변수 설정 스크립트 생성
echo "환경 변수 스크립트 생성 중..."
cat > /home/ec2-user/app/setup-env.sh << 'EOF'
#!/bin/bash
# Parameter Store에서 값 가져오기
export mysql_password=$(aws ssm get-parameter --name /ringgo/mysql/root-password --with-decryption --region ${aws_region} --query 'Parameter.Value' --output text)
export jwt_secret=$(aws ssm get-parameter --name /ringgo/jwt/secret --with-decryption --region ${aws_region} --query 'Parameter.Value' --output text)
export oauth_kakao_client_id=$(aws ssm get-parameter --name /ringgo/oauth/kakao/client-id --with-decryption --region ${aws_region} --query 'Parameter.Value' --output text)
export oauth_kakao_client_secret=$(aws ssm get-parameter --name /ringgo/oauth/kakao/client-secret --with-decryption --region ${aws_region} --query 'Parameter.Value' --output text)
export oauth_naver_client_id=$(aws ssm get-parameter --name /ringgo/oauth/naver/client-id --with-decryption --region ${aws_region} --query 'Parameter.Value' --output text)
export oauth_naver_client_secret=$(aws ssm get-parameter --name /ringgo/oauth/naver/client-secret --with-decryption --region ${aws_region} --query 'Parameter.Value' --output text)
export oauth_google_client_id=$(aws ssm get-parameter --name /ringgo/oauth/google/client-id --with-decryption --region ${aws_region} --query 'Parameter.Value' --output text)
export oauth_google_client_secret=$(aws ssm get-parameter --name /ringgo/oauth/google/client-secret --with-decryption --region ${aws_region} --query 'Parameter.Value' --output text)
EOF

chmod +x /home/ec2-user/app/setup-env.sh

# 시작 스크립트 생성
echo "시작 스크립트 생성 중..."
cat > /home/ec2-user/scripts/start-app.sh << 'EOF'
#!/bin/bash
cd /home/ec2-user/app
source ./setup-env.sh
docker-compose pull
docker-compose up -d
EOF

# 재시작 스크립트 생성
echo "재시작 스크립트 생성 중..."
cat > /home/ec2-user/scripts/restart-app.sh << 'EOF'
#!/bin/bash
cd /home/ec2-user/app
source ./setup-env.sh
docker-compose down
docker-compose pull
docker-compose up -d
docker system prune -f
echo "애플리케이션이 재시작되었습니다."
EOF

# 로그 확인 스크립트 생성
echo "로그 확인 스크립트 생성 중..."
cat > /home/ec2-user/scripts/check-logs.sh << 'EOF'
#!/bin/bash
echo "=== Docker 상태 ==="
docker ps -a
echo -e "\n=== 최근 로그 (50줄) ==="
docker logs ringgo --tail 50
echo -e "\n=== Nginx 에러 로그 ==="
sudo tail -20 /var/log/nginx/error.log
EOF

chmod +x /home/ec2-user/scripts/*.sh
chown -R ec2-user:ec2-user /home/ec2-user

# SSL 인증서 발급 스크립트 생성 (수동 실행용)
echo "SSL 스크립트 생성 중..."
cat > /home/ec2-user/setup-ssl.sh << 'EOF'
#!/bin/bash
# 도메인이 준비되면 실행
certbot --nginx -d api-dev.ring-go.kr --non-interactive --agree-tos -m admin@ring-go.kr
EOF

chmod +x /home/ec2-user/setup-ssl.sh

# 애플리케이션 시작
echo "애플리케이션 시작 중..."
cd /home/ec2-user/app
/home/ec2-user/scripts/start-app.sh

echo "=== User Data 스크립트 완료: $(date) ==="
echo "다음 단계:"
echo "1. 도메인이 준비되면: sudo /home/ec2-user/setup-ssl.sh"
echo "2. 로그 확인: docker logs ringgo"
echo "3. nginx 설정 확인: cat /etc/nginx/conf.d/ringgo.conf"
