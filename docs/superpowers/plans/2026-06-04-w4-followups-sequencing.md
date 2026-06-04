# W4 후속 완료 가능 우선 실행 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** W4 후속 중 외부 의존(ECR·라이브 클러스터) 없이 코드로 완결되는 WS3(Kafka SSL) + ES #114를 완료 근접도 순(Approach A)으로 main에 머지한다.

**Architecture:** Phase 0(#114 완결)로 knowledge overlay 베이스를 ES로 확정 → Phase 1(앱 4 PR로 security.protocol 배선) → Phase 2(gitops dev Kafka 활성화) → Phase 3(staging/prod authoring). 완료=코드 머지 + 렌더/lint/validate. 라이브 검증은 EKS 윈도 이월.

**Tech Stack:** Kustomize, ArgoCD ApplicationSet, AWS MSK(TLS-only 9094), Terraform(`infra/aws/dev`), Spring Kafka(`KafkaConfig`), aiokafka(learning-ai), yamllint, JUnit5, pytest.

**상위 문서:** 스펙 `docs/superpowers/specs/2026-06-04-w4-followups-sequencing-design.md`. WS3 task 패턴 권위 `docs/superpowers/plans/2026-06-04-report-followups-kafka-ssl-gateway-prod-prereqs.md`(이하 "후속 플랜").

**환경:** `C:/workspace/team-project-final/synapse-gitops`. PowerShell/Bash 혼용(Windows). yamllint은 CRLF→LF 정규화 후 실행.

---

## File Structure

| Phase | 레포 | 파일 (책임) |
|---|---|---|
| 0 | gitops | `infra/aws/dev/{main,outputs,variables,velero,vpc}.tf`(OpenSearch terraform 제거), `infra/aws/dev/opensearch.tf`(삭제) — #114 머지 |
| 1 | platform-svc | `.../global/kafka/KafkaProducerConfig.java`·`KafkaConsumerConfig.java`(security.protocol 주입), `src/main/resources/application.yml`(명시 바인딩), 테스트 |
| 1 | knowledge-svc | `.../global/config/KafkaConfig.java`, `application.yml`, 테스트 |
| 1 | learning-card | `.../config/KafkaConfig.java`, `application.yml`, 테스트 |
| 1 | learning-ai | `app/core/config.py`(Settings 필드), `app/kafka/consumer.py`·`notification_producer.py`(aiokafka 전달), 테스트 |
| 2 | gitops | `apps/{platform-svc,knowledge-svc,learning-card,learning-ai}/overlays/dev/kustomization.yaml` |
| 3 | gitops | `apps/schema-registry/overlays/{staging,prod}/`, `apps/*/overlays/{staging,prod}/kustomization.yaml`, `argocd/applicationset*.yaml` |

---

## Phase 0 — ES 검색엔진 정합 #114 완결

> 베이스: `feat/knowledge-search-elasticsearch`(현재 0573daa=FS-C1). FS-C2(`6acecf2`)는 `recover-fs-c2-opensearch-tf-removal` 브랜치에 보존. 완료 후 main이 ES 정합본 + 매니지드 OpenSearch terraform 제거를 가진다.

### Task 0.1: FS-C2 cherry-pick 통합

**Files:** Modify `infra/aws/dev/{main,outputs,variables,velero,vpc}.tf`, Delete `infra/aws/dev/opensearch.tf` (cherry-pick 적용분)

- [ ] **Step 1: ES 브랜치로 전환 + 최신 확인**

```bash
cd C:/workspace/team-project-final/synapse-gitops
git switch feat/knowledge-search-elasticsearch
git log --oneline -1            # 0573daa (FS-C1) 확인
```
Expected: HEAD=0573daa, 워킹트리 clean.

- [ ] **Step 2: FS-C2 cherry-pick**

```bash
git cherry-pick 6acecf2
```
Expected: 충돌 가능(FS-C1과 동일 `infra/aws/dev/*.tf`). 충돌 시 Step 3.

- [ ] **Step 3: 충돌 해결 (충돌 시에만)**

`git status`로 충돌 파일 확인. 의도: FS-C2는 매니지드 OpenSearch(`opensearch.tf`·관련 SG/outputs/var) 제거. FS-C1(인클러스터 ES)과 겹치는 부분은 **양쪽 의도 보존**(인클러스터 ES 유지 + 매니지드 OpenSearch 제거). 각 파일 해결 후:
```bash
git add infra/aws/dev/
git cherry-pick --continue
```
Expected: cherry-pick 완료, `opensearch.tf` 삭제 반영.

- [ ] **Step 4: terraform 검증**

```bash
cd infra/aws/dev && terraform fmt -check && terraform init -backend=false -input=false && terraform validate
```
Expected: `Success! The configuration is valid.` (OpenSearch 참조 잔존 시 validate 에러 → 잔여 참조 제거).

- [ ] **Step 5: 커밋 (cherry-pick가 자동 커밋 안 했을 때만)**

cherry-pick는 보통 자동 커밋. 추가 수정이 있었으면:
```bash
cd C:/workspace/team-project-final/synapse-gitops
git add infra/aws/dev/ && git commit --amend --no-edit
```

### Task 0.2: main 동기화 + 회귀 가드

**Files:** 없음(머지/검증)

- [ ] **Step 1: origin/main 머지로 BEHIND 해소**

```bash
git fetch origin main
git merge origin/main
```
Expected: 가이드(docs/local-k8s-guide.html)는 문서라 충돌 무관. 충돌 시 인프라 파일만 주의해서 해결.

- [ ] **Step 2: 전 오버레이 렌더**

```bash
for d in apps/*/overlays/*; do kubectl kustomize "$d" >/dev/null && echo "OK $d" || echo "FAIL $d"; done
```
Expected: 모든 줄 `OK`. `FAIL`이면 해당 오버레이 수정.

- [ ] **Step 3: yamllint (CRLF 정규화)**

```bash
for f in $(git diff --name-only origin/main -- '*.yaml' '*.yml'); do tr -d '\r' < "$f" > /tmp/lf.yaml && python -m yamllint -c .yamllint /tmp/lf.yaml || echo "LINT FAIL $f"; done
```
Expected: 출력 없음(clean).

- [ ] **Step 4: 푸시**

```bash
git push origin feat/knowledge-search-elasticsearch
```

### Task 0.3: #114 머지 + 정리

**Files:** 없음

- [ ] **Step 1: CI 통과 대기**

```bash
gh pr checks 114 --watch --interval 5
```
Expected: `validate` pass, `diff-comment` pass.

- [ ] **Step 2: mergeStateStatus 확인 후 머지**

```bash
gh pr view 114 --json mergeStateStatus,mergeable
gh pr merge 114 --merge --delete-branch
```
Expected: BEHIND면 `gh pr update-branch 114` 후 재시도. CLEAN이면 머지 성공.

- [ ] **Step 3: recover 브랜치 삭제 (FS-C2 통합 확인 후)**

```bash
git fetch origin main && git switch main && git pull --ff-only
test -f infra/aws/dev/opensearch.tf && echo "WARN: opensearch.tf 잔존 — 삭제 안 됨" || echo "OK: FS-C2 반영됨"
git branch -D recover-fs-c2-opensearch-tf-removal
```
Expected: `OK: FS-C2 반영됨` 후 브랜치 삭제. WARN이면 삭제 보류하고 조사.

---

## Phase 1 — WS3-A/B 앱 레포 security.protocol 배선 (4 PR, 병렬 가능)

> 각 레포 별도 브랜치→dev PR. TDD. 코드 패턴은 후속 플랜 WS3-A/B와 동일. 아래는 레포별 정확 경로 + 실착수 시 팩토리 앵커 확인 step 포함.

### Task 1.1: platform-svc security.protocol (Spring)

**Files (synapse-platform-svc):**
- Modify: `src/main/java/.../global/kafka/KafkaProducerConfig.java`, `.../KafkaConsumerConfig.java`
- Modify: `src/main/resources/application.yml`
- Test: 해당 config 테스트 디렉터리(아래 Step 1에서 패턴 확인)

- [ ] **Step 1: 레포 전환 + 팩토리 앵커 확인**

```bash
cd C:/workspace/team-project-final/synapse-platform-svc
git switch -c feat/kafka-security-protocol
grep -rn 'ProducerFactory\|ConsumerFactory\|props.put\|DefaultKafkaProducerFactory' src/main/java/ | grep -i kafka
ls src/test/java/**/kafka/ 2>/dev/null || find src/test -iname '*kafka*'
```
Expected: producer/consumer 팩토리 props 구성 위치 + 기존 kafka 테스트 패턴.

- [ ] **Step 2: 실패 테스트 작성**

securityProtocol=SSL 주입 시 factory config map에 `security.protocol=SSL` 포함을 단언. 기존 테스트 컨벤션(JUnit5 + @SpringBootTest 또는 단위)에 맞춤. 예(단위):
```java
@Test
void producerFactory_includesSecurityProtocol_whenSsl() {
    var cfg = new KafkaProducerConfig(/* bootstrap */ "b:9094", /* schemaRegistry */ "http://sr:8081", /* securityProtocol */ "SSL");
    Map<String, Object> props = cfg.producerConfigs();
    assertThat(props).containsEntry(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, "SSL");
}
```
(생성자 시그니처는 Step 1에서 본 실제 구조에 맞춰 조정.)

- [ ] **Step 3: 테스트 실패 확인**

Run: `./gradlew test --tests '*KafkaProducerConfig*'`
Expected: FAIL (security.protocol 미포함).

- [ ] **Step 4: 구현 — @Value + 조건부 props 주입**

producer·consumer 팩토리 양쪽에:
```java
@Value("${spring.kafka.security.protocol:PLAINTEXT}")
private String securityProtocol;
// 팩토리 props 구성부에:
if (!"PLAINTEXT".equalsIgnoreCase(securityProtocol)) {
    props.put(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, securityProtocol);
}
```
(MSK 인증서=Amazon Trust → JDK 기본 truststore 충분, truststore 설정 불요.)

- [ ] **Step 5: application.yml 명시 바인딩**

```yaml
spring:
  kafka:
    security:
      protocol: ${SPRING_KAFKA_SECURITY_PROTOCOL:PLAINTEXT}
```

- [ ] **Step 6: 테스트 green**

Run: `./gradlew test --tests '*Kafka*Config*'`
Expected: PASS.

- [ ] **Step 7: 커밋 + dev PR**

```bash
git add -A
git commit -m "feat(kafka): security.protocol 배선 (SSL 주입 시 factory에 반영, WS3-A)"
git push -u origin feat/kafka-security-protocol
gh pr create --repo team-project-final/synapse-platform-svc --base main --head feat/kafka-security-protocol \
  --title "feat(kafka): security.protocol 배선 (WS3-A)" \
  --body "MSK TLS-only(9094) 대비. KafkaConfig가 SPRING_KAFKA_SECURITY_PROTOCOL=SSL를 factory props에 반영. 기존 PLAINTEXT 기본 유지."
```

### Task 1.2: knowledge-svc security.protocol (Spring)

**Files (synapse-knowledge-svc):** Modify `src/main/java/.../global/config/KafkaConfig.java`, `application.yml`. Test: 동일 패턴.

- [ ] **Step 1: 앵커 확인** — `cd ../synapse-knowledge-svc && git switch -c feat/kafka-security-protocol && grep -rn 'props.put\|ProducerFactory\|ConsumerFactory' src/main/java/.../config/KafkaConfig.java`
- [ ] **Step 2~6:** Task 1.1 Step 2~6과 동일 코드 패턴(`@Value` + 조건부 `SECURITY_PROTOCOL_CONFIG` + application.yml). KafkaConfig 단일 파일에 producer+consumer 팩토리 모두 처리. 테스트 명령 `./gradlew test --tests '*KafkaConfig*'`.
- [ ] **Step 7: 커밋 + dev PR** (메시지 WS3-A 동일).

> ⚠️ knowledge-svc는 Phase 0(ES 정합)와 같은 레포지만 다른 파일(KafkaConfig vs search). main 최신(#114 머지본)에서 브랜치를 따 충돌 회피.

### Task 1.3: learning-card security.protocol (Spring)

**Files (synapse-learning-svc/learning-card):** Modify `src/main/java/com/synapse/learning/config/KafkaConfig.java`, `application.yml`. Test 동일.

- [ ] **Step 1: 앵커 확인** — `cd ../synapse-learning-svc/learning-card && git switch -c feat/kafka-security-protocol && grep -rn 'props.put\|ProducerFactory\|ConsumerFactory' src/main/java/com/synapse/learning/config/KafkaConfig.java`
- [ ] **Step 2~6:** Task 1.1과 동일 패턴(producer+consumer 모두). `./gradlew test --tests '*KafkaConfig*'`.
- [ ] **Step 7: 커밋 + dev PR.**

### Task 1.4: learning-ai security_protocol (Python/aiokafka)

**Files (synapse-learning-svc/learning-ai):**
- Modify: `app/core/config.py`(Settings), `app/kafka/consumer.py`, `app/kafka/notification_producer.py`
- Test: `tests/` (Step 1에서 패턴 확인)

- [ ] **Step 1: 레포 전환 + 패턴 확인**

```bash
cd C:/workspace/team-project-final/synapse-learning-svc/learning-ai
git switch -c feat/kafka-security-protocol
grep -n 'kafka_bootstrap_servers\|AIOKafkaConsumer\|AIOKafkaProducer\|env_prefix' app/core/config.py app/kafka/*.py
ls tests/ 2>/dev/null
```
Expected: Settings 필드 정의부 + aiokafka 생성자 호출부.

- [ ] **Step 2: 실패 테스트 작성**

```python
def test_settings_reads_kafka_security_protocol(monkeypatch):
    monkeypatch.setenv("LEARNING_AI_KAFKA_SECURITY_PROTOCOL", "SSL")
    from app.core.config import Settings
    assert Settings().kafka_security_protocol == "SSL"
```

- [ ] **Step 3: 테스트 실패 확인**

Run: `pytest tests/ -k security_protocol -v`
Expected: FAIL (필드 부재 → AttributeError 또는 default 불일치).

- [ ] **Step 4: Settings 필드 추가** (`app/core/config.py`)

```python
kafka_security_protocol: str = "PLAINTEXT"
```
(env_prefix `LEARNING_AI_` 적용되어 `LEARNING_AI_KAFKA_SECURITY_PROTOCOL` 바인딩.)

- [ ] **Step 5: aiokafka 생성자에 전달** (`app/kafka/consumer.py`, `notification_producer.py`)

```python
AIOKafkaConsumer(..., bootstrap_servers=settings.kafka_bootstrap_servers,
                 security_protocol=settings.kafka_security_protocol)
# producer도 동일 키워드 추가
```
(SSL이면 aiokafka 기본 ssl context = 시스템 CA, Amazon Trust 포함.)

- [ ] **Step 6: 테스트 green**

Run: `pytest tests/ -k security_protocol -v`
Expected: PASS.

- [ ] **Step 7: 커밋 + dev PR**

```bash
git add -A
git commit -m "feat(kafka): LEARNING_AI_KAFKA_SECURITY_PROTOCOL → aiokafka security_protocol (WS3-B)"
git push -u origin feat/kafka-security-protocol
gh pr create --repo team-project-final/synapse-learning-svc --base main --head feat/kafka-security-protocol \
  --title "feat(kafka): learning-ai security_protocol (WS3-B)" \
  --body "MSK TLS-only 대비. Settings.kafka_security_protocol(env_prefix) → aiokafka consumer/producer 전달."
```

---

## Phase 2 — WS3-C gitops dev Kafka 활성화

> 베이스: main(#114 머지본). 브랜치 `feat/ws3c-dev-kafka-enable`. 참조 동형: `apps/engagement-svc/overlays/dev/kustomization.yaml`.

### Task 2.1: 4개 서비스 dev 오버레이 패치

**Files:** Modify `apps/{platform-svc,knowledge-svc,learning-card,learning-ai}/overlays/dev/kustomization.yaml`

- [ ] **Step 1: 브랜치 + engagement 기준 패턴 확인**

```bash
cd C:/workspace/team-project-final/synapse-gitops
git switch main && git pull --ff-only && git switch -c feat/ws3c-dev-kafka-enable
sed -n '/KAFKA_ENABLED/,/SCHEMA_REGISTRY_URL/p' apps/engagement-svc/overlays/dev/kustomization.yaml
```
Expected: engagement dev의 ConfigMap 패치 형식(literals 또는 patch).

- [ ] **Step 2: platform/knowledge/learning-card 패치 추가**

각 `overlays/dev/kustomization.yaml`의 ConfigMap `/data`(engagement 동형)에:
```yaml
      KAFKA_ENABLED: "true"
      SPRING_KAFKA_SECURITY_PROTOCOL: SSL
      SCHEMA_REGISTRY_URL: http://schema-registry:8081
```
(앱 게이트 키가 다르면 Step 1에서 본 engagement 키명에 맞춤.)

- [ ] **Step 3: learning-ai 패치 추가** (prefix 키)

```yaml
      LEARNING_AI_KAFKA_ENABLED: "true"
      LEARNING_AI_KAFKA_SECURITY_PROTOCOL: SSL
      SCHEMA_REGISTRY_URL: http://schema-registry:8081
```
(learning-ai 게이트/스키마 키는 `apps/learning-ai/overlays/dev` 기존 env 컨벤션 확인 후 정합.)

- [ ] **Step 4: 렌더 + lint**

```bash
for d in apps/platform-svc apps/knowledge-svc apps/learning-card apps/learning-ai; do kubectl kustomize "$d/overlays/dev" >/dev/null && echo "OK $d"; done
for f in apps/{platform-svc,knowledge-svc,learning-card,learning-ai}/overlays/dev/kustomization.yaml; do tr -d '\r' < "$f" > /tmp/lf.yaml && python -m yamllint -c .yamllint /tmp/lf.yaml || echo "LINT FAIL $f"; done
```
Expected: `OK` ×4, lint 출력 없음.

- [ ] **Step 5: 커밋 + PR**

```bash
git add apps/{platform-svc,knowledge-svc,learning-card,learning-ai}/overlays/dev/kustomization.yaml
git commit -m "feat(gitops): dev 4서비스 Kafka 활성화 + SSL env (engagement 동형, WS3-C)"
git push -u origin feat/ws3c-dev-kafka-enable
gh pr create --base main --head feat/ws3c-dev-kafka-enable \
  --title "feat(gitops): dev Kafka SSL 활성화 4서비스 (WS3-C)" \
  --body "WS3-A/B 배선 머지 후 dev 오버레이에 KAFKA_ENABLED+SECURITY_PROTOCOL=SSL+SCHEMA_REGISTRY_URL. 런타임(이미지 정합)·E2E는 EKS 윈도 이월(D-B)."
```
> ⚠️ 머지 전 확인: dev ArgoCD auto-sync 정책. auto-sync면 WS3-A/B 이미지 빌드 전 활성화 시 일시 PLAINTEXT 폴백 가능 → sync 보류 또는 이미지 정합 후 머지.

---

## Phase 3 — WS3-E staging/prod authoring (구조만, prod sync Manual)

> 베이스: main(WS3-C 머지본). 브랜치 `feat/ws3e-staging-prod-authoring`. dev E2E 미완이라 **authoring만**, prod sync는 Manual 유지.

### Task 3.1: schema-registry staging/prod 오버레이 신설

**Files:** Create `apps/schema-registry/overlays/{staging,prod}/kustomization.yaml`(+필요 patch)

- [ ] **Step 1: dev 오버레이 구조 확인**

```bash
ls apps/schema-registry/overlays/dev/
cat apps/schema-registry/overlays/dev/kustomization.yaml
```
Expected: dev 오버레이 파일 구성(namespace, kafka-brokers 참조, SSL env).

- [ ] **Step 2: staging 오버레이 생성** — dev 복제 후 namespace `synapse-staging`, ns별 `kafka-brokers` ConfigMap 참조로 치환. (prod도 동일하게 `synapse-prod`.)

- [ ] **Step 3: 렌더**

```bash
kubectl kustomize apps/schema-registry/overlays/staging >/dev/null && echo OK-staging
kubectl kustomize apps/schema-registry/overlays/prod >/dev/null && echo OK-prod
```
Expected: `OK-staging`, `OK-prod`.

### Task 3.2: 서비스 staging/prod 오버레이 + applicationset 등록

**Files:** Modify `apps/{platform-svc,knowledge-svc,learning-card,learning-ai}/overlays/{staging,prod}/kustomization.yaml`, `argocd/applicationset*.yaml`

- [ ] **Step 1: 각 서비스 staging/prod에 WS3-C 동형 패치** (Phase 2 Step 2/3 동일 env, ns만 staging/prod).
- [ ] **Step 2: applicationset에 schema-registry staging/prod 등록**

```bash
grep -n 'schema-registry\|elements:\|generators:' argocd/applicationset*.yaml
```
dev 등록 패턴에 맞춰 staging/prod element 추가. prod는 `syncPolicy` Manual(자동 sync 비활성) 유지 확인.

- [ ] **Step 3: 전 오버레이 렌더 회귀 + lint**

```bash
for d in apps/*/overlays/*; do kubectl kustomize "$d" >/dev/null && echo "OK $d" || echo "FAIL $d"; done
for f in $(git diff --name-only main -- '*.yaml' '*.yml'); do tr -d '\r' < "$f" > /tmp/lf.yaml && python -m yamllint -c .yamllint /tmp/lf.yaml || echo "LINT FAIL $f"; done
```
Expected: 모두 OK, lint clean.

- [ ] **Step 4: 커밋 + PR**

```bash
git add -A
git commit -m "feat(gitops): WS3 staging/prod authoring — schema-registry 오버레이 + 서비스 SSL env + applicationset (prod sync Manual, WS3-E)"
git push -u origin feat/ws3e-staging-prod-authoring
gh pr create --base main --head feat/ws3e-staging-prod-authoring \
  --title "feat(gitops): WS3 staging/prod authoring (WS3-E)" \
  --body "검증된 서비스 staging/prod 구조 코드화. prod ApplicationSet은 Manual sync 유지(dev E2E 후 활성화). 라이브는 EKS 윈도."
```

---

## 이월 (EKS 윈도 — 본 플랜 범위 밖, 체크리스트만)

- [ ] WS3-D: 4서비스 TLS MSK(9094) bootstrap·group join·Avro produce/consume 무에러 + EVENT_FLOW 체인 E2E (`docs/runbooks/engagement-kafka-enablement.md` 확장).
- [ ] WS3-C 런타임: WS3-A/B 새 이미지 ECR 도착 후 dev 오버레이 이미지 태그 정합 + 파드 로그 SSL bootstrap 확인.
- [ ] WS1/WS2 이미지 릴리스(별도 라운드).
- [ ] prod netpol 집행·HPA (`docs/runbooks/prod-prereqs-netpol-metrics.md`).

---

## Self-Review

**Spec coverage:** D1(완료=머지)→각 Phase "완료=머지", 라이브 이월 명시 ✓. D2(cross-repo)→Phase 1 4 앱 레포 PR ✓. D3(스코프 WS3+#114, WS1/WS2 제외)→Phase 0~3 = #114+WS3, WS1/WS2 이월 ✓. D4(Approach A 순서)→Phase 0 선행으로 knowledge overlay 충돌 회피 ✓. 회귀 가드(kustomize+yamllint+terraform validate) 매 Phase ✓. 리스크(cherry-pick 충돌·auto-sync 폴백)→Task 0.1 Step 3, Phase 2 ⚠️ 노트 ✓.

**Placeholder scan:** 코드 step은 실제 스니펫(@Value+SECURITY_PROTOCOL_CONFIG, Settings 필드, aiokafka 키워드, kustomize env) 포함. 레포별 "앵커 확인" step은 placeholder가 아니라 실값 탐색 명령(후속 플랜 관례 동일). `<bootstrap>` 등 테스트 시그니처 토큰은 Step 1 탐색 결과로 확정.

**Type/이름 일관성:** env 이름 `SPRING_KAFKA_SECURITY_PROTOCOL`(Spring)/`LEARNING_AI_KAFKA_SECURITY_PROTOCOL`(Python), config 키 `CommonClientConfigs.SECURITY_PROTOCOL_CONFIG`, namespace `synapse-{dev,staging,prod}` 전 Phase 일관.
