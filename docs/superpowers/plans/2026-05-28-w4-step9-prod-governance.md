# W4 Step 9 — prod 거버넌스 + 첫 배포 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** dev/staging과 동일한 GitOps 파이프라인 위에 `synapse-prod` 네임스페이스를 논리 분리로 얹고, ArgoCD Manual Sync + RBAC 권한 분리로 prod 승인 게이트를 증명한다 (FR-GO-401~404).

**Architecture:** 별도 prod 인프라 없이 공유 dev 데이터스토어를 **DB명(`synapse_prod`)·Redis index(1)·시크릿 경로(`synapse/prod/*`)** 로 논리 분리한다. prod Application은 `automated` sync 정책 없이 OutOfSync 대기 → `gitops-admin` 계정만 `role:prod-deployer`로 수동 sync. 일반 계정은 `policy.default: role:readonly`로 거부.

**Tech Stack:** Kustomize 5.4.3, ArgoCD (ApplicationSet/AppProject/RBAC ConfigMap), External Secrets Operator, kubeconform, yamllint.

---

## 검증 도구 (이 플랜의 "테스트")

이 플랜은 매니페스트 작업이라 단위테스트 대신 **렌더 검증**이 테스트 역할을 한다. CI(`.github/workflows/validate-manifests.yml`)와 동일하게:

```bash
# 단일 overlay 렌더 (실패 시 비정상 종료)
kustomize build apps/<svc>/overlays/prod

# 스키마 검증
kustomize build apps/<svc>/overlays/prod | kubeconform -strict -ignore-missing-schemas -summary -output text

# YAML 린트 (전체)
yamllint -c .yamllint apps/ argocd/
```

> **PowerShell 주의(Windows 로컬)**: `kustomize build ... | Select-String <pattern>` 로 grep 대체. CI는 Linux라 동일 동작.

---

## File Structure

| 파일 | 책임 | 작업 |
|---|---|---|
| `apps/platform-svc/overlays/prod/kustomization.yaml` | platform-svc prod overlay (Redis/Stripe 포함) | **수정**(REPLACE_ME 제거 + 논리분리) |
| `apps/engagement-svc/overlays/prod/kustomization.yaml` | engagement-svc prod overlay | **신규 작성**(현재 replicas만) |
| `apps/knowledge-svc/overlays/prod/kustomization.yaml` | knowledge-svc prod overlay (OpenSearch) | **신규 작성** |
| `apps/learning-card/overlays/prod/kustomization.yaml` | learning-card prod overlay | **신규 작성** |
| `apps/learning-ai/overlays/prod/kustomization.yaml` | learning-ai prod overlay (Python) | **신규 작성** |
| `argocd/projects.yaml` | AppProject — 기존 `synapse` + 신규 `synapse-prod` | **수정**(append) |
| `argocd/applicationset-prod.yaml` | prod ApplicationSet (manual sync, image-updater 없음) | **신규** |
| `argocd/bootstrap/rbac-cm.yaml` | RBAC — `role:prod-deployer` 추가 | **수정** |
| `argocd/bootstrap/argocd-cm.yaml` | 로컬 계정 `gitops-admin` 정의 | **신규** |
| `argocd/README.md` | prod 환경/계정 문서화 | **수정** |

> **비용**: Task 1~8 = 비용 0 준비(매니페스트만). Task 9 = prod 라이브 사이클(과금). 라이브 사이클은 Step 10 검증과 batching하고 종료 시 `terraform destroy` (핸드오프 §7).

---

## Task 1: platform-svc prod overlay 논리 분리로 확정

`platform-svc`는 유일하게 풀 ConfigMap 패치가 스캐폴드돼 있으나 `REPLACE_ME_*` 호스트(별도 prod 인프라 가정) + `DATABASE_NAME=synapse`(dev와 동일, 논리분리 안 됨) 상태다. 공유 dev 데이터스토어 + 논리분리 키로 확정한다.

**Files:**
- Modify: `apps/platform-svc/overlays/prod/kustomization.yaml`

- [ ] **Step 1: 현재 (미분리) 상태 확인 — 베이스라인**

Run:
```bash
kustomize build apps/platform-svc/overlays/prod | grep -E "REPLACE_ME|DATABASE_NAME|synapse/dev"
```
Expected: `REPLACE_ME_*` 호스트와 `DATABASE_NAME: synapse`, `synapse/dev/platform-svc/*` remoteRef가 출력됨(=아직 dev 공유·미분리).

- [ ] **Step 2: overlay 전체를 논리분리 버전으로 교체**

`apps/platform-svc/overlays/prod/kustomization.yaml` 전체를 아래로 교체:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: synapse-prod

