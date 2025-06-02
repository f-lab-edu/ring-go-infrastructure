# Ring-Go 로컬 테스트 환경

## 🎯 목적
개발 서버 환경을 로컬에서 테스트하기 위한 Docker Compose 환경입니다.

## 🏗 구조
- **단일 도메인**: `dev.ring-go.kr` (로컬에서는 localhost로 테스트)
- **Swagger UI**: `/swagger-ui/index.html`
- **API**: `/v1/*`
- **Health Check**: `/actuator/health`

## 🚀 실행 방법

### 1. 테스트 환경 시작
```bash
cd local-test
chmod +x test.sh
./test.sh
```

### 2. 접속 URL
- **메인**: http://localhost
- **Swagger UI**: http://localhost/swagger-ui/index.html
- **Health Check**: http://localhost/actuator/health
- **Spring Boot 직접**: http://localhost:8080 (디버깅용)

### 3. 디버깅
```bash
./debug.sh  # 상태 확인 및 로그 보기
```

### 4. 종료
```bash
docker-compose down -v
```

## 📋 체크리스트
- [ ] Swagger UI 정상 접속
- [ ] API 엔드포인트 응답 확인
- [ ] 정적 리소스 로딩 확인 (CSS, JS)
- [ ] HTTPS 리다이렉트 테스트 (운영환경)

## 🔧 문제 해결
- 포트 충돌 시: 기존 서비스 중지 또는 docker-compose.yml에서 포트 변경
- 메모리 부족: Docker Desktop 메모리 할당 증가
