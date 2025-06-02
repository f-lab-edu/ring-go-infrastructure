#!/bin/bash

echo "🔍 Ring-Go 디버깅 도구"

echo ""
echo "=== 1. 컨테이너 상태 ==="
docker-compose ps

echo ""
echo "=== 2. 서비스 Health Check ==="
echo -n "Spring Boot Health: "
curl -s http://localhost/actuator/health 2>/dev/null | jq -r '.status' 2>/dev/null || echo "접속 실패"

echo -n "Nginx Health: "
curl -s http://localhost/health 2>/dev/null || echo "접속 실패"

echo ""
echo "=== 3. Swagger UI 접근성 ==="
echo -n "Swagger UI HTML: "
curl -s -o /dev/null -w "%{http_code}" http://localhost/swagger-ui/index.html

echo -n "Swagger UI CSS: "
curl -s -o /dev/null -w "%{http_code}" http://localhost/swagger-ui/swagger-ui.css

echo -n "API Docs JSON: "
curl -s -o /dev/null -w "%{http_code}" http://localhost/v3/api-docs

echo ""
echo "=== 4. 네트워크 연결 상태 ==="
docker-compose exec nginx ping -c 1 app > /dev/null 2>&1 && echo "✅ Nginx → App 연결 정상" || echo "❌ Nginx → App 연결 실패"
docker-compose exec app ping -c 1 db > /dev/null 2>&1 && echo "✅ App → DB 연결 정상" || echo "❌ App → DB 연결 실패"
docker-compose exec app ping -c 1 redis > /dev/null 2>&1 && echo "✅ App → Redis 연결 정상" || echo "❌ App → Redis 연결 실패"

echo ""
echo "=== 5. 리소스 사용량 ==="
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep -E "ringgo|CONTAINER"

echo ""
echo "=== 6. 최근 로그 (각 서비스 5줄) ==="
echo "--- Nginx ---"
docker-compose logs --tail=5 nginx 2>/dev/null | grep -v "Attaching"

echo "--- Spring Boot ---"
docker-compose logs --tail=5 app 2>/dev/null | grep -v "Attaching"

echo ""
echo "🛠️ 추가 디버깅 명령어:"
echo "- 전체 로그: docker-compose logs -f"
echo "- 특정 서비스: docker-compose logs -f [nginx|app|db|redis]"
echo "- 컨테이너 접속: docker-compose exec [서비스명] sh"
echo "- Nginx 설정 확인: docker-compose exec nginx nginx -T"