# prod = 공유 dev 데이터스토어 + 논리 분리(DB명 synapse_prod / Redis index 1 / 시크릿 synapse/prod/*).
# 별도 prod 인프라 없음(W4 핵심은 거버넌스 증명). cf. specs/2026-05-27-w4-prod-design.md §3
patches:
  - target:
      kind: Deployment
      name: platform-svc
    patch: |
      - op: replace
        path: /spec/replicas
        value: 3
  - target:
      kind: ConfigMap
      name: platform-svc-config
    patch: |
      - op: replace
        path: /data/LOG_LEVEL
        value: "INFO"
      - op: replace
        path: /data/SPRING_PROFILES_ACTIVE
        value: "prod"
      - op: add
        path: /data/DATABASE_HOST
        value: "synapse-dev-postgres.c7emuq20mhyy.ap-northeast-2.rds.amazonaws.com"
      - op: add
        path: /data/DATABASE_PORT
        value: "5432"
      - op: add
        path: /data/DATABASE_NAME
        value: "synapse_prod"
      - op: add
        path: /data/DB_URL
        value: "jdbc:postgresql://synapse-dev-postgres.c7emuq20mhyy.ap-northeast-2.rds.amazonaws.com:5432/synapse_prod"
      - op: add
        path: /data/DB_USERNAME
        value: "synapse_admin"
      # 앱은 spring.data.redis.* 만 읽음 → relaxed-binding 키. dev=index 0, prod=index 1로 논리 분리.
      - op: add
        path: /data/SPRING_DATA_REDIS_HOST
        value: "master.synapse-dev-redis.v6lpdh.apn2.cache.amazonaws.com"
      - op: add
        path: /data/SPRING_DATA_REDIS_PORT
        value: "6379"
      - op: add
        path: /data/SPRING_DATA_REDIS_SSL_ENABLED
        value: "true"
      - op: add
        path: /data/SPRING_DATA_REDIS_DATABASE
        value: "1"
      - op: add
        path: /data/KAFKA_BROKERS
        value: "b-1.synapsedevkafka.dchj3l.c2.kafka.ap-northeast-2.amazonaws.com:9094,b-2.synapsedevkafka.dchj3l.c2.kafka.ap-northeast-2.amazonaws.com:9094"
      # ⚠️ prod Stripe price ID는 라이브 전 실제 prod price로 치환 필요(아래 placeholder는 렌더 통과용).
      - op: add
        path: /data/STRIPE_PRO_PRICE_ID
        value: "price_prod_pro_placeholder"
      - op: add
        path: /data/STRIPE_TEAM_PRICE_ID
        value: "price_prod_team_placeholder"
      - op: add
        path: /data/STRIPE_ENTERPRISE_PRICE_ID
        value: "price_prod_enterprise_placeholder"
  - target:
      kind: ExternalSecret
      name: platform-svc-external-secret
    patch: |
      - op: replace
        path: /spec/secretStoreRef/name
        value: aws-secrets-manager
      - op: replace
        path: /spec/data/0/remoteRef/key
        value: synapse/prod/platform-svc/db-password
      - op: replace
        path: /spec/data/1/remoteRef/key
        value: synapse/prod/platform-svc/redis-auth-token
      - op: replace
        path: /spec/data/2/remoteRef/key
        value: synapse/prod/platform-svc/jwt-secret
      - op: replace
        path: /spec/data/3/remoteRef/key
        value: synapse/prod/platform-svc/aes-secret-key
      - op: replace
        path: /spec/data/4/remoteRef/key
        value: synapse/prod/platform-svc/jwt-private-key
      - op: replace
        path: /spec/data/5/remoteRef/key
        value: synapse/prod/platform-svc/jwt-public-key
      - op: replace
        path: /spec/data/6/remoteRef/key
        value: synapse/prod/platform-svc/stripe-api-key
      - op: replace
        path: /spec/data/7/remoteRef/key
        value: synapse/prod/platform-svc/stripe-webhook-secret
      - op: replace
        path: /spec/data/8/remoteRef/key
        value: synapse/prod/platform-svc/google-client-id
      - op: replace
        path: /spec/data/9/remoteRef/key
        value: synapse/prod/platform-svc/google-client-secret
      - op: replace
        path: /spec/data/10/remoteRef/key
        value: synapse/prod/platform-svc/github-client-id
      - op: replace
        path: /spec/data/11/remoteRef/key
        value: synapse/prod/platform-svc/github-client-secret
      - op: replace
        path: /spec/data/12/remoteRef/key
        value: synapse/prod/platform-svc/apple-client-id
      - op: replace
        path: /spec/data/13/remoteRef/key
        value: synapse/prod/platform-svc/apple-client-secret

images:
  - name: ghcr.io/team-project-final/synapse-platform-svc
    newTag: prod-latest
