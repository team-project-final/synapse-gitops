# W4 Step 10 — 롤백 + 백업 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** prod/staging에 GitOps 우선 롤백(ArgoCD History / git revert)과 Velero 기반 ns 백업·복구를 갖춰 RTO 30분 / RPO 1시간을 증명한다 (FR-GO-405~408).

**Architecture:** 1차 롤백은 코드 경로(ArgoCD History rollback, git revert PR) — DB 스키마는 forward-only(Flyway). 백업은 Velero가 `synapse-prod`/`synapse-staging` ns + PV를 일일 스냅샷해 전용 S3 버킷에 저장(IRSA로 권한 부여). 백업 실패는 W3 observability(PrometheusRule→Alertmanager Slack) 재사용으로 알람.

**Tech Stack:** Velero (AWS plugin), Terraform(S3+IRSA, `aws_iam_openid_connect_provider.eks` 미러), ArgoCD CLI, kube-prometheus-stack(PrometheusRule).

> **Step 9와 독립**: 롤백·백업은 **staging에서도 검증 가능**(prod 라이브 불필요). Step 9와 별개로 실행/머지할 수 있다.

---

## 검증 도구

- Terraform: `terraform -chdir=infra/aws/dev fmt -check` + `terraform -chdir=infra/aws/dev validate`
- 매니페스트: `yamllint -c .yamllint infra/` + `kubeconform -strict -ignore-missing-schemas <file>`
- 라이브 검증: `velero`, `argocd`, `kubectl` CLI

> **비용**: Task 1(terraform 코드)·Task 3·4(매니페스트) = 비용 0 준비. Task 2(Velero 설치)·Task 5(라이브 드릴) = prod/staging 라이브 사이클(과금). Step 9 라이브와 batching, 종료 시 `terraform destroy`.

---

## File Structure

| 파일 | 책임 | 작업 |
|---|---|---|
| `infra/aws/dev/velero.tf` | Velero S3 버킷 + IRSA(S3/EC2 snapshot) | **신규** |
| `infra/aws/dev/outputs.tf` | velero role/bucket output | **수정**(append) |
| `infra/monitoring/velero-schedule.yaml` | Velero `Schedule` CR(일일, ns 최소) | **신규** |
| `infra/monitoring/prometheus-rules.yaml` | 백업 실패 알람 룰 추가 | **수정** |
| `docs/runbooks/w4-prod-rollback-backup-runbook.md` | 롤백/복구 절차서(FR-GO-405~408) | **신규** |

---

## Task 1: Velero S3 버킷 + IRSA terraform

`eso-irsa.tf` 패턴 미러링(같은 OIDC provider `aws_iam_openid_connect_provider.eks`). Velero SA = `velero/velero`. 버킷·IAM은 비용 0(스토리지 과금은 백업 저장 시점부터, 무시 가능 수준).

**Files:**
- Create: `infra/aws/dev/velero.tf`
- Modify: `infra/aws/dev/outputs.tf`

- [ ] **Step 1: velero.tf 작성**

```hcl
# Velero 백업용 S3 버킷 + IRSA. eso-irsa.tf 패턴 미러링.
# SA: velero/velero. ns(synapse-prod/staging)+PV 일일 백업 → 이 버킷.

data "aws_caller_identity" "current" {}

locals {
  velero_bucket = "synapse-velero-backups-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "velero" {
  bucket = local.velero_bucket
}

resource "aws_s3_bucket_public_access_block" "velero" {
  bucket                  = aws_s3_bucket.velero.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "velero_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:velero:velero"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "velero" {
  # S3: 백업 객체 read/write
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListMultipartUploadParts",
      "s3:AbortMultipartUpload",
    ]
    resources = ["${aws_s3_bucket.velero.arn}/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.velero.arn]
  }
  # EC2: PV(EBS) 스냅샷
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeVolumes",
      "ec2:DescribeSnapshots",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:CreateSnapshot",
      "ec2:DeleteSnapshot",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "velero" {
  name        = "synapse-dev-velero"
  description = "Velero backup: S3 (velero bucket) + EBS snapshot"
  policy      = data.aws_iam_policy_document.velero.json
}

resource "aws_iam_role" "velero" {
  name               = "synapse-dev-velero-role"
  assume_role_policy = data.aws_iam_policy_document.velero_assume.json
}

resource "aws_iam_role_policy_attachment" "velero" {
  role       = aws_iam_role.velero.name
  policy_arn = aws_iam_policy.velero.arn
}
```

