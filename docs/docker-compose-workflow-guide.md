# WORKFLOW Guide — W1 Step 2: Docker Compose 4-서비스 구성

> **담당**: `@team-lead` (김민구)
> **영역**: Gateway / 인프라 / 아키텍처
> **Duration**: 1일
> **기준 문서**: `WORKFLOW_team-lead_W1.md`, `TASK_team-lead.md`, `PRD_W1`

---

## 1. 먼저 이해할 것

이 작업은 팀 전체 개발/배포 흐름을 지탱하는 운영 기반을 다루는 작업이다. 팀원이 4개 백엔드 서비스와 learning-ai 컨테이너를 로컬에서 한 번에 실행하여 통합 개발을 시작할 수 있는 환경을 제공한다.

### Done When

- `docker compose up` → 전체 서비스 Health OK (< 2분)
- Schema Registry 접속 가능 (http://localhost:8081)
- PostgreSQL + Redis + Kafka + ES 접속 가능
- 팀원 온보딩 문서에 실행 방법 기재

### 범위 제한

| In Scope | Out of Scope |
|----------|-------------|
| docker-compose.yml (4-서비스 + infra) | Production Docker 이미지 최적화 |
| .env.example 업데이트 | K8s Helm Chart (별도 관리) |
| Schema Registry 컨테이너 | 모니터링 대시보드 |
| Health check 설정 | Gateway 라우팅 (W2) |

---

## 2. 서비스 구성도

```
┌─────────────────────────────────────────────────────────────┐
│                    synapse-net (bridge)                       │
│                                                              │
│  ┌──────────────────── Infrastructure ───────────────────┐   │
│  │  postgres:5432  redis:6379  elasticsearch:9200        │   │
│  │  zookeeper:2181 → kafka:9092 → schema-registry:8081  │   │
│  └───────────────────────────────────────────────────────┘   │
│                           │                                   │
│                    depends_on (healthy)                        │
│                           │                                   │
│  ┌──────────────────── Applications ─────────────────────┐   │
│  │  platform-svc:8080    engagement-svc:8081             │   │
│  │  knowledge-svc:8082   learning-card:8083              │   │
│  │  learning-ai:8000                                      │   │
│  └───────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘

Host Port Mapping:
  5432 → postgres        8082 → engagement-svc
  6379 → redis           8083 → knowledge-svc
  9092 → kafka           8084 → learning-card
  8081 → schema-registry 8000 → learning-ai
  9200 → elasticsearch   8080 → platform-svc
```

---

## 3. 의존성 체인

```
zookeeper ─(healthy)→ kafka ─(healthy)→ schema-registry
postgres  ─(healthy)→ platform-svc, engagement-svc, knowledge-svc, learning-card
redis     ─(healthy)→ platform-svc, engagement-svc, learning-card
kafka     ─(healthy)→ ALL app services
elasticsearch ─(healthy)→ knowledge-svc, learning-ai
```

---

## 4. 실행 방법

### 최초 설정

```bash
# 1. 환경 변수 파일 생성
cp .env.example .env

# 2. 필요한 경우 .env 편집 (API 키 등)
# 로컬 개발 시 대부분 기본값으로 동작

# 3. 전체 실행
docker compose up -d

# 4. 상태 확인
docker compose ps
docker compose logs -f  # 로그 추적
```

### 인프라만 실행 (서비스 개발 시)

```bash
# 인프라 컨테이너만 실행 (앱은 IDE에서 직접 실행)
docker compose up -d postgres redis kafka zookeeper schema-registry elasticsearch
```

### 특정 서비스만 실행

```bash
# 예: platform-svc만 실행 (+ 의존 인프라 자동 포함)
docker compose up -d platform-svc
```

### 종료 및 정리

```bash
# 종료 (데이터 유지)
docker compose down

# 종료 + 볼륨 삭제 (완전 초기화)
docker compose down -v
```

---

## 5. Health Check 기준

| 서비스 | Health Check | 간격 | 타임아웃 | 재시도 |
|--------|-------------|------|---------|--------|
| postgres | `pg_isready` | 5s | 3s | 10 |
| redis | `redis-cli ping` | 5s | 3s | 10 |
| zookeeper | `echo ruok` | 10s | 5s | 5 |
| kafka | `kafka-broker-api-versions` | 10s | 10s | 10 |
| schema-registry | `curl /subjects` | 10s | 5s | 10 |
| elasticsearch | `curl /_cluster/health` | 10s | 5s | 15 |
| app services (Spring) | `curl /actuator/health` | 10s | 5s | 10 |
| learning-ai (FastAPI) | `curl /health` | 10s | 5s | 10 |

---

## 6. 메모리 설계 (8GB 제한)

| 서비스 | 메모리 제한 | 비고 |
|--------|-----------|------|
| postgres | 512M | pgvector 포함 |
| redis | 192M | maxmemory 128MB + overhead |
| zookeeper | 384M | |
| kafka | 768M | 단일 브로커 |
| schema-registry | 384M | |
| elasticsearch | 512M | ES_JAVA_OPTS -Xms256m -Xmx256m |
| platform-svc | 512M | |
| engagement-svc | 512M | |
| knowledge-svc | 512M | |
| learning-card | 512M | |
| learning-ai | 512M | |
| **합계** | **~5.3GB** | 8GB 시스템에서 여유 확보 |

---

## 7. 네트워크 및 보안

### 네트워크 격리

- 모든 서비스는 `synapse-net` 단일 bridge 네트워크에서 통신
- 외부 포트 바인딩은 개발 필수 포트만 노출
- 서비스 간 통신은 컨테이너 이름으로 DNS 해결

### 시크릿 관리

- `.env` 파일은 `.gitignore`에 포함 (커밋 금지)
- `.env.example`에는 플레이스홀더만 기재
- 로컬 개발용 기본값은 docker-compose.yml 내 `${VAR:-default}` 패턴 사용

---

## 8. Smoke Test 명령

```bash
# PostgreSQL
docker compose exec postgres psql -U synapse -c "SELECT version();"

# Redis
docker compose exec redis redis-cli -a redis_local ping

# Kafka
docker compose exec kafka kafka-topics --bootstrap-server localhost:9092 --list

# Schema Registry
curl http://localhost:8081/subjects

# Elasticsearch
curl http://localhost:9200/_cluster/health?pretty

# App Services
curl http://localhost:8080/actuator/health  # platform-svc
curl http://localhost:8082/actuator/health  # engagement-svc
curl http://localhost:8083/actuator/health  # knowledge-svc
curl http://localhost:8084/actuator/health  # learning-card
curl http://localhost:8000/health           # learning-ai
```

---

## 9. 트러블슈팅

### Kafka 시작 실패

```bash
# Zookeeper가 healthy인지 확인
docker compose logs zookeeper
# 볼륨 초기화 후 재시작
docker compose down -v && docker compose up -d
```

### Elasticsearch OOM

```bash
# host에서 vm.max_map_count 설정 (Linux/WSL)
sudo sysctl -w vm.max_map_count=262144
```

### Apple Silicon에서 Confluent 이미지 느림

Confluent 이미지(kafka, zookeeper, schema-registry)는 `platform: linux/amd64` Rosetta 에뮬레이션으로 동작. 초기 시작이 느릴 수 있으나 정상.

---

## 10. 진행 체크리스트

- [ ] TASK Step Goal / Done When / Scope 확인
- [ ] 4-서비스 + infra 컨테이너 목록 확정
- [ ] Health check 기준 정의
- [ ] 컨테이너 간 네트워크 격리 정책 확인
- [ ] 외부 포트 바인딩 최소화
- [ ] .env 파일 .gitignore 확인
- [ ] docker-compose.yml 서비스 구성 작성
- [ ] depends_on 의존관계 정의
- [ ] DB 비밀번호 환경변수 관리 확인
- [ ] Redis AUTH 설정 확인
- [ ] `docker compose up` → 전체 Health OK (< 2분)
- [ ] Schema Registry 접속 확인 (http://localhost:8081)
- [ ] PostgreSQL + Redis + Kafka + ES 접속 확인
- [ ] README 실행 방법 문서화