```

> **인덱스 주의**: ExternalSecret `data[0..13]`는 `apps/platform-svc/base/externalsecret.yaml`의 순서와 1:1 대응. base의 data 순서가 바뀌면 이 인덱스도 갱신해야 한다. base는 현재 db-password→redis-auth-token→jwt-secret→...→apple-client-secret 순서(14개).

- [ ] **Step 3: 렌더 + 논리분리 반영 확인**

Run:
```bash
kustomize build apps/platform-svc/overlays/prod | grep -E "synapse_prod|SPRING_DATA_REDIS_DATABASE|synapse/prod/platform-svc/apple-client-secret"
```
Expected: `DATABASE_NAME: synapse_prod`, `SPRING_DATA_REDIS_DATABASE: "1"`, `synapse/prod/platform-svc/apple-client-secret`가 출력되고 **`REPLACE_ME` / `synapse/dev` 는 0건**.

확인:
```bash
kustomize build apps/platform-svc/overlays/prod | grep -cE "REPLACE_ME|synapse/dev"
```
Expected: `0`

- [ ] **Step 4: 스키마 검증**

Run: `kustomize build apps/platform-svc/overlays/prod | kubeconform -strict -ignore-missing-schemas -summary -output text`
Expected: `Summary: ... 0 errors`

- [ ] **Step 5: 커밋**

```bash
git add apps/platform-svc/overlays/prod/kustomization.yaml
git commit -m "feat(prod): platform-svc overlay 논리 분리 확정 (synapse_prod/redis idx1/synapse/prod 시크릿)"
```

---

## Task 2: engagement-svc prod overlay 신규 작성

현재 `replicas=3` + image만 있는 bare overlay. staging overlay를 미러링하되 prod 논리분리 적용.

**Files:**
- Modify(전체 교체): `apps/engagement-svc/overlays/prod/kustomization.yaml`

- [ ] **Step 1: Redis 사용 여부 확인 (앱별 키 함정)**

staging은 `REDIS_HOST`/`REDIS_PORT`를 설정한다(platform-svc 코멘트상 spring.data.redis.* 앱은 이 키를 무시). engagement가 Redis를 실제로 읽는지/논리 index 분리가 가능한지는 **앱 소스(`synapse-engagement-svc` 레포)에서 확인**한다.
- 읽지 않으면 → Redis 키 자체를 prod overlay에서 생략(불필요한 설정 제거).
- `spring.data.redis.*` 를 읽으면 → 키를 `SPRING_DATA_REDIS_*` 로 쓰고 `SPRING_DATA_REDIS_DATABASE: "1"` 추가.
- 확인 불가 시 fallback: staging 키(REDIS_HOST/PORT) 그대로 미러 + **index 분리는 캡스톤 한계로 문서화**(spec §3 Kafka와 동급).

아래 Step 2 YAML은 **fallback(staging 미러)** 기준. Step 1 확인 결과에 따라 Redis 블록만 조정.

- [ ] **Step 2: overlay 작성**

`apps/engagement-svc/overlays/prod/kustomization.yaml` 전체를 아래로 교체:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: synapse-prod

patches:
  - target:
      kind: Deployment
      name: engagement-svc
    patch: |
      - op: replace
        path: /spec/replicas
        value: 3
  - target:
      kind: ConfigMap
      name: engagement-svc-config
    patch: |
      - op: replace
        path: /data/LOG_LEVEL
        value: "INFO"
      - op: replace
        path: /data/SPRING_PROFILES_ACTIVE
        value: "prod"
      - op: add
        path: /data/DATABASE_HOST
        value: "synapse-dev-postgres.c7emuq20mhyy.ap-northeast-2.rds.amazonaws.com"
      - op: add
        path: /data/DATABASE_PORT
        value: "5432"
      - op: add
        path: /data/DATABASE_NAME
        value: "synapse_prod"
      - op: add
        path: /data/REDIS_HOST
        value: "master.synapse-dev-redis.v6lpdh.apn2.cache.amazonaws.com"
      - op: add
        path: /data/REDIS_PORT
        value: "6379"
      - op: add
        path: /data/KAFKA_BROKERS
        value: "b-1.synapsedevkafka.dchj3l.c2.kafka.ap-northeast-2.amazonaws.com:9094,b-2.synapsedevkafka.dchj3l.c2.kafka.ap-northeast-2.amazonaws.com:9094"
      - op: add
        path: /data/SPRING_DATASOURCE_URL
        value: "jdbc:postgresql://synapse-dev-postgres.c7emuq20mhyy.ap-northeast-2.rds.amazonaws.com:5432/synapse_prod"
      - op: add
        path: /data/SPRING_DATASOURCE_USERNAME
        value: "synapse_admin"
  - target:
      kind: ExternalSecret
      name: engagement-svc-external-secret
    patch: |
      - op: replace
        path: /spec/secretStoreRef/name
        value: aws-secrets-manager
      - op: replace
        path: /spec/data/0/remoteRef/key
        value: synapse/prod/engagement-svc/db-password

images:
  - name: ghcr.io/team-project-final/synapse-engagement-svc
    newTag: prod-latest
```

- [ ] **Step 3: 렌더 + 검증**

Run:
```bash
kustomize build apps/engagement-svc/overlays/prod | grep -E "synapse_prod|synapse/prod/engagement-svc/db-password"
kustomize build apps/engagement-svc/overlays/prod | grep -cE "synapse/dev|staging"
```
Expected: 첫 명령은 `synapse_prod`·prod 시크릿 경로 출력, 둘째 명령은 `0`.