- [ ] **Step 2: outputs.tf에 output 추가**

`infra/aws/dev/outputs.tf` 끝에 append:

```hcl
output "velero_role_arn" {
  description = "Velero IRSA role ARN (annotate velero SA with this)"
  value       = aws_iam_role.velero.arn
}

output "velero_bucket" {
  description = "Velero backup S3 bucket"
  value       = aws_s3_bucket.velero.id
}
```

- [ ] **Step 3: terraform 검증**

Run:
```bash
terraform -chdir=infra/aws/dev fmt -check
terraform -chdir=infra/aws/dev validate
```
Expected: fmt 변경 없음(있으면 `terraform -chdir=infra/aws/dev fmt` 실행 후 재확인), validate `Success`.

> **주의**: `validate`는 backend init 필요. 미초기화 시 `terraform -chdir=infra/aws/dev init -backend=false` 후 validate.

- [ ] **Step 4: 커밋**

```bash
git add infra/aws/dev/velero.tf infra/aws/dev/outputs.tf
git commit -m "feat(backup): Velero S3 버킷 + IRSA terraform (eso-irsa 패턴)"
```

---

## Task 2 (라이브): Velero 설치 + BackupStorageLocation

> **과금 구간**. Step 1의 terraform이 apply돼 role/bucket이 존재해야 한다.

