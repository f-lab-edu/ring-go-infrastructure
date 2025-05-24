# ring-go-infrastructure
링고(Ring-go) 인프라 - 하이브리드 클라우드 구성

## 아키텍처
- **AWS**: Spring Boot 애플리케이션 서버 (t2.micro)
- **Oracle Cloud**: MySQL + Redis 데이터베이스 서버 (E2.1.Micro)

## 배포 순서

### 1. Oracle Cloud 데이터베이스 서버 배포
```bash
cd environments/oci-dev
terraform init
terraform plan
terraform apply
```

### 2. Oracle Cloud IP 확인
```bash
terraform output database_server_public_ip
```

### 3. AWS 환경 변수 설정
`environments/dev/terraform.tfvars` 파일에서 다음 값을 업데이트:
```hcl
database_server_ip = "ORACLE_CLOUD_PUBLIC_IP_HERE"
```

### 4. AWS 애플리케이션 서버 배포
```bash
cd environments/dev
terraform init
terraform plan
terraform apply
```

## 포트 구성
- **AWS**: 8080 (Spring Boot), 22 (SSH)
- **Oracle Cloud**: 3306 (MySQL), 6379 (Redis), 22 (SSH)

## 주의사항
- Oracle Cloud를 먼저 배포한 후 AWS 배포를 진행해주세요
- 두 클라우드 간 네트워크 연결 상태를 확인해주세요
- 보안 그룹/Security List에서 필요한 포트가 열려있는지 확인해주세요
