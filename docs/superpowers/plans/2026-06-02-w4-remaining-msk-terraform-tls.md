# W4 잔여 2일 — MSK terraform 편입(TLS-only) + 정리·마감 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** W4 잔여 실작업일(06-04·06-05)에 MSK 9개 토픽을 terraform 선언으로 전환(TLS-only)하고, git 정리·W4 마감·shared 정합·W5 스코핑을 봉합한다.

**Architecture:** MSK 인증은 TLS-only 유지(`msk.tf` 무변경). 토픽은 `infra/aws/dev/kafka-topics/`에 `Mongey/kafka` provider로 별도 state 분리 — 인프라 apply(브로커 생성) → 토픽 apply의 2단계. 토픽 apply는 private subnet 도달이 필요하므로 **bastion에서 terraform 실행**(Go 단일 바이너리, JRE 불필요)으로 수행. 라이브 검증은 06-04 1회 기동 window, 06-05 destroy로 과금 차단.

**Tech Stack:** Terraform (>=1.7, hashicorp/aws ~>5.40, Mongey/kafka ~>0.7), AWS MSK(Kafka 3.6, TLS 9094), AWS SSM(bastion 접속), kustomize overlays, ArgoCD Image Updater.

**참조 spec:** `docs/superpowers/specs/2026-06-02-w4-remaining-msk-terraform-tls-design.md`

---

## File Structure

| 파일 | 책임 | 생성/수정 |
|---|---|---|
| `infra/aws/dev/kafka-topics/main.tf` | kafka provider + 9개 `kafka_topic` 선언 | Create |
| `infra/aws/dev/kafka-topics/variables.tf` | `bootstrap_servers` 입력 변수 | Create |
| `infra/aws/dev/kafka-topics/versions.tf` | required_providers (Mongey/kafka) | Create |
| `infra/aws/dev/kafka-topics/README.md` | 2단계 apply 절차(bastion 실행 포함) | Create |
| `.gitignore` | `infra/aws/dev/*.log` 무시 | Modify |
| `apps/<svc>/overlays/<env>/kustomization.yaml` | apply 후 브로커 DNS 갱신(5 svc × 3 env) | Modify (라이브 window) |
| `docs/project-management/workflow/WORKFLOW_gitops_W4.md` | 토픽 terraform화·사인오프·마감 반영 | Modify |
| `docs/project-management/history/HISTORY_gitops.md` | 06-04/05 라이브 기록 | Modify |
| `docs/superpowers/W5-scoping.md` | W5 범위 초안(백로그 포함) | Create |
| (shared repo) `docs/guides/KAFKA_AUTH_MATRIX.md` | TLS-only 정렬 | Modify (cross-repo PR) |

**주의:** 작업 브랜치 = `docs/w4-remaining-msk-terraform-tls`(이미 spec 커밋됨). 라이브 window 전 Phase 0는 오프라인 가능.

---

## Phase 0 — 오프라인 준비 (06-02 오늘, 비용 0)

### Task 1: git 정리 — 머지된 브랜치 삭제 · main ff · 로그 gitignore

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: 현재 상태 확인 (삭제 안전성 재검증)**

Run:
```bash
git fetch --all --prune
git branch --merged origin/main | grep -E "chore/local-k8s-cleanup|feat/deploy-mirror-standardization|feat/gateway-dev-overlay"
git rev-list --left-right --count origin/main...docs/unified-handoff-hub-spoke
```
Expected: 앞 3개 브랜치가 merged 목록에 나옴. orphan은 `192  1`(1 커밋, 내용은 main과 동일 — Task 1 Step 2에서 재확인).

- [ ] **Step 2: orphan 브랜치 내용이 main과 동일한지 재확인**

Run: `git diff origin/main docs/unified-handoff-hub-spoke -- site/lib/pages/doc_page.dart`
Expected: 출력 비어 있음(=내용 동일 → 무손실 삭제 가능). 비어 있지 않으면 중단하고 사용자에게 보고.

- [ ] **Step 3: `.gitignore`에 infra 로그 패턴 추가**

`.gitignore`의 `# === Terraform ===` 섹션을 다음으로 수정:
```gitignore
# === Terraform ===
infra/aws/dev/tfplan
infra/aws/dev/*.log
```