**사전조건:**
- [ ] `terraform -chdir=infra/aws/dev apply` 완료 → `velero_role_arn`, `velero_bucket` output 확보
- [ ] `velero` CLI 설치 (https://velero.io/docs)

- [ ] **Step 1: Velero 설치(IRSA, S3 BSL)**

```bash
VELERO_ROLE=$(terraform -chdir=infra/aws/dev output -raw velero_role_arn)
VELERO_BUCKET=$(terraform -chdir=infra/aws/dev output -raw velero_bucket)

velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.10.0 \
  --bucket "$VELERO_BUCKET" \
  --backup-location-config region=ap-northeast-2 \
  --snapshot-location-config region=ap-northeast-2 \
  --no-secret \
  --service-account-annotations eks.amazonaws.com/role-arn="$VELERO_ROLE" \
  --sa-annotations eks.amazonaws.com/role-arn="$VELERO_ROLE"
```
> IRSA 사용이므로 `--no-secret`(정적 키 미사용). `velero` ns/SA가 IRSA 신뢰정책(`system:serviceaccount:velero:velero`)과 일치해야 함.

Run: `velero backup-location get`
Expected: `default` location `Phase: Available`.

- [ ] **Step 2: 권한 스모크 — 임시 백업**

```bash
velero backup create velero-smoke --include-namespaces synapse-staging --wait
velero backup describe velero-smoke --details
```
Expected: `Phase: Completed`, S3 버킷에 객체 생성. (실패 시 IRSA 신뢰정책/정책 권한 점검)

---

## Task 3: Velero Schedule CR (일일 백업, ns 최소)

`synapse-prod` + `synapse-staging` ns + PV를 매일 백업(FR-GO-407). 매니페스트는 비용 0 작성, apply는 라이브(Task 5).

**Files:**
- Create: `infra/monitoring/velero-schedule.yaml`

- [ ] **Step 1: Schedule CR 작성**

```yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: synapse-daily
  namespace: velero
spec:
  # 매일 17:00 UTC = 02:00 KST
  schedule: "0 17 * * *"
  template:
    includedNamespaces:
      - synapse-prod
      - synapse-staging
    snapshotVolumes: true
    # RPO 1시간 목표 대비 일일 스케줄은 캡스톤 비용 한계 — 필요 시 cron 단축(예: "0 */1 * * *").
    ttl: 720h0m0s
```

> **RPO 주석**: 일일 스케줄의 실제 RPO는 최대 24h. spec의 RPO 1h를 충족하려면 cron을 시간별로 단축해야 하나 캡스톤 비용 한계로 일일 채택 — runbook(Task 5)에 한계 명시 + DB는 RDS 자동백업(PITR)이 RPO 1h를 별도 보장함을 기록.

- [ ] **Step 2: 검증**

Run:
```bash
yamllint -c .yamllint infra/monitoring/velero-schedule.yaml
kubeconform -strict -ignore-missing-schemas infra/monitoring/velero-schedule.yaml
```
Expected: 린트 무경고, kubeconform `0 errors`(Schedule CRD skip).

- [ ] **Step 3: 커밋**

```bash
git add infra/monitoring/velero-schedule.yaml
git commit -m "feat(backup): Velero 일일 Schedule (synapse-prod/staging ns+PV)"
```

---

## Task 4: 백업 실패 알람 (PrometheusRule)

W3 observability 재사용. `velero_backup_failure_total` 증가 시 Slack 알람(Alertmanager 라우팅은 기존 `alertmanager-slack-externalsecret.yaml`).

**Files:**
- Modify: `infra/monitoring/prometheus-rules.yaml`

- [ ] **Step 1: velero 그룹 추가**

`infra/monitoring/prometheus-rules.yaml`의 `spec.groups` 리스트 끝에 아래 그룹을 추가(기존 `synapse.rules` 그룹 뒤):

```yaml
    - name: velero.rules
      rules:
        - alert: VeleroBackupFailed
          expr: increase(velero_backup_failure_total[1h]) > 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Velero 백업 실패 (schedule {{ $labels.schedule }})"
        - alert: VeleroBackupPartialFailure
          expr: increase(velero_backup_partial_failure_total[1h]) > 0
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Velero 백업 부분 실패 (schedule {{ $labels.schedule }})"
```

- [ ] **Step 2: 검증**

Run:
```bash
yamllint -c .yamllint infra/monitoring/prometheus-rules.yaml
kubeconform -strict -ignore-missing-schemas infra/monitoring/prometheus-rules.yaml
grep -c "velero.rules" infra/monitoring/prometheus-rules.yaml
```
Expected: 린트 무경고, kubeconform `0 errors`, `velero.rules` 1건.

- [ ] **Step 3: 커밋**

```bash
git add infra/monitoring/prometheus-rules.yaml
git commit -m "feat(backup): Velero 백업 실패 PrometheusRule (W3 Alertmanager 재사용)"
```

---

## Task 5: 롤백/복구 절차서 (runbook)

FR-GO-405/406(롤백)과 408(복구) 절차를 문서화. `docs/runbooks/` 기존 패턴 따름.

**Files:**
- Create: `docs/runbooks/w4-prod-rollback-backup-runbook.md`

- [ ] **Step 1: runbook 작성**

```markdown
# W4 prod 롤백·백업 Runbook

> RTO 30분 / RPO 1시간 (team-lead 합의). 1차 롤백=GitOps 코드 경로, DB=forward-only.

## 1. ArgoCD History 롤백 (FR-GO-405)
1. `argocd app history synapse-<svc>-prod` 로 직전 synced revision ID 확인
2. `argocd app rollback synapse-<svc>-prod <id>` (prod는 gitops-admin 계정)
3. `argocd app get synapse-<svc>-prod` → Synced/Healthy 확인
- 적용 대상: 워크로드/설정 회귀. 단발 1-step 롤백.

## 2. git revert 롤백 (FR-GO-406)
1. 문제 커밋 `git revert <sha>` → revert PR 생성
2. main 머지 (PR 보호 게이트 통과)
3. sync: staging은 auto, prod는 gitops-admin 수동 `argocd app sync`
- 적용 대상: 영구 롤백(소스 of truth 복원).

## 3. 이미지 롤백
- overlay `images[].newTag`를 직전 태그로 되돌리는 PR (승격이 PR이므로 동일 경로). → 2와 동일 sync.

## 4. DB 스키마
- forward-only(Flyway). 위 메커니즘으로 스키마 롤백하지 않음. 데이터는 RDS 자동백업(PITR)로 복구.

## 5. Velero 복구 시뮬레이션 (FR-GO-408)
1. (드릴) `kubectl delete ns synapse-staging` 또는 일부 리소스 삭제
2. `velero restore create --from-backup <backup-name> --include-namespaces synapse-staging --wait`
3. `kubectl get pods -n synapse-staging` → 복구 확인
- etcd는 관리형 EKS=AWS 책임, 직접 snapshot 불가.

## 한계 (캡스톤)
- Velero 일일 스케줄 → 객체/PV RPO 최대 24h. DB는 RDS PITR가 RPO 1h 별도 보장.
- prod/staging 논리 분리 — Kafka 토픽/OpenSearch 인덱스 공유.
```

- [ ] **Step 2: 커밋**

```bash
git add docs/runbooks/w4-prod-rollback-backup-runbook.md
git commit -m "docs(runbook): W4 prod 롤백·백업 절차서 (FR-GO-405/406/408)"
```

---

## Task 6 (라이브): 백업/복구 + 롤백 드릴 검증

> **과금 구간**. Task 2(Velero 설치) 완료 + staging/prod 워크로드 기동 후. Step 9 라이브와 batching.

- [ ] **Step 1: FR-GO-407 — 일일 백업 동작 확인**

```bash
kubectl apply -f infra/monitoring/velero-schedule.yaml
velero schedule get
# 스케줄을 기다리지 않고 즉시 1회 트리거:
velero backup create --from-schedule synapse-daily synapse-daily-manual --wait
velero backup describe synapse-daily-manual --details
```
Expected: `Phase: Completed`, includedNamespaces=synapse-prod/staging, S3 버킷에 객체 저장 확인(`aws s3 ls s3://<velero_bucket>/backups/`).

- [ ] **Step 2: FR-GO-408 — staging ns 삭제 → 복구**

```bash
kubectl delete ns synapse-staging
velero restore create staging-restore --from-backup synapse-daily-manual --include-namespaces synapse-staging --wait
kubectl get pods -n synapse-staging
```
Expected: restore `Phase: Completed`, staging Pod 재기동. (RTO 30분 내 측정 기록)

- [ ] **Step 3: FR-GO-405 — ArgoCD History 1-step 롤백 (staging)**

```bash
# 무해한 변경(예: replicas/LOG_LEVEL) 커밋·sync 후:
argocd app history synapse-platform-svc-staging
argocd app rollback synapse-platform-svc-staging <직전-id>
argocd app get synapse-platform-svc-staging
```
Expected: 직전 revision으로 Synced/Healthy.

- [ ] **Step 4: FR-GO-406 — git revert 롤백**

```bash
git revert <테스트-커밋-sha>   # revert PR → main 머지
argocd app sync synapse-platform-svc-staging   # prod면 gitops-admin
```
Expected: revert 반영 → 복원 확인.

- [ ] **Step 5: 알람 경로 확인(선택)**

의도적 실패(예: 잘못된 BSL) 유발 또는 메트릭 확인:
```bash
kubectl exec -n velero deploy/velero -- wget -qO- localhost:8085/metrics | grep velero_backup
```
Expected: `velero_backup_failure_total`/`velero_backup_success_total` 메트릭 노출 → PrometheusRule 평가 가능.

- [ ] **Step 6: 결과 기록**

RTO/RPO 측정값과 각 FR Done 여부를 핸드오프/검증 노트에 기록.

---

## Self-Review (스펙 커버리지)

| spec/PRD 요구 | 구현 Task |
|---|---|
| FR-GO-405 ArgoCD History 롤백 | Task 5 §1 + Task 6 Step 3 |
| FR-GO-406 git revert 롤백 | Task 5 §2 + Task 6 Step 4 |
| FR-GO-407 Velero 일일 백업 | Task 1(IRSA/버킷) + Task 3(Schedule) + Task 6 Step 1 |
| FR-GO-408 백업 복구 시뮬 | Task 6 Step 2 |
| §5.2 백업 실패 알람 | Task 4 |
| §5.2 RTO 30m/RPO 1h | Task 3 주석 + Task 5 runbook + Task 6 측정 |
| §5.1 DB forward-only | Task 5 runbook §4 |

**미해결(라이브 사전조건)**: Velero CLI 설치, terraform apply(role/bucket), staging/prod 워크로드 기동. 모두 Task 2/6 사전조건에 명시.
