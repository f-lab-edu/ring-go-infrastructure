#!/bin/bash

echo "🚀 Ring-Go 로컬 테스트 시작"

# 기존 컨테이너 정리
echo "🧹 기존 컨테이너 정리 중..."
docker-compose down -v

# Docker Compose로 환경 구성
echo "📦 Docker Compose로 환경 구성 중..."
docker-compose up -d

# 서비스가 준비될 때까지 대기
echo "⏳ 서비스 준비 대기 중..."
for i in {1..30}; do
    if curl -s http://localhost/actuator/health > /dev/null 2>&1; then
        echo "✅ 서비스 준비 완료!"
        break
    fi
    echo "대기 중... ($i/30)"
    sleep 2
done

# 서비스 상태 확인
echo ""
echo "🔍 서비스 상태 확인"
docker-compose ps

echo ""
echo "🌐 테스트 URL들:"
echo "- 메인: http://localhost"
echo "- Swagger UI: http://localhost/swagger-ui/index.html"
echo "- Health Check: http://localhost/actuator/health"
echo "- API 예시: http://localhost/v1/meeting"

echo ""
echo "🧪 기본 동작 테스트"

echo "1. Health Check"
HEALTH=$(curl -s http://localhost/actuator/health | grep -o '"status":"[^"]*' | cut -d'"' -f4)
echo "   상태: ${HEALTH:-실패}"

echo "2. Swagger UI"
if curl -s http://localhost/swagger-ui/index.html | grep -q "Swagger UI"; then
    echo "   ✅ Swagger UI 로딩 성공"
else
    echo "   ❌ Swagger UI 로딩 실패"
fi

echo "3. 정적 리소스"
CSS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/swagger-ui/swagger-ui.css)
echo "   CSS 파일: HTTP ${CSS_STATUS}"

echo ""
echo "✅ 테스트 환경 준비 완료!"
echo "🌐 브라우저에서 http://localhost/swagger-ui/index.html 접속하여 확인하세요."
echo ""
echo "🛑 테스트 종료: docker-compose down"
echo "📋 로그 확인: docker-compose logs -f [서비스명]"
echo "🔍 디버깅: ./debug.sh"
