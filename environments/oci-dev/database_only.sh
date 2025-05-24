#!/bin/bash
apt-get update
apt-get install -y docker.io
systemctl start docker
systemctl enable docker
usermod -aG docker ubuntu

# MySQL 5.7 컨테이너 (메모리 최적화 및 UTF8MB4 설정)
docker run -d --name mysql \
  --restart unless-stopped \
  -m 250m \
  -e MYSQL_ROOT_PASSWORD=${mysql_password} \
  -e MYSQL_DATABASE=ringgo \
  -e MYSQL_ROOT_HOST=% \
  -p 3306:3306 \
  mysql:5.7 \
  --character-set-server=utf8mb4 \
  --collation-server=utf8mb4_unicode_ci \
  --innodb-buffer-pool-size=32M \
  --innodb-log-file-size=16M \
  --max-connections=30 \
  --skip-performance-schema

# Redis 컨테이너 (메모리 제한)
docker run -d --name redis \
  --restart unless-stopped \
  -m 100m \
  -p 6379:6379 \
  redis:latest --maxmemory 80mb --maxmemory-policy allkeys-lru