Run: `kustomize build apps/engagement-svc/overlays/prod | kubeconform -strict -ignore-missing-schemas -summary -output text`
Expected: `0 errors`

- [ ] **Step 4: 커밋**

```bash
git add apps/engagement-svc/overlays/prod/kustomization.yaml
git commit -m "feat(prod): engagement-svc prod overlay 작성 (synapse_prod/prod 시크릿)"
```

---

## Task 3: knowledge-svc prod overlay 신규 작성

staging 미러. knowledge는 OpenSearch 사용(공유 dev OpenSearch — 인덱스/prefix 분리는 캡스톤 한계로 문서화, spec §3 Kafka 동급). ExternalSecret 2키(db-password, s3-access-key).

**Files:**
- Modify(전체 교체): `apps/knowledge-svc/overlays/prod/kustomization.yaml`

- [ ] **Step 1: overlay 작성**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: synapse-prod

# OpenSearch는 공유 dev 도메인 사용 — prod 인덱스/prefix 분리는 캡스톤 한계로 미적용(문서화).
patches:
  - target:
      kind: Deployment
      name: knowledge-svc
    patch: |
      - op: replace
        path: /spec/replicas
        value: 3
  - target:
      kind: ConfigMap
      name: knowledge-svc-config
    patch: |
      - op: replace
        path: /data/LOG_LEVEL
        value: "INFO"
      - op: replace
        path: /data/SPRING_PROFILES_ACTIVE
        value: "prod"
      - op: add
        path: /data/DATABASE_HOST
        value: "synapse-dev-postgres.c7emuq20mhyy.ap-northeast-2.rds.amazonaws.com"
      - op: add
        path: /data/DATABASE_PORT
        value: "5432"
      - op: add
        path: /data/DATABASE_NAME
        value: "synapse_prod"
      - op: add
        path: /data/KAFKA_BROKERS
        value: "b-1.synapsedevkafka.dchj3l.c2.kafka.ap-northeast-2.amazonaws.com:9094,b-2.synapsedevkafka.dchj3l.c2.kafka.ap-northeast-2.amazonaws.com:9094"
      - op: add
        path: /data/OPENSEARCH_URL
        value: "https://vpc-synapse-dev-qm5l2xdch6nfmkqanpmipou74a.ap-northeast-2.es.amazonaws.com"
      - op: add
        path: /data/SPRING_DATASOURCE_URL
        value: "jdbc:postgresql://synapse-dev-postgres.c7emuq20mhyy.ap-northeast-2.rds.amazonaws.com:5432/synapse_prod"
      - op: add
        path: /data/SPRING_DATASOURCE_USERNAME
        value: "synapse_admin"
  - target:
      kind: ExternalSecret
      name: knowledge-svc-external-secret
    patch: |
      - op: replace
        path: /spec/secretStoreRef/name
        value: aws-secrets-manager
      - op: replace
        path: /spec/data/0/remoteRef/key
        value: synapse/prod/knowledge-svc/db-password
      - op: replace
        path: /spec/data/1/remoteRef/key
        value: synapse/prod/knowledge-svc/s3-access-key

images:
  - name: ghcr.io/team-project-final/synapse-knowledge-svc
    newTag: prod-latest
