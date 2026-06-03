# 작업 리포트 — dev EKS 실검증 + local-k8s 온보딩 가이드 (2026-06-03)

> 하루 작업 요약. dev EKS를 실제로 프로비저닝해 머지된 하드닝을 검증하고,
> 발견 이슈를 수정(머지)한 뒤 teardown했다. 이어서 local-k8s 구조를 보여주는
> 단일 HTML 온보딩 가이드를 설계·구현했다.

## 1. 한눈에

| 영역 | 결과 |
|------|------|
| dev EKS 프로비저닝 | terraform 60리소스 + `bring-up.sh` 부트스트랩 → **검증 완료 → destroy(과금 중단)** |
| 하드닝 검증 | #100 non-root(UID 101)✅ · schema-registry MSK TLS✅ · dev 앱 Healthy✅ |
| 머지된 수정 | gitops **#107**(postgres 16.9 + lock) · **#108**(Kafka SSL) |
| 앱 레포 수정 | platform-svc **#48**(`application-staging.yml` 신설, base=dev, 리뷰 대기) |
| 신규 산출물 | `docs/local-k8s-guide.html` — 인터랙티브 온보딩 가이드(이 PR) |

---

## 2. dev EKS 실프로비저닝 & 검증

### 2.1 절차
- `infra/aws/dev` terraform `apply` → **60리소스**(EKS 1.30 4노드 · MSK 2broker · RDS · OpenSearch · Redis · bastion · IRSA 등).
- `scripts/bring-up.sh --from eks-auth` → SSM 터널(`scripts/lib/eks-tunnel.sh`) → ArgoCD · ESO · OIDC-fix · kafka-config(ConfigMap) · ApplicationSet 적용.
- 접근: EKS 엔드포인트가 **private 전용**이라 bastion 경유 SSM 포트포워딩 터널로 kubectl 도달.
- 로컬 도구 갭 해소: `helm`, `session-manager-plugin` 신규 설치(winget).

### 2.2 하드닝 검증 결과 (memory A 체크리스트)
- **#100 non-root securityContext** ✅ — platform/knowledge/learning-card가 실 ECR 이미지에서 `uid=101(app)`로 기동(A 최대 리스크 "UID≠101 시 CreateContainerConfigError" 통과).
- **schema-registry ↔ MSK(TLS)** ✅ — SSL 적용 후 `_schemas` 토픽 리더 선출·오프셋 read 성공, 1/1 Ready, `/subjects` 200.
- **dev 앱** ✅ — platform/engagement/knowledge/learning-ai/learning-card 모두 1/1, ArgoCD Synced/Healthy(gateway 제외).
- ➖ #101 NetworkPolicy·#100 HPA는 prod 전용 → dev 미대상. prod 적용 시 **VPC CNI netpol 컨트롤러 활성화 + metrics-server 설치** 선행 필요.

### 2.3 발견 이슈 & 수정
1. **postgres 16.6 미제공**(ap-northeast-2) → `CreateDBInstance` 실패 → `engine_version 16.9` + `apply_immediately=true`. `.terraform.lock.hcl`도 추적(다른 PC `terraform init` 일관성). → **gitops #107 머지**.
2. **MSK가 `client_broker=TLS` 전용(9094)**인데 schema-registry/engagement는 PLAINTEXT 가정 → 연결 실패. SR 오버레이를 `KAFKASTORE_BOOTSTRAP_SERVERS=configmap valueFrom` + `SECURITY_PROTOCOL=SSL`, engagement에 `SPRING_KAFKA_SECURITY_PROTOCOL=SSL`. MSK 인증서는 Amazon CA → 기본 truststore로 충분. → **gitops #108 머지**.
3. **사이징 부족** — tfvars 2노드/db.t3.micro는 dev+staging 동시 수용에 부족(pod 슬롯 17×2 만석 · micro 연결 고갈로 platform-svc CrashLoop). **4노드/db.t3.medium**으로 교정.
4. **staging platform-svc** — `application-staging.yml` 부재로 staging 프로파일에 datasource 미정의 → CrashLoop. platform-svc 레포에 신설(`${DB_URL}` 등). → **platform-svc #48**(base=신규 dev 브랜치, 리뷰 대기; 런타임 반영은 이미지 재빌드 후).

