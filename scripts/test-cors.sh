#!/bin/bash

# CORS 테스트 스크립트
# 사용법: ./test-cors.sh [도메인]

DOMAIN=${1:-"https://api-dev.ring-go.kr"}
ORIGIN="https://dev.ring-go.kr"

echo "========================================="
echo "CORS 테스트 시작"
echo "API Domain: $DOMAIN"
echo "Origin: $ORIGIN"
echo "========================================="

# 색상 코드
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. OPTIONS 요청 테스트 (Preflight)
echo -e "\n${YELLOW}1. OPTIONS 요청 테스트 (Preflight)${NC}"
echo "curl -X OPTIONS $DOMAIN/api/v1/health"

RESPONSE=$(curl -s -X OPTIONS "$DOMAIN/api/v1/health" \
  -H "Origin: $ORIGIN" \
  -H "Access-Control-Request-Method: GET" \
  -H "Access-Control-Request-Headers: Authorization, Content-Type" \
  -w "\n%{http_code}" \
  -D -)

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
HEADERS=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" == "204" ]] || [[ "$HTTP_CODE" == "200" ]]; then
    echo -e "${GREEN}✓ OPTIONS 요청 성공 (HTTP $HTTP_CODE)${NC}"
else
    echo -e "${RED}✗ OPTIONS 요청 실패 (HTTP $HTTP_CODE)${NC}"
fi

# CORS 헤더 확인
echo -e "\n${YELLOW}CORS 헤더 확인:${NC}"
echo "$HEADERS" | grep -i "access-control-" | while read -r line; do
    if [[ -n "$line" ]]; then
        echo -e "${GREEN}✓ $line${NC}"
    fi
done

# 2. GET 요청 테스트
echo -e "\n${YELLOW}2. GET 요청 테스트${NC}"
echo "curl -X GET $DOMAIN/api/v1/health"

RESPONSE=$(curl -s -X GET "$DOMAIN/api/v1/health" \
  -H "Origin: $ORIGIN" \
  -H "Content-Type: application/json" \
  -w "\n%{http_code}" \
  -D -)

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
HEADERS=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" == "200" ]]; then
    echo -e "${GREEN}✓ GET 요청 성공 (HTTP $HTTP_CODE)${NC}"
else
    echo -e "${RED}✗ GET 요청 실패 (HTTP $HTTP_CODE)${NC}"
fi

# 3. 인증이 필요한 요청 테스트
echo -e "\n${YELLOW}3. 인증이 필요한 요청 테스트${NC}"
echo "curl -X GET $DOMAIN/api/v1/users/me"

RESPONSE=$(curl -s -X GET "$DOMAIN/api/v1/users/me" \
  -H "Origin: $ORIGIN" \
  -H "Authorization: Bearer dummy-token" \
  -H "Content-Type: application/json" \
  -w "\n%{http_code}" \
  -D -)

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)

if [[ "$HTTP_CODE" == "401" ]] || [[ "$HTTP_CODE" == "403" ]]; then
    echo -e "${GREEN}✓ 인증 확인 동작 (HTTP $HTTP_CODE)${NC}"
else
    echo -e "${YELLOW}! 예상과 다른 응답 (HTTP $HTTP_CODE)${NC}"
fi

# 4. 다른 Origin에서 요청 테스트
echo -e "\n${YELLOW}4. 다른 Origin에서 요청 테스트${NC}"
echo "curl -X GET $DOMAIN/api/v1/health (Origin: https://malicious-site.com)"

RESPONSE=$(curl -s -X GET "$DOMAIN/api/v1/health" \
  -H "Origin: https://malicious-site.com" \
  -H "Content-Type: application/json" \
  -w "\n%{http_code}" \
  -D -)

HEADERS=$(echo "$RESPONSE" | head -n -1)
ALLOW_ORIGIN=$(echo "$HEADERS" | grep -i "access-control-allow-origin:" | cut -d' ' -f2-)

if [[ "$ALLOW_ORIGIN" == "*" ]] || [[ "$ALLOW_ORIGIN" == "https://malicious-site.com" ]]; then
    echo -e "${YELLOW}⚠ 모든 Origin 허용됨 (개발 환경에서는 정상)${NC}"
else
    echo -e "${GREEN}✓ Origin 제한 동작중${NC}"
fi

# 5. 요약
echo -e "\n${YELLOW}========================================="
echo "테스트 완료"
echo "=========================================${NC}"

# CORS 체크리스트
echo -e "\n${YELLOW}CORS 체크리스트:${NC}"
if echo "$HEADERS" | grep -qi "access-control-allow-origin"; then
    echo -e "${GREEN}✓ Access-Control-Allow-Origin 헤더 존재${NC}"
else
    echo -e "${RED}✗ Access-Control-Allow-Origin 헤더 없음${NC}"
fi

if echo "$HEADERS" | grep -qi "access-control-allow-methods"; then
    echo -e "${GREEN}✓ Access-Control-Allow-Methods 헤더 존재${NC}"
else
    echo -e "${RED}✗ Access-Control-Allow-Methods 헤더 없음${NC}"
fi

if echo "$HEADERS" | grep -qi "access-control-allow-headers"; then
    echo -e "${GREEN}✓ Access-Control-Allow-Headers 헤더 존재${NC}"
else
    echo -e "${RED}✗ Access-Control-Allow-Headers 헤더 없음${NC}"
fi

echo -e "\n${YELLOW}추가 테스트가 필요한 경우:${NC}"
echo "- 브라우저 개발자 도구에서 실제 요청 확인"
echo "- Postman이나 Insomnia로 상세 테스트"
echo "- 프론트엔드 애플리케이션에서 실제 API 호출 테스트"