```

- [ ] **Step 2: 렌더 + 검증**

Run:
```bash
kustomize build apps/knowledge-svc/overlays/prod | grep -E "synapse_prod|synapse/prod/knowledge-svc/s3-access-key"
kustomize build apps/knowledge-svc/overlays/prod | grep -cE "synapse/dev"
```
Expected: 첫 명령 출력 있음, 둘째 `0`.

Run: `kustomize build apps/knowledge-svc/overlays/prod | kubeconform -strict -ignore-missing-schemas -summary -output text`
Expected: `0 errors`

- [ ] **Step 3: 커밋**

```bash
git add apps/knowledge-svc/overlays/prod/kustomization.yaml
git commit -m "feat(prod): knowledge-svc prod overlay 작성 (synapse_prod/prod 시크릿)"
```

---

## Task 4: learning-card prod overlay 신규 작성

staging 미러. ⚠️ base ExternalSecret의 `SPRING_DATASOURCE_PASSWORD`는 **`synapse/dev/knowledge-svc/db-password`** 를 참조(learning-card 아님). 공유 DB 비밀번호(모든 svc가 `synapse_admin` 사용)라 의도된 공유일 수 있음.

**Files:**
- Modify(전체 교체): `apps/learning-card/overlays/prod/kustomization.yaml`

- [ ] **Step 1: 공유 DB 비밀번호 참조 결정**

`apps/learning-card/base/externalsecret.yaml` 의 `SPRING_DATASOURCE_PASSWORD` → `synapse/dev/knowledge-svc/db-password` 가 의도인지 확인:
- **의도(공유)** 라면 prod도 `synapse/prod/knowledge-svc/db-password` 참조 → 이 경우 Step 2 YAML 그대로.
- **버그(learning-card여야)** 라면 base를 먼저 별도 PR로 고치고 prod는 `synapse/prod/learning-card/db-password`. (이 플랜 범위 밖 base 수정이므로 team-lead 확인)

기본값: **공유로 간주**(아래 YAML). 결정이 바뀌면 remoteRef key만 교체.

- [ ] **Step 2: overlay 작성**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: synapse-prod

patches:
  - target:
      kind: Deployment
      name: learning-card
    patch: |
      - op: replace
        path: /spec/replicas
        value: 3
  - target:
      kind: ConfigMap
      name: learning-card-config
    patch: |
      - op: replace
        path: /data/LOG_LEVEL
        value: "INFO"
      - op: replace
        path: /data/SPRING_PROFILES_ACTIVE
        value: "prod"
      - op: add
        path: /data/DATABASE_HOST
        value: "synapse-dev-postgres.c7emuq20mhyy.ap-northeast-2.rds.amazonaws.com"
      - op: add
        path: /data/DATABASE_PORT
        value: "5432"
      - op: add
        path: /data/DATABASE_NAME
        value: "synapse_prod"
      - op: add
        path: /data/KAFKA_BROKERS
        value: "b-1.synapsedevkafka.dchj3l.c2.kafka.ap-northeast-2.amazonaws.com:9094,b-2.synapsedevkafka.dchj3l.c2.kafka.ap-northeast-2.amazonaws.com:9094"
      - op: add
        path: /data/SPRING_DATASOURCE_URL
        value: "jdbc:postgresql://synapse-dev-postgres.c7emuq20mhyy.ap-northeast-2.rds.amazonaws.com:5432/synapse_prod"
      - op: add
        path: /data/SPRING_DATASOURCE_USERNAME
        value: "synapse_admin"
  - target:
      kind: ExternalSecret
      name: learning-card-external-secret
    patch: |
      - op: replace
        path: /spec/secretStoreRef/name
        value: aws-secrets-manager
      - op: replace
        path: /spec/data/0/remoteRef/key
        value: synapse/prod/learning-card/api-key
      - op: replace
        path: /spec/data/1/remoteRef/key
        value: synapse/prod/knowledge-svc/db-password

images:
  - name: ghcr.io/team-project-final/synapse-learning-card
    newTag: prod-latest
```

- [ ] **Step 3: 렌더 + 검증**

Run:
```bash
kustomize build apps/learning-card/overlays/prod | grep -E "synapse_prod|synapse/prod/learning-card/api-key"
kustomize build apps/learning-card/overlays/prod | grep -cE "synapse/dev"
```
Expected: 첫 명령 출력 있음, 둘째 `0`.

Run: `kustomize build apps/learning-card/overlays/prod | kubeconform -strict -ignore-missing-schemas -summary -output text`
Expected: `0 errors`

- [ ] **Step 4: 커밋**

```bash
git add apps/learning-card/overlays/prod/kustomization.yaml
git commit -m "feat(prod): learning-card prod overlay 작성 (synapse_prod/prod 시크릿)"
```

---

## Task 5: learning-ai prod overlay 신규 작성

Python 서비스. `SPRING_PROFILES_ACTIVE` 없음. DB는 `LEARNING_AI_DATABASE_URL`(asyncpg). OpenSearch 공유. ExternalSecret 2키(openai-api-key, db-password).

**Files:**
- Modify(전체 교체): `apps/learning-ai/overlays/prod/kustomization.yaml`

- [ ] **Step 1: overlay 작성**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: synapse-prod

# Python 서비스 — SPRING_PROFILES_ACTIVE 없음. DB는 LEARNING_AI_DATABASE_URL(asyncpg).
# OpenSearch는 공유 dev 도메인(캡스톤 한계, 문서화).
patches:
  - target:
      kind: Deployment
      name: learning-ai
    patch: |
      - op: replace
        path: /spec/replicas
        value: 3
  - target:
      kind: ConfigMap
      name: learning-ai-config
    patch: |
      - op: replace
        path: /data/LOG_LEVEL
        value: "INFO"
      - op: add
        path: /data/DATABASE_HOST
        value: "synapse-dev-postgres.c7emuq20mhyy.ap-northeast-2.rds.amazonaws.com"
      - op: add
        path: /data/DATABASE_PORT
        value: "5432"
      - op: add
        path: /data/DATABASE_NAME
        value: "synapse_prod"
      - op: add
        path: /data/KAFKA_BROKERS
        value: "b-1.synapsedevkafka.dchj3l.c2.kafka.ap-northeast-2.amazonaws.com:9094,b-2.synapsedevkafka.dchj3l.c2.kafka.ap-northeast-2.amazonaws.com:9094"
      - op: add
        path: /data/OPENSEARCH_URL
        value: "https://vpc-synapse-dev-qm5l2xdch6nfmkqanpmipou74a.ap-northeast-2.es.amazonaws.com"
      - op: add
        path: /data/LEARNING_AI_DATABASE_URL
        value: "postgresql+asyncpg://synapse_admin@synapse-dev-postgres.c7emuq20mhyy.ap-northeast-2.rds.amazonaws.com:5432/synapse_prod"
  - target:
      kind: ExternalSecret
      name: learning-ai-external-secret
    patch: |
      - op: replace
        path: /spec/secretStoreRef/name
        value: aws-secrets-manager
      - op: replace
        path: /spec/data/0/remoteRef/key
        value: synapse/prod/learning-ai/openai-api-key
      - op: replace
        path: /spec/data/1/remoteRef/key
        value: synapse/prod/learning-ai/db-password