### 2.4 teardown
검증 목표 달성 후 `terraform destroy` → **60리소스 삭제, 과금 중단**. S3 state/DynamoDB lock은 보존(재프로비저닝 시 재사용). `bring-up.sh --from eks-auth`/`terraform destroy` 절차가 실인프라에서 검증됨.

### 2.5 남은 후속
- **gateway**: dev 오버레이가 `synapse/gateway`(슬래시) 참조하나 실 ECR은 `synapse-gateway`(하이픈) + 태그 latest/1.0.0(B2 non-root 이전) → 이미지 경로 + 재빌드 필요.
- **engagement Kafka 런타임**: 배포 이미지 `1.0.0`이 Kafka 배선(#21) 이전 → KAFKA_ENABLED=true여도 미초기화. 이미지 재빌드 후 검증.
- **staging/prod 오버레이**에 동일 Kafka SSL 적용(동일 TLS MSK).
- prod 적용 시 VPC CNI netpol 컨트롤러 + metrics-server 선행.

---

## 3. local-k8s 온보딩 가이드 (이 PR의 핵심 산출물)

### 3.1 개요
`docs/local-k8s-guide.html` — synapse `local-k8s` 스택의 **서비스간 연결 · Kafka 구독/소비 ·
연결 주소 · 요청/응답 API**를 보여주는 **자체완결 단일 HTML**(외부 의존성 0, 더블클릭으로 오프라인 동작).
설계/계획: `docs/superpowers/{specs,plans}/2026-06-03-local-k8s-guide*`.

### 3.2 구성 (애니메이션 + 탐색, 계층적)
- **인터랙티브 아키텍처 맵**(SVG, 3단 티어): gateway / 서비스 6 / 인프라 6. 엣지 색 구분(REST·Kafka·Store) + 레이어 토글 + hover/클릭 하이라이트.
- **드릴다운 패널**: 노드/엣지 클릭 시 주소·역할·REST 엔드포인트·pub/sub 토픽·DTO·Avro 필드.
- **이벤트 흐름 애니메이션**: 시나리오(사용자 가입 / 노트→카드 생성 / 복습 완료) 입자 재생 + 재생/일시정지·단계 이동·속도 컨트롤.
- **종합 레퍼런스(검색)**: REST 엔드포인트 85 · Kafka 토픽 5(Avro 필드) · 연결 디렉터리 · DTO 카탈로그 65(샘플 JSON 펼침). 맵↔레퍼런스 연동.

### 3.3 정확성 (실 코드/계약 기반)
- 데이터는 매니페스트(`local-k8s/apps/*`, `infra/kafka-topics-job.yaml`)·앱 컨트롤러·`synapse-shared` Avro 스키마에서 전수 수집.
- **D-001 반영**: `learning.ai.cards-generated-v1`은 deprecated(발행자 없음) — 카드 등록은 learning-ai→learning-card **HTTP(card_client.py)**. 가이드도 이 흐름으로 표기(출처: `synapse-shared/docs/guides/EVENT_FLOW_MATRIX.md`).
- 파일 내 `SELFTEST`(참조 무결성) + 실제 브라우저 end-to-end 검증 통과.

### 3.4 유지보수
스냅샷 성격(코드 시점 기준). 아키텍처 변경 시 파일 내 단일 `SYSTEM` 데이터 객체만 갱신하면 맵·애니메이션·레퍼런스가 함께 갱신된다.

---

## 4. 비용 메모
dev EKS 스택은 가동 중 시간당 ~$0.5(월 ~$300±). 검증 후 즉시 destroy해 과금을 중단했다.
재현은 `terraform apply` + `bring-up.sh --from eks-auth`, 종료는 `terraform destroy`.
