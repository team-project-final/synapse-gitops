# W4 후속 — 완료 가능 우선 실행 시퀀싱 Design

> 작성: 2026-06-04 (`/superpowers:brainstorming`). 상위 작업 분해는 `docs/superpowers/plans/2026-06-04-report-followups-kafka-ssl-gateway-prod-prereqs.md`(이하 "후속 플랜")가 권위. 본 문서는 그중 **이번 라운드 스코프(WS3 + ES #114)를 "완료 가능 우선"으로 재배열**한 실행 시퀀싱이다.

## 목표

W4 리포트 후속 중 **외부 의존(ECR 이미지·라이브 클러스터) 없이 코드로 완결되는 작업**을 완료 근접도 순으로 닫는다. 산출은 매 단계 `kubectl kustomize` 렌더 + yamllint + `terraform validate`로 회귀를 막은, main에 머지된 코드.

## 결정 (이번 라운드 확정)

- **D1. 완료 기준 = 코드 머지.** main 머지 + 렌더/lint/validate 통과를 "완료"로 본다. 라이브 검증(E2E·netpol 집행·HPA)은 다음 EKS provision→verify→destroy 윈도로 일괄 이월(후속 플랜 D-B).
- **D2. cross-repo 허용.** 필요 시 `../synapse-*` 앱 레포에서 코드+테스트+PR(각 레포 컨벤션·TDD 준수).
- **D3. 스코프 = WS3(Kafka SSL) + ES #114.** WS1/WS2(gateway/engagement 이미지 릴리스)는 ECR/CI 의존이라 이번 라운드 제외. ES #114는 다른 곳 병행 작업이 없어 본 라운드에서 완결(FS-C2 통합 + 머지).
- **D4. 순서 = 완료 근접도 우선(Approach A).** 거의 끝난 #114를 먼저 닫아 `apps/knowledge-svc/overlays/dev`를 ES 베이스로 확정 → WS3 knowledge overlay 충돌을 구조적으로 회피.

## 비스코프 (이번 라운드 밖)

- 라이브 런타임/집행 검증(EKS 윈도): WS3-D E2E, prod netpol 집행, HPA.
- WS1 gateway non-root 이미지 릴리스, WS2 engagement 이미지 태그 bump(둘 다 ECR 선행).

## 시퀀스

### Phase 0 — ES 검색엔진 정합 #114 완결
완료 근접도 최상 + knowledge overlay 베이스 확정.

1. FS-C2(`6acecf2`, recover-fs-c2-opensearch-tf-removal 브랜치) 통합 — `feat/knowledge-search-elasticsearch`에 `git cherry-pick 6acecf2`. FS-C1과 동일 `infra/aws/dev/*.tf` 파일군이라 충돌 예상 → 수동 해결.
2. `origin/main` 머지로 #114 BEHIND 해소(가이드는 문서라 충돌 무관).
3. 회귀 가드: 전 오버레이 `kubectl kustomize` + yamllint + `terraform validate`(infra/aws/dev).
4. CI(`validate`) 통과 후 #114 머지 → `recover-fs-c2-opensearch-tf-removal` 삭제.

산출: in-cluster ES StatefulSet + `ELASTICSEARCH_URIS` 정합 + 매니지드 OpenSearch terraform 제거가 main에.

### Phase 1 — WS3-A/B 앱 레포 security.protocol 배선 (4 PR, 병렬 가능)
MSK TLS 연결의 코어. 후속 플랜 WS3-A/B 단계가 task-level 권위. 각 레포 TDD, 레포별 1 PR.

- **WS3-A (Spring 3): platform-svc, knowledge-svc, learning-card** — producer/consumer 팩토리에
  `@Value("${spring.kafka.security.protocol:PLAINTEXT}")` 추가 + props에 조건부 `CommonClientConfigs.SECURITY_PROTOCOL_CONFIG` 주입 + `application.yml` 명시 바인딩. 실패 테스트 → 구현 → green → dev PR.
- **WS3-B (Python 1): learning-ai** — `Settings.kafka_security_protocol`(env_prefix `LEARNING_AI_`) 추가 + aiokafka consumer/producer 생성자에 `security_protocol` 전달. 테스트 → PR.

완료 = 각 앱 PR 머지. 새 이미지 빌드(CI/ECR)는 라이브(WS3-C 런타임)의 선행이라 EKS 윈도 이월.

### Phase 2 — WS3-C gitops dev Kafka 활성화 오버레이
`apps/engagement-svc/overlays/dev` 동형 패치를 4개 서비스 dev 오버레이에 추가.

- `apps/{platform-svc,knowledge-svc,learning-card,learning-ai}/overlays/dev/kustomization.yaml` ConfigMap `/data`:
  `KAFKA_ENABLED`(앱 게이트키에 맞춤), `SPRING_KAFKA_SECURITY_PROTOCOL=SSL`(learning-ai는 `LEARNING_AI_KAFKA_SECURITY_PROTOCOL=SSL`), `SCHEMA_REGISTRY_URL=http://schema-registry:8081`.
- knowledge-svc 오버레이는 Phase 0(ES env) 위에 적용 → 충돌 없음.
- 회귀 가드 후 PR(서비스별 또는 묶음). 완료 = 머지. 이미지 정합·런타임은 이월.

### Phase 3 — WS3-E staging/prod authoring (구조만)
dev E2E(이월) 전이라도 staging/prod 구조를 코드화하되 **prod sync는 Manual로 막아둔다**("검증된 서비스만" 원칙).

- `apps/schema-registry/overlays/{staging,prod}/` 신설(dev 복제, ns별 kafka-brokers ConfigMap, SSL 동일).
- 검증 대상 서비스 staging/prod 오버레이에 WS3-C 동형 패치.
- `argocd/applicationset*.yaml`에 schema-registry 등록.
- 전 오버레이 render 회귀 + lint + PR.

### 이월 (EKS 윈도 — 완료 범위 밖)
- WS3-D: 4서비스 TLS MSK(9094) bootstrap·consumer group join·Avro produce/consume 무에러, EVENT_FLOW 체인 E2E(런북 `docs/runbooks/engagement-kafka-enablement.md` 확장).
- WS1/WS2 이미지 릴리스 + 라이브.
- prod netpol 집행·HPA(런북 `docs/runbooks/prod-prereqs-netpol-metrics.md`).

## 회귀 가드 (매 Phase 공통)

```bash
for d in apps/*/overlays/*; do kubectl kustomize "$d" >/dev/null && echo "OK $d"; done
# yamllint: CRLF 정규화 후
tr -d '\r' < <file> > /tmp/lf.yaml && python -m yamllint -c .yamllint /tmp/lf.yaml
# terraform(Phase 0): cd infra/aws/dev && terraform fmt -check && terraform validate
```

## 리스크 & 완화

| 리스크 | 완화 |
|---|---|
| Phase 0 cherry-pick 충돌(FS-C1/C2 동일 tf 파일군) | 수동 해결 후 `terraform validate` + render로 검증 |
| WS3-C를 이미지(WS3-A/B) 전 머지 → dev auto-sync면 일시 PLAINTEXT 폴백 | dev sync 정책 확인. image 정합까지 sync 보류 또는 이미지 빌드 후 활성화 |
| cross-repo 4 PR 컨벤션·테스트 패턴 상이 | 레포별 TDD, 후속 플랜의 앵커/패턴 참조 |
| #114 머지가 knowledge-svc를 ES로 바꾼 직후 WS3 knowledge 작업 | Phase 0를 선행해 베이스 확정(D4) |

## 산출물 매핑

| Phase | 레포 | 파일 |
|---|---|---|
| 0 | gitops | `infra/aws/dev/*.tf`, knowledge-svc 오버레이(ES env) — #114 머지 |
| 1 | app ×4 | `*/KafkaConfig.java`·`KafkaProducerConfig.java`/`KafkaConsumerConfig.java`, `learning-ai/app/core/config.py`·`app/kafka/*.py`, 각 `application.yml` |
| 2 | gitops | `apps/{platform-svc,knowledge-svc,learning-card,learning-ai}/overlays/dev/kustomization.yaml` |
| 3 | gitops | `apps/schema-registry/overlays/{staging,prod}/`, `apps/*/overlays/{staging,prod}/kustomization.yaml`, `argocd/applicationset*.yaml` |