images:
  - name: ghcr.io/team-project-final/synapse-learning-ai
    newTag: prod-latest
```

- [ ] **Step 2: 렌더 + 검증**

Run:
```bash
kustomize build apps/learning-ai/overlays/prod | grep -E "synapse_prod|synapse/prod/learning-ai/openai-api-key"
kustomize build apps/learning-ai/overlays/prod | grep -cE "synapse/dev"
```
Expected: 첫 명령 출력 있음, 둘째 `0`.

Run: `kustomize build apps/learning-ai/overlays/prod | kubeconform -strict -ignore-missing-schemas -summary -output text`
Expected: `0 errors`

- [ ] **Step 3: 5개 overlay 일괄 검증 (CI 미러)**

Run (bash):
```bash
for d in apps/*/overlays/prod; do echo "--- $d ---"; kustomize build "$d" >/dev/null && echo OK || echo FAIL; done
yamllint -c .yamllint apps/
```
Expected: 5개 모두 `OK`, yamllint 무경고.

- [ ] **Step 4: 커밋**

```bash
git add apps/learning-ai/overlays/prod/kustomization.yaml
git commit -m "feat(prod): learning-ai prod overlay 작성 (synapse_prod/prod 시크릿)"
```

---

## Task 6: `synapse-prod` AppProject 추가

RBAC 리소스 포맷이 `<project>/<application>`이라, `role:prod-deployer`의 `synapse-prod/*` glob이 의도대로(=prod 앱만) 동작하려면 prod 앱이 **별도 `synapse-prod` 프로젝트**에 속해야 한다(spec §4.1).

**Files:**
- Modify: `argocd/projects.yaml` (기존 `synapse` 뒤에 append)

- [ ] **Step 1: AppProject 추가**

`argocd/projects.yaml` 끝에 아래를 append(기존 `synapse` AppProject는 유지):

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: synapse-prod
  namespace: argocd
spec:
  description: Synapse prod (manual sync, restricted)
  sourceRepos:
    - https://github.com/team-project-final/synapse-gitops.git
  destinations:
    - namespace: synapse-prod
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: ""
      kind: Namespace
  namespaceResourceWhitelist:
    - group: "*"
      kind: "*"
```

- [ ] **Step 2: 검증**

Run: `yamllint -c .yamllint argocd/projects.yaml && kubeconform -strict -ignore-missing-schemas argocd/projects.yaml`
Expected: 린트 무경고, kubeconform `0 errors`(AppProject CRD는 ignore-missing-schemas로 skip).

- [ ] **Step 3: 커밋**

```bash
git add argocd/projects.yaml
git commit -m "feat(prod): synapse-prod AppProject 추가 (RBAC scope 분리용)"
```

---

## Task 7: prod ApplicationSet (manual sync) 추가

staging 패턴(`applicationset-staging.yaml`, list generator 5개) 미러링하되 **`syncPolicy.automated` 제거**(수동) + **image-updater 어노테이션 없음**(prod 이미지=명시적 PR 승격).

**Files:**
- Create: `argocd/applicationset-prod.yaml`

- [ ] **Step 1: ApplicationSet 작성**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: synapse-apps-prod
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - service: platform-svc
          - service: engagement-svc
          - service: knowledge-svc
          - service: learning-card
          - service: learning-ai
  template:
    metadata:
      name: "synapse-{{service}}-prod"
      namespace: argocd
      labels:
        app.kubernetes.io/part-of: synapse
        app.kubernetes.io/component: "{{service}}"
        environment: prod
    spec:
      project: synapse-prod
      source:
        repoURL: https://github.com/team-project-final/synapse-gitops.git
        targetRevision: main
        path: "apps/{{service}}/overlays/prod"
      destination:
        server: https://kubernetes.default.svc
        namespace: synapse-prod
      # ⚠️ automated 없음 — main 머지 후 OutOfSync 대기 → gitops-admin 수동 sync (FR-GO-402 승인 게이트)
      syncPolicy:
        syncOptions:
          - CreateNamespace=true
```

- [ ] **Step 2: 검증 — automated 없음 확인**

Run:
```bash
yamllint -c .yamllint argocd/applicationset-prod.yaml
grep -c "automated" argocd/applicationset-prod.yaml
grep -c "image-updater" argocd/applicationset-prod.yaml
```
Expected: 린트 무경고, 두 `grep -c` 모두 `0`.

Run: `kubeconform -strict -ignore-missing-schemas argocd/applicationset-prod.yaml`
Expected: `0 errors`(ApplicationSet CRD skip).

- [ ] **Step 3: 커밋**

```bash
git add argocd/applicationset-prod.yaml
git commit -m "feat(prod): prod ApplicationSet 추가 (manual sync, image-updater 없음)"
```

---

## Task 8: RBAC 권한 분리 + 로컬 계정

`role:prod-deployer`(synapse-prod sync만) + `gitops-admin` 계정. `policy.default: role:readonly` 유지 → 일반 계정 prod sync 거부(FR-GO-403).

**Files:**
- Modify: `argocd/bootstrap/rbac-cm.yaml`
- Create: `argocd/bootstrap/argocd-cm.yaml`

- [ ] **Step 1: rbac-cm에 prod-deployer role 추가**

`argocd/bootstrap/rbac-cm.yaml`의 `policy.csv` 블록에서 `g, admin, role:admin` 줄 **앞에** 아래 4줄을 추가:

```
    p, role:prod-deployer, applications, sync, synapse-prod/*, allow
    p, role:prod-deployer, applications, get, */*, allow
    p, role:prod-deployer, projects, get, *, allow
    g, gitops-admin, role:prod-deployer