- [ ] **Step 4: 로그가 무시되는지 검증**

Run: `git check-ignore infra/aws/dev/apply.log infra/aws/dev/destroy.log`
Expected: 두 경로가 출력됨(=이제 무시됨).

- [ ] **Step 5: 로컬 main을 origin으로 ff**

Run:
```bash
git switch main
git pull --ff-only
git log --oneline -1
```
Expected: `17255da` 또는 그 이후 커밋(Merge PR #85)로 이동. ff 실패 시 중단·보고.

- [ ] **Step 6: 작업 브랜치 복귀 + 머지된 로컬 브랜치 4개 삭제**

Run:
```bash
git switch docs/w4-remaining-msk-terraform-tls
git branch -D chore/local-k8s-cleanup feat/deploy-mirror-standardization feat/gateway-dev-overlay docs/unified-handoff-hub-spoke
git branch
```
Expected: 4개 삭제됨, 남는 로컬 = `main`, `docs/w4-remaining-msk-terraform-tls`(현재). (`-D`는 orphan이 origin/main 미머지 표시이나 내용 동일 검증을 Step 2에서 마쳤기 때문.)

- [ ] **Step 7: Commit (.gitignore)**

```bash
git add .gitignore
git commit -m "chore(infra): gitignore infra/aws/dev/*.log (apply/destroy 로그 아티팩트)"
```

---

### Task 2: 토픽 terraform 구성 — versions.tf

**Files:**
- Create: `infra/aws/dev/kafka-topics/versions.tf`

- [ ] **Step 1: provider 버전 선언 작성**

`infra/aws/dev/kafka-topics/versions.tf`:
```hcl
terraform {
  required_version = ">= 1.7.0"

  required_providers {
    kafka = {
      source  = "Mongey/kafka"
      version = "~> 0.7"
    }
  }
}

provider "kafka" {
  bootstrap_servers = var.bootstrap_servers
  tls_enabled       = true
  # MSK TLS(9094): 브로커는 Amazon Trust Services CA 체인 → 기본 시스템 신뢰스토어로 검증.
  # 별도 클라이언트 인증서 없음(TLS-only, SASL/IAM 미사용 — spec §3 B안).
}
```

- [ ] **Step 2: HCL 문법 검증(offline)**

Run: `cd infra/aws/dev/kafka-topics && terraform fmt -check && terraform init -backend=false && terraform validate`
Expected: `terraform init`이 Mongey/kafka provider 다운로드, `validate`는 변수 미정의로 실패할 수 있음 → Task 3·4 후 재검증. fmt는 통과.

---

### Task 3: 토픽 terraform 구성 — variables.tf

**Files:**
- Create: `infra/aws/dev/kafka-topics/variables.tf`

- [ ] **Step 1: 입력 변수 작성**

`infra/aws/dev/kafka-topics/variables.tf`:
```hcl
variable "bootstrap_servers" {
  description = "MSK TLS bootstrap brokers (9094). 인프라 state의 msk_bootstrap_brokers_tls output에서 취득."
  type        = list(string)
}

variable "replication_factor" {
  description = "토픽 복제 계수. MSK 브로커 수와 정합(dev=3)."
  type        = number
  default     = 3
}

variable "min_insync_replicas" {
  description = "min.insync.replicas. aws_msk_configuration(min.insync.replicas=2)와 정합."
  type        = string
  default     = "2"
}
```

- [ ] **Step 2: fmt 검증**

Run: `cd infra/aws/dev/kafka-topics && terraform fmt -check`
Expected: 통과(변경 없음).

---

### Task 4: 토픽 terraform 구성 — main.tf (9개 토픽)

**Files:**
- Create: `infra/aws/dev/kafka-topics/main.tf`

- [ ] **Step 1: 9개 토픽 선언 작성 (단일 출처 = EVENT_CONTRACT_STANDARD §2)**

`infra/aws/dev/kafka-topics/main.tf`:
```hcl
# Kafka 토픽 선언 (단일 출처: shared EVENT_CONTRACT_STANDARD §2 / create-kafka-topics.sh TOPICS)
# 기존 bastion 수동 스크립트(create-kafka-topics.sh)를 terraform 선언으로 대체.
# partitions=3 (aws_msk_configuration num.partitions=3 정합).

locals {
  topics = [
    "platform.auth.user-registered-v1",
    "knowledge.note.note-created-v1",
    "knowledge.note.note-updated-v1",
    "learning.card.review-completed-v1",
    "learning.card.review-due-v1",
    "engagement.gamification.level-up-v1",
    "engagement.gamification.badge-earned-v1",
    "platform.notification.notification-send-v1",
    "learning.ai.cards-generated-v1", # deprecated(D-001 HTTP 전환) — 토픽만 존속, 동등 선언
  ]
}

resource "kafka_topic" "synapse" {
  for_each           = toset(local.topics)
  name               = each.value
  partitions         = 3
  replication_factor = var.replication_factor

  config = {
    "min.insync.replicas" = var.min_insync_replicas
    "retention.ms"        = "604800000" # 168h (aws_msk_configuration log.retention.hours=168 정합)
  }
}
```

- [ ] **Step 2: validate (변수 채운 상태)**

Run:
```bash
cd infra/aws/dev/kafka-topics
terraform init -backend=false
terraform validate
```
Expected: `Success! The configuration is valid.` (apply 아님 — 브로커 연결 불필요).

- [ ] **Step 3: 토픽 수 검증 (9개)**

Run: `grep -c '"' infra/aws/dev/kafka-topics/main.tf` 대신 명시 확인 — `terraform console`로:
```bash
cd infra/aws/dev/kafka-topics && echo 'length(local.topics)' | terraform console
```
Expected: `9`.

- [ ] **Step 4: Commit (토픽 TF 구성)**

```bash
git add infra/aws/dev/kafka-topics/versions.tf infra/aws/dev/kafka-topics/variables.tf infra/aws/dev/kafka-topics/main.tf
git commit -m "feat(infra): MSK 토픽 9개 terraform 선언화 (Mongey/kafka, TLS-only) — bastion 수동 대체"
```

---

### Task 5: 토픽 apply 절차 README (bastion 실행 turnkey화)

**Files:**
- Create: `infra/aws/dev/kafka-topics/README.md`

- [ ] **Step 1: 2단계 apply 절차 문서 작성**

`infra/aws/dev/kafka-topics/README.md`:
```markdown
# MSK 토픽 terraform 관리 (TLS-only)

MSK 9개 토픽을 선언 관리한다. 기존 `create-kafka-topics.sh`(bastion 수동) 대체.

## 전제
- 인프라(`infra/aws/dev`)가 apply되어 MSK 브로커가 ACTIVE.
- MSK는 private subnet → **bastion에서 실행**(또는 bastion 경유 도달). TLS-only라 IAM/Kafka CLI 불필요, terraform Go 바이너리만 필요(JRE 불필요).

## 절차 (라이브 window)

### 1. 브로커 주소 취득 (로컬, 인프라 디렉터리)
```bash
cd infra/aws/dev
terraform output -raw msk_bootstrap_brokers_tls   # b-1...:9094,b-2...:9094
```

### 2. bastion에 terraform 설치 (SSM, 1회)
```bash
aws ssm send-command --instance-ids <bastion_instance_id> \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["cd /tmp && curl -fsSL https://releases.hashicorp.com/terraform/1.9.8/terraform_1.9.8_linux_amd64.zip -o tf.zip && unzip -o tf.zip && sudo mv terraform /usr/local/bin/ && terraform version"]'
```

### 3. bastion에 토픽 구성 복사 + apply
```bash
# 구성을 bastion으로 (git clone 또는 SSM으로 파일 전송)
# bastion 셸에서:
cd /tmp/kafka-topics
terraform init
terraform apply -var='bootstrap_servers=["b-1...:9094","b-2...:9094"]'
```

### 4. 검증 (9개 토픽)
```bash
terraform state list | grep kafka_topic | wc -l   # 9
```

## 폴백
provider 연결 실패 시 진단: SG(9094 inbound) 확인 → `infra/aws/dev` SG 수동 추가(D-026). 그래도 실패 시 기존 `create-kafka-topics.sh`는 bastion에 JRE+kafka CLI가 없어 사용 불가 → terraform provider 경로가 유일 실용 경로(spec §3.3).
```

- [ ] **Step 2: Commit (README)**

```bash
git add infra/aws/dev/kafka-topics/README.md
git commit -m "docs(infra): MSK 토픽 terraform apply 절차(bastion 실행) README"
```

---

### Task 6: image-updater E2E 라이브 런북 사전 점검

**Files:**
- 없음(읽기만) — 기존 런북 확인

- [ ] **Step 1: image-updater bypass 런북 존재·최신성 확인**

Run: `git -C ../synapse-shared log --oneline -3 -- '**/image-updater*'` 또는
```bash
ls docs/runbooks/ | grep -i image
```
Expected: image-updater 관련 런북 식별(A5 절차: ruleset bypass → ECR semver push → write-back). 없으면 Task 10에서 작성 항목으로 이관.

- [ ] **Step 2: A5 라이브 절차를 window 체크리스트로 정리(메모)**

`docs/superpowers/W5-scoping.md`에 임시 섹션이 아니라, 06-04 window 실행 순서를 spec §5에 이미 정의됨 — 별도 산출물 없음. 런북 누락 시에만 작성.

---

## Phase 1 — 라이브 기동 window (06-04, 과금 발생)

### Task 7: 인프라 재기동 + 브로커 주소 확보

**Files:**
- 없음(terraform apply)

- [ ] **Step 1: 인프라 apply**

Run:
```bash
cd infra/aws/dev
terraform init
terraform apply
```
Expected: EKS/MSK/RDS/Redis/OpenSearch 재생성. `Apply complete!`. (로그는 `apply.log`로 리다이렉트 가능 — gitignore됨.)

- [ ] **Step 2: 브로커 주소 + bastion id output**

Run:
```bash
terraform output -raw msk_bootstrap_brokers_tls
terraform output -raw bastion_instance_id
```
Expected: 9094 TLS 브로커 2개, bastion 인스턴스 id.

- [ ] **Step 3: SG 수동 추가 (D-026 재현 방지)**

`eks-cluster-sg-*` ↔ MSK(9094) inbound 확인. 누락 시 추가(shared `W4_DAY1_POST_APPLY` §SG 근거).
Run: `aws ec2 describe-security-groups --group-ids $(terraform output -raw sg_msk_id) --query 'SecurityGroups[0].IpPermissions'`
Expected: 9094가 EKS 노드 SG에서 도달 가능. 아니면 inbound rule 추가.

---

### Task 8: 토픽 terraform apply (bastion) + 검증

**Files:**
- 없음(`kafka-topics/` apply)

- [ ] **Step 1: bastion에 terraform 설치 (README §2)**

Run: `infra/aws/dev/kafka-topics/README.md` §2의 SSM 명령 실행.
Expected: `terraform version` 출력(1.9.x).

- [ ] **Step 2: 토픽 구성 전송 + apply (README §3)**

Run: README §3 절차. `terraform apply -var='bootstrap_servers=[...]'`.
Expected: `Apply complete! Resources: 9 added.`

- [ ] **Step 3: 토픽 9개 검증**

Run: `terraform state list | grep -c kafka_topic`
Expected: `9`.

- [ ] **Step 4: 검증 결과 캡처 (성공 기준 증거)**

apply 출력·state list를 HISTORY용으로 저장(텍스트). 이미지 토픽 생성 입증.

---

### Task 9: service overlay 브로커 주소 갱신 + image-updater E2E

**Files:**
- Modify: `apps/engagement-svc/overlays/{dev,staging,prod}/kustomization.yaml`
- Modify: `apps/knowledge-svc/overlays/{dev,staging,prod}/kustomization.yaml`
- Modify: `apps/learning-ai/overlays/{dev,staging,prod}/kustomization.yaml`
- Modify: `apps/learning-card/overlays/{dev,staging,prod}/kustomization.yaml`
- Modify: `apps/platform-svc/overlays/{dev,staging,prod}/kustomization.yaml` (KAFKA_BROKERS 보유 시)

- [ ] **Step 1: 신규 브로커 DNS로 KAFKA_BROKERS 일괄 갱신**

Run: 기존 값(예: `b-1.synapsedevkafka.dchj3l...`)을 Task 7 Step 2의 신규 DNS로 치환. 대상 파일 grep:
```bash
grep -rl "KAFKA_BROKERS" apps/ | xargs grep -l "9094"
```
각 파일의 `value: "b-1...:9094,b-2...:9094"`를 신규 주소로 수정.

- [ ] **Step 2: kustomize 렌더 검증**

Run: `kustomize build apps/engagement-svc/overlays/dev > /dev/null && echo OK`
Expected: `OK`(렌더 에러 없음). 5개 svc × dev 반복.

- [ ] **Step 3: image-updater E2E(A5) 라이브 검증**

ECR 상위 semver push → image-updater write-back 커밋(브랜치 `image-updates-<app>`) → PR/auto-merge(prod=B안) 또는 dev 자동 sync 확인. 결과 캡처(목표 5분 내 반영).
Expected: write-back 커밋 발생 + ArgoCD sync로 새 이미지 반영.

- [ ] **Step 4: Commit (overlay 브로커 주소)**

```bash
git add apps/*/overlays/*/kustomization.yaml
git commit -m "fix(overlays): MSK 브로커 주소 갱신 (재apply 신규 DNS, 5 svc × 3 env)"
```

---

## Phase 2 — 마감 + destroy (06-05, 비용 차단 복귀)

### Task 10: shared 정합 — KAFKA_AUTH_MATRIX TLS-only (cross-repo)

**Files:**
- Modify (shared repo): `C:/workspace/team-project-final/synapse-shared/docs/guides/KAFKA_AUTH_MATRIX.md`

- [ ] **Step 1: §1 인증표를 TLS-only로 수정**

`dev/staging/prod (MSK)` 행: 프로토콜 `TLS (9094)`, 인증 `없음(전송 암호화)`, 권한 제어 `SG/네트워크 경계`로 변경. IAM/AWS_MSK_IAM 표기 제거.

- [ ] **Step 2: §1 "선결 결정 필요" 경고 블록 → 결정 기록으로 갱신**

`(A)/(B)` 선택 경고를 "**결정: B(TLS-only) 채택 — gitops spec 2026-06-02, msk.tf 무변경·토픽 terraform화**. A(SASL/IAM)는 W5+ 백로그(서비스 코드 `aws-msk-iam-auth` 의존)"로 교체.

- [ ] **Step 3: §3 IAM Policy 예시 강등**

§3을 "A안 백로그 참조용(미적용)"으로 헤더 표기. 본문 보존하되 적용 대상 아님 명시.

- [ ] **Step 4: shared 커밋 (별도 repo)**

```bash
git -C ../synapse-shared add docs/guides/KAFKA_AUTH_MATRIX.md
git -C ../synapse-shared commit -m "docs(kafka): 인증 모델 B(TLS-only) 확정 반영 — gitops 2026-06-02 결정"
```
(push/PR은 사용자 확인 후.)

---

### Task 11: W4 마감 패키지 — WORKFLOW · HISTORY · 사인오프

**Files:**
- Modify: `docs/project-management/workflow/WORKFLOW_gitops_W4.md`
- Modify: `docs/project-management/history/HISTORY_gitops.md`

- [ ] **Step 1: WORKFLOW에 토픽 terraform화·라이브 결과 반영**

Step 9/10 잔여 항목 중 image-updater E2E(W2 이월) 라이브 검증 결과를 반영하고, MSK 토픽 terraform화를 신규 완료 항목으로 기록. 사인오프 2건은 "전달 패키지 준비 완료, 합의 대기"로 상태 명시.

- [ ] **Step 2: HISTORY에 06-04/05 라이브 기록 추가**

`HISTORY_gitops.md`에 2026-06-04(재기동·토픽 terraform apply 9개·image-updater E2E)·2026-06-05(destroy) 섹션 추가. Task 8 Step 4·Task 9 Step 3 증거 인용.

- [ ] **Step 3: 사인오프 패키지 정리**

권한모델(ArgoCD RBAC `role:prod-deployer`)·RTO 30분/RPO 1시간을 team-lead 전달용 1-pager로 정리(WORKFLOW 내 섹션 또는 별도 노트).

- [ ] **Step 4: Commit (마감 문서)**

```bash
git add docs/project-management/
git commit -m "docs(w4): 마감 — 토픽 terraform화·image-updater E2E 라이브 반영 + 사인오프 패키지"
```

---

### Task 12: 이월 정정 + W5 스코핑

**Files:**
- Create: `docs/superpowers/W5-scoping.md`

- [ ] **Step 1: 이월 항목 차단사유 명시 정정**

WORKFLOW의 실도메인 3항목(W1)·image-updater 잔여 측정 항목을 "차단사유=도메인 부재/측정은 라이브 재기동 시" 명시로 닫고 "복귀 시 즉시 실행" 상태 표기.

- [ ] **Step 2: W5 범위 초안 작성**

`docs/superpowers/W5-scoping.md`:
```markdown
# W5 스코핑 초안 (2026-06-02 작성)

## 백로그 (W4에서 의도적 이월/강등)
- **A안 SASL/IAM 전환**: msk.tf `client_authentication.sasl.iam=true` + 5개 서비스 `aws-msk-iam-auth` 의존성·IRSA 매트릭스. 타 owner 조율 필요.
- **브로커 주소 자동화**: 재apply마다 변동하는 DNS → `terraform output` 단일 ConfigMap 소싱(overlay 하드코딩 5×3 제거).
- **실도메인 의존 3항목**: ACM ARN·DNS·ArgoCD UI TLS·webhook 외부 도달 (W1 이월, 도메인 확보 시).
- **image-updater 측정**: 평균 반영시간(목표 5분)·잘못된 이미지 롤백 케이스(W2 이월).

## team-lead 의존
- 권한모델·RTO/RPO 사인오프(패키지 준비 완료).

## 후보 주제
- (W5 착수 시 brainstorming으로 구체화)
```

- [ ] **Step 3: Commit (W5 스코핑)**

```bash
git add docs/superpowers/W5-scoping.md docs/project-management/workflow/WORKFLOW_gitops_W4.md
git commit -m "docs(w5): 스코핑 초안 + W4 이월 항목 차단사유 정정"
```

---

### Task 13: terraform destroy (과금 차단 복귀)

**Files:**
- 없음

- [ ] **Step 1: 토픽 state 정리(선택) + 인프라 destroy**

Run:
```bash
cd infra/aws/dev
terraform destroy
```
Expected: `Destroy complete! Resources: NN destroyed.` (토픽은 클러스터 삭제와 함께 소멸 — kafka-topics state는 stale 허용, 다음 기동 시 재 apply.)

- [ ] **Step 2: destroy 확인 + HISTORY 마감 갱신**

Run: `aws kafka list-clusters --query 'ClusterInfoList[].ClusterName'`
Expected: synapse-dev-kafka 부재. HISTORY 06-05 destroy 줄 확정.

- [ ] **Step 3: PR 생성 (사용자 확인 후)**

```bash
git push -u origin docs/w4-remaining-msk-terraform-tls
gh pr create --base main --title "feat(w4): MSK 토픽 terraform화(TLS-only) + W4 마감·정리" --body "spec: docs/superpowers/specs/2026-06-02-w4-remaining-msk-terraform-tls-design.md"
```

---

## Self-Review (작성자 점검)

**Spec coverage:**
- §3 인증 B(TLS-only) → Task 2(provider tls_enabled)·Task 10(매트릭스 정렬) ✅
- §4.2 토픽 9개 terraform화 → Task 2~5, 8 ✅
- §4.3 브로커 주소(옵션) → Task 9(이번 갱신)·Task 12(자동화는 W5 백로그) ✅
- §5 라이브 window(apply/destroy/image-updater) → Task 7·8·9·13 ✅
- §6 경량 트랙 A(git)·B(마감)·C(이월)·D(shared)·E(W5) → Task 1·11·12·10·12 ✅
- §3.3 bastion 경로 → Task 5·8 ✅

**Placeholder scan:** TBD/TODO 없음. 모든 코드 스텝에 실제 HCL/명령 포함.

**Type consistency:** `bootstrap_servers`(list(string)) — variables.tf↔versions.tf↔apply -var 일치. `replication_factor`/`min_insync_replicas` 변수명 Task 3↔4 일치. output 이름 `msk_bootstrap_brokers_tls`·`bastion_instance_id`·`sg_msk_id`는 실제 outputs.tf와 일치(확인됨).

**알려진 리스크(spec §9):** 토픽 TF provider의 bastion 실행은 첫 실증 — Task 8에서 검증, 실패 시 README 폴백 진단(SG 9094).