```

수정 후 `policy.csv` 전체는 아래와 같아야 한다:

```yaml
data:
  policy.default: role:readonly
  policy.csv: |
    p, role:admin, applications, *, */*, allow
    p, role:admin, clusters, *, *, allow
    p, role:admin, repositories, *, *, allow
    p, role:admin, projects, *, *, allow
    p, role:admin, accounts, *, *, allow
    p, role:admin, certificates, *, *, allow
    p, role:readonly, applications, get, */*, allow
    p, role:readonly, projects, get, *, allow
    p, role:prod-deployer, applications, sync, synapse-prod/*, allow
    p, role:prod-deployer, applications, get, */*, allow
    p, role:prod-deployer, projects, get, *, allow
    g, gitops-admin, role:prod-deployer
    g, admin, role:admin
  scopes: "[groups]"
```

- [ ] **Step 2: argocd-cm 로컬 계정 정의 신규**

`argocd/bootstrap/` 에는 현재 `argocd-cm`이 없다(`rbac-cm`/`notifications-cm`만). `gitops-admin` 로컬 계정을 정의할 파일을 생성:

`argocd/bootstrap/argocd-cm.yaml`:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-cm
    app.kubernetes.io/part-of: argocd
data:
  # prod 수동 sync 전용 로컬 계정. RBAC: g, gitops-admin, role:prod-deployer (rbac-cm.yaml)
  # 비밀번호는 설치 후 `argocd account update-password --account gitops-admin` 로 설정(시크릿 미커밋).
  accounts.gitops-admin: apiKey, login
```

> **적용 경로 확인 필요(spec §7 OPEN)**: `scripts/bootstrap-argocd.sh`가 bootstrap CM들을 어떻게 apply하는지 확인하고, 누락 시 `argocd-cm.yaml`을 동일 경로에 편입한다. (Task 8 Step 3 참조)

- [ ] **Step 3: bootstrap 적용 경로에 argocd-cm 편입 확인**

Run: `grep -rn "bootstrap" scripts/bootstrap-argocd.sh`
- bootstrap 디렉토리를 `kubectl apply -f argocd/bootstrap/` 처럼 디렉토리째 적용하면 추가 작업 불필요.
- 파일을 개별 나열해 apply하면 `argocd-cm.yaml`을 목록에 추가.
- Argo가 Helm/values로 argocd-cm을 관리하면 `accounts.gitops-admin`을 values에 반영(이 경우 bootstrap/argocd-cm.yaml은 참고용 + 적용 방식 주석 명시).

확인 결과에 맞춰 적용 경로를 수정(스크립트 수정 시 같은 커밋에 포함).

- [ ] **Step 4: 검증**

Run:
```bash
yamllint -c .yamllint argocd/bootstrap/rbac-cm.yaml argocd/bootstrap/argocd-cm.yaml
grep -c "prod-deployer" argocd/bootstrap/rbac-cm.yaml
grep "accounts.gitops-admin" argocd/bootstrap/argocd-cm.yaml
```
Expected: 린트 무경고, `prod-deployer` 3건, `accounts.gitops-admin: apiKey, login` 출력.

- [ ] **Step 5: 커밋**

```bash
git add argocd/bootstrap/rbac-cm.yaml argocd/bootstrap/argocd-cm.yaml
git commit -m "feat(prod): RBAC role:prod-deployer + gitops-admin 로컬 계정"
```

---

## Task 9 (라이브): 첫 prod 배포 + 권한 검증

> **과금 구간**. Step 10(롤백/백업) 검증과 batching. 사전조건 미충족 시 중단하고 비용 0 작업만 머지.

**라이브 사전조건 (체크):**
- [ ] EKS 클러스터 기동 (`cd infra/aws/dev && terraform apply`), ArgoCD 설치/부트스트랩 완료
- [ ] D-039 ESO role 충돌 처리: `terraform import aws_iam_role.eso synapse-dev-eso-role` 또는 수동 role 삭제 (`infra/aws/dev/eso-irsa.tf` 주석 참조)
- [ ] AWS SM에 `synapse/prod/{app}/*` 시크릿 생성 — platform-svc 14, engagement 1, knowledge 2, learning-card 2(공유 db-password 포함), learning-ai 2. ESO 정책 `synapse/*`가 이미 커버(W3 A2)
- [ ] 공유 RDS에 `synapse_prod` DB 생성 (`CREATE DATABASE synapse_prod;`)
- [ ] prod 이미지 태그(`prod-latest`)가 ghcr.io에 push돼 있음 — 없으면 명시적 PR 승격 경로로 먼저 push (cf. 레지스트리 일관성: staging은 ECR newName, prod 스캐폴드는 ghcr.io. deploy-mirror-standardization 트랙과 정합 확인)
- [ ] prod 도메인(Route53) — 없으면 FR-GO-404는 port-forward로 대체 검증

- [ ] **Step 1: prod ApplicationSet + AppProject + RBAC 적용**

```bash
kubectl apply -f argocd/projects.yaml
kubectl apply -f argocd/bootstrap/rbac-cm.yaml -f argocd/bootstrap/argocd-cm.yaml
kubectl apply -f argocd/applicationset-prod.yaml
argocd account update-password --account gitops-admin   # 대화형, 비밀번호 설정
```
Expected: `synapse-{svc}-prod` Application 5개 생성, 모두 **OutOfSync**(automated 없음 → 자동 sync 안 됨 = FR-GO-402 증명).

Run: `argocd app list -p synapse-prod`
Expected: 5개 앱, SYNC STATUS = `OutOfSync`.

- [ ] **Step 2: FR-GO-403 — 일반 계정 sync 거부 확인**

```bash
# readonly(기본) 계정 또는 권한 없는 계정으로:
argocd account can-i sync applications "synapse-prod/synapse-platform-svc-prod"
```
Expected: `no`

- [ ] **Step 3: FR-GO-404 — gitops-admin 수동 sync → 5/5 기동**

```bash
argocd login <NLB_HOST> --username gitops-admin --password <설정값> --insecure --grpc-web
argocd account can-i sync applications "synapse-prod/synapse-platform-svc-prod"   # → yes
for s in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  argocd app sync "synapse-$s-prod"
done
kubectl get pods -n synapse-prod
```
Expected: `can-i` = `yes`, 5개 앱 Synced/Healthy, `synapse-prod` ns에 5개 서비스 Pod Running(replicas=3).

- [ ] **Step 4: 데이터 논리분리 스모크 체크**

```bash
# platform-svc Pod 환경변수에 prod 분리 키가 주입됐는지
kubectl exec -n synapse-prod deploy/platform-svc -- printenv | grep -E "DATABASE_NAME|SPRING_DATA_REDIS_DATABASE"
```
Expected: `DATABASE_NAME=synapse_prod`, `SPRING_DATA_REDIS_DATABASE=1`.

- [ ] **Step 5: 엔드포인트 200 확인 (도메인 또는 port-forward)**

```bash
kubectl port-forward -n synapse-prod svc/platform-svc 8080:8080 &
curl -so /dev/null -w "%{http_code}\n" http://localhost:8080/actuator/health
```
Expected: `200`

- [ ] **Step 6: 검증 결과 기록**

Step 1~5 결과(스크린샷/로그)를 `docs/superpowers/` 핸드오프 또는 검증 노트에 기록. FR-GO-401~404 Done 표시.

---

## 문서화 (Task 1~8과 함께 머지)

- [ ] **argocd/README.md 갱신**: "환경 추가" 섹션에 prod = 별도 `applicationset-prod.yaml`(matrix 아닌 독립 파일) + manual sync + `synapse-prod` AppProject + `gitops-admin`/`prod-deployer` RBAC를 반영. prod 이미지=명시적 PR 승격(image-updater 없음) 명시.

---

## Self-Review (스펙 커버리지)

| spec/PRD 요구 | 구현 Task |
|---|---|
| FR-GO-401 prod overlay ×5 | Task 1~5 |
| FR-GO-402 Manual Sync | Task 7 (automated 제거) + Task 9 Step 1 |
| FR-GO-403 권한 분리(거부) | Task 8 + Task 9 Step 2 |
| FR-GO-404 첫 prod 배포+검증 | Task 9 Step 3~5 |
| §3 데이터 논리분리(DB/Redis/시크릿) | Task 1~5 + Task 9 Step 4 |
| §4.1 AppProject | Task 6 |
| §4.3 argocd-cm 로컬 계정 | Task 8 Step 2~3 |

**미해결(라이브 사전조건으로 이관)**: prod SM 시크릿 생성, `synapse_prod` DB 생성, prod 이미지 push, 도메인. 모두 Task 9 사전조건 체크리스트에 명시.
