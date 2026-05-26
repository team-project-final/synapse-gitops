# Bring-up 자동화·견고화 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** destroy된 클러스터를 한 명령(`scripts/bring-up.sh`)으로 dev/staging+observability까지 멱등 기동하고, `--verify`로 W3 잔여 3항목을 반복 검증한다.

**Architecture:** 로컬 단일 bash 스크립트가 terraform/AWS CLI 단계 후 SSM 포트포워딩 터널을 열어 kubectl/helm을 로컬에서 터널 경유 실행. EBS CSI는 terraform addon으로, SG/OIDC 취약점은 terraform output + 멱등 phase로 제거. 죽은 argocd helm_release 제거.

**Tech Stack:** bash, terraform(aws provider), aws-cli, kubectl, helm, AWS SSM Session Manager, External Secrets Operator, kube-prometheus-stack, Loki.

**설계 spec:** [2026-05-26-bringup-automation-design.md](../specs/2026-05-26-bringup-automation-design.md)

---

## 작업 그룹

- **Group T — Terraform** (T1 outputs, T2 EBS CSI addon+IRSA, T3 gp3 SC, T4 argocd 제거, T5 validate)
- **Group L — 터널 헬퍼** (L1 `lib/eks-tunnel.sh`)
- **Group S — `bring-up.sh`** (S1 골격, S2 local phases, S3 cluster phases, S4 oidc+manifests, S5 observability+status, S6 `--verify`, S7 `--destroy`)
- **Group D — 문서** (D1 런북 갱신)
- **Group A — 수용** (A1 shellcheck+dry-run, A2 실 사이클)

## 파일 구조

| 경로 | 동작 | 책임 |
|---|---|---|
| `infra/aws/dev/outputs.tf` | 수정 | SG ID 4종 + eks_cluster_sg + oidc_id output 추가 |
| `infra/aws/dev/addons.tf` | 생성 | EBS CSI addon + IRSA role/policy |
| `infra/aws/dev/argocd.tf` | 삭제 | 죽은 helm_release.argocd 제거 |
| `infra/monitoring/storageclass-gp3.yaml` | 생성 | gp3 default StorageClass |
| `scripts/lib/eks-tunnel.sh` | 생성 | SSM 터널 + 터널 kubeconfig |
| `scripts/bring-up.sh` | 생성 | 멱등 오케스트레이터 |
| `docs/runbooks/w2-session-bootstrap-runbook.md` | 수정 | 스크립트 1차 경로화 |

---

## Group T — Terraform

### Task T1: SG/OIDC output 추가

**Files:**
- Modify: `infra/aws/dev/outputs.tf`

- [ ] **Step 1: output 블록 추가**

`infra/aws/dev/outputs.tf` 끝에 추가 (SG 리소스명: `aws_security_group.{rds,redis,msk,opensearch}` — vpc.tf, EKS cluster SG는 클러스터 auto-managed):
```hcl
# ─── Bring-up automation outputs ──────────────────────────────────────────
output "eks_cluster_security_group_id" {
  description = "EKS 클러스터 auto-managed SG (D-026 source)"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "sg_rds_id" {
  description = "RDS SG ID"
  value       = aws_security_group.rds.id
}

output "sg_redis_id" {
  description = "Redis SG ID"
  value       = aws_security_group.redis.id
}

output "sg_msk_id" {
  description = "MSK SG ID"
  value       = aws_security_group.msk.id
}

output "sg_opensearch_id" {
  description = "OpenSearch SG ID"
  value       = aws_security_group.opensearch.id
}

output "eks_oidc_id" {
  description = "EKS OIDC provider ID (마지막 path 세그먼트)"
  value       = element(split("/", aws_iam_openid_connect_provider.eks.url), length(split("/", aws_iam_openid_connect_provider.eks.url)) - 1)
}
```

- [ ] **Step 2: 검증**

Run: `terraform -chdir=infra/aws/dev validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 3: 커밋**

```bash
git add infra/aws/dev/outputs.tf
git commit -m "feat(tf): bring-up용 SG/OIDC output 추가"
```

### Task T2: EBS CSI driver addon + IRSA

**Files:**
- Create: `infra/aws/dev/addons.tf`

- [ ] **Step 1: addons.tf 작성**

OIDC provider는 `aws_iam_openid_connect_provider.eks`(terraform 관리 — 매 apply 자동 갱신되므로 IRSA가 OIDC 변경을 자동 처리). `infra/aws/dev/addons.tf`:
```hcl
data "aws_iam_policy_document" "ebs_csi_assume" {
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
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "synapse-dev-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on               = [aws_eks_node_group.main]
}
```

- [ ] **Step 2: 검증**

Run: `terraform -chdir=infra/aws/dev validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 3: 커밋**

```bash
git add infra/aws/dev/addons.tf
git commit -m "feat(tf): aws-ebs-csi-driver addon + IRSA (D-033)"
```

### Task T3: gp3 default StorageClass

**Files:**
- Create: `infra/monitoring/storageclass-gp3.yaml`

- [ ] **Step 1: 매니페스트 작성**

`infra/monitoring/storageclass-gp3.yaml`:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
parameters:
  type: gp3
```

- [ ] **Step 2: 스키마 유효성 (js-yaml)**

Run: `node -e "require('./site/scripts/node_modules/js-yaml').load(require('fs').readFileSync('infra/monitoring/storageclass-gp3.yaml','utf8')); console.log('OK')"`
Expected: `OK`

- [ ] **Step 3: 커밋**

```bash
git add infra/monitoring/storageclass-gp3.yaml
git commit -m "feat(monitoring): gp3 default StorageClass (EBS CSI)"
```

### Task T4: 죽은 helm_release.argocd 제거

**Files:**
- Delete: `infra/aws/dev/argocd.tf`

- [ ] **Step 1: 파일 삭제**

Run: `git rm infra/aws/dev/argocd.tf`
(argocd는 `bring-up.sh`의 `argocd` phase가 터널 경유 설치. 이 파일의 helm_release는 private endpoint로 항상 실패하던 죽은 리소스.)

- [ ] **Step 2: 다른 곳에서 helm_release.argocd 참조 없는지 확인**

Run: `grep -rn "helm_release.argocd\|argocd_namespace" infra/aws/dev/`
Expected: 출력 없음 (참조 0건)

- [ ] **Step 3: 검증**

Run: `terraform -chdir=infra/aws/dev validate`
Expected: `Success! The configuration is valid.` (helm provider가 다른 리소스에서 안 쓰이면 provider 블록 경고 가능 — 경고면 무시, 에러면 helm provider 블록도 제거)

- [ ] **Step 4: 커밋**

```bash
git add -A infra/aws/dev/argocd.tf
git commit -m "refactor(tf): 죽은 helm_release.argocd 제거 (스크립트가 터널 경유 설치)"
```

### Task T5: terraform 전체 validate + fmt

**Files:** (검증)

- [ ] **Step 1: fmt + validate**

Run:
```bash
terraform -chdir=infra/aws/dev fmt
terraform -chdir=infra/aws/dev validate
```
Expected: validate `Success!`. fmt가 파일 수정 시 커밋.

- [ ] **Step 2: 변경 있으면 커밋**

```bash
git add -A infra/aws/dev/
git commit -m "style(tf): terraform fmt" || echo "변경 없음"
```

---

## Group L — 터널 헬퍼

### Task L1: `scripts/lib/eks-tunnel.sh`

**Files:**
- Create: `scripts/lib/eks-tunnel.sh`

- [ ] **Step 1: 헬퍼 작성**

`scripts/lib/eks-tunnel.sh` (source되어 `tunnel_up`/`tunnel_down` 제공. terraform output에서 endpoint/CA/bastion 읽음):
```bash
#!/usr/bin/env bash
# EKS private endpoint용 SSM 포트포워딩 터널 + 터널 kubeconfig
# 사용: source scripts/lib/eks-tunnel.sh; tunnel_up; ... ; tunnel_down (trap 권장)
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
CLUSTER_NAME="${CLUSTER_NAME:-synapse-dev}"
TUNNEL_LOCAL_PORT="${TUNNEL_LOCAL_PORT:-6443}"
TUNNEL_KUBECONFIG="${TUNNEL_KUBECONFIG:-/tmp/kubeconfig-synapse-tunnel.yaml}"
_TUNNEL_PID=""

tunnel_up() {
  local tfdir="infra/aws/dev"
  local bastion endpoint host ca
  bastion=$(terraform -chdir="$tfdir" output -raw bastion_instance_id)
  endpoint=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query cluster.endpoint --output text)
  host="${endpoint#https://}"
  ca=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query cluster.certificateAuthority.data --output text)

  aws ssm start-session --target "$bastion" --region "$AWS_REGION" \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters "{\"host\":[\"$host\"],\"portNumber\":[\"443\"],\"localPortNumber\":[\"$TUNNEL_LOCAL_PORT\"]}" \
    >/tmp/eks-tunnel.log 2>&1 &
  _TUNNEL_PID=$!

  cat > "$TUNNEL_KUBECONFIG" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: synapse-tunnel
  cluster:
    server: https://localhost:${TUNNEL_LOCAL_PORT}
    certificate-authority-data: ${ca}
    tls-server-name: ${host}
contexts:
- name: synapse-tunnel
  context: {cluster: synapse-tunnel, user: synapse-tunnel}
current-context: synapse-tunnel
users:
- name: synapse-tunnel
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: aws
      args: [eks, get-token, --cluster-name, ${CLUSTER_NAME}, --region, ${AWS_REGION}]
EOF
  export KUBECONFIG="$TUNNEL_KUBECONFIG"

  local i
  for i in $(seq 1 30); do
    if kubectl get --raw='/readyz' >/dev/null 2>&1; then return 0; fi
    sleep 2
  done
  echo "[ERR] 터널로 API 도달 실패 (포트 $TUNNEL_LOCAL_PORT)" >&2
  return 1
}

tunnel_down() {
  [ -n "$_TUNNEL_PID" ] && kill "$_TUNNEL_PID" 2>/dev/null || true
  _TUNNEL_PID=""
}
```

- [ ] **Step 2: shellcheck**

Run: `shellcheck scripts/lib/eks-tunnel.sh`
Expected: 출력 없음(통과). (없으면 `choco install shellcheck`)

- [ ] **Step 3: 커밋**

```bash
git add scripts/lib/eks-tunnel.sh
git commit -m "feat(scripts): EKS SSM 터널 헬퍼 (lib/eks-tunnel.sh)"
```

---

## Group S — `bring-up.sh`

### Task S1: 골격 (helpers, arg parsing, dispatch)

**Files:**
- Create: `scripts/bring-up.sh`

- [ ] **Step 1: 골격 작성**

`scripts/bring-up.sh` (helper 스타일은 `scripts/bootstrap-argocd.sh` 따름. `run`은 `--dry-run` 시 명령 출력만):
```bash
#!/usr/bin/env bash
# synapse-dev 멱등 bring-up: destroy된 상태 → dev/staging + observability
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-northeast-2}"
CLUSTER_NAME="${CLUSTER_NAME:-synapse-dev}"
ACCOUNT_ID="${ACCOUNT_ID:-963773969059}"
TFDIR="infra/aws/dev"
DRY_RUN=false
START_PHASE=""
MODE="bringup"   # bringup | verify | destroy

log() { echo -e "\033[1;34m[*]\033[0m $*"; }
ok()  { echo -e "\033[1;32m[OK]\033[0m $*"; }
warn(){ echo -e "\033[1;33m[!]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERR]\033[0m $*" >&2; }
run() { if $DRY_RUN; then echo "+ $*"; else eval "$*"; fi; }

require() { command -v "$1" >/dev/null 2>&1 || { err "필수 도구 없음: $1"; exit 1; }; }

usage() {
  cat <<USAGE
사용법: bring-up.sh [옵션]
  --from <phase>   해당 phase부터 재개 (terraform|eks-auth|access-entry|sg|tunnel|argocd|eso|oidc-fix|manifests|observability|status)
  --verify         bring-up 대신 W3 잔여 3항목 검증
  --destroy        terraform destroy (비용 차단)
  --dry-run        명령 출력만, 미실행
  --help           도움말
USAGE
}

PHASES=(terraform eks-auth access-entry sg tunnel argocd eso oidc-fix manifests observability status)

main() {
  require aws; require kubectl; require helm; require terraform; require jq
  case "$MODE" in
    destroy) phase_destroy; return ;;
    verify)  source scripts/lib/eks-tunnel.sh; trap tunnel_down EXIT; tunnel_up; verify_all; return ;;
  esac
  local started=false
  [ -z "$START_PHASE" ] && started=true
  for p in "${PHASES[@]}"; do
    [ "$p" = "$START_PHASE" ] && started=true
    $started || continue
    log "=== phase: $p ==="
    "phase_${p//-/_}"
  done
  ok "bring-up 완료. 검증: bring-up.sh --verify"
}

# (phase 함수들은 후속 Task에서 추가)

while [ $# -gt 0 ]; do
  case "$1" in
    --from) START_PHASE="$2"; shift 2;;
    --verify) MODE="verify"; shift;;
    --destroy) MODE="destroy"; shift;;
    --dry-run) DRY_RUN=true; shift;;
    --help) usage; exit 0;;
    *) err "알 수 없는 옵션: $1"; usage; exit 1;;
  esac
done
main
```

- [ ] **Step 2: 임시 스텁으로 파싱 확인**

phase 함수가 아직 없으므로, 임시로 파일 끝 `main` 위에 스텁 추가 후 `--help`/`--dry-run` 흐름만 확인:
Run: `bash scripts/bring-up.sh --help`
Expected: usage 출력, exit 0.

- [ ] **Step 3: shellcheck**

Run: `shellcheck scripts/bring-up.sh`
Expected: 통과(스텁 없는 phase 호출 경고가 나오면 다음 Task에서 함수 추가로 해소 — 이 시점엔 `--help`만 검증).

- [ ] **Step 4: 커밋**

```bash
git add scripts/bring-up.sh
git commit -m "feat(scripts): bring-up.sh 골격 (arg parsing, dispatch, dry-run)"
```

### Task S2: local phases (terraform, eks-auth, access-entry, sg)

**Files:**
- Modify: `scripts/bring-up.sh` (`# (phase 함수들…)` 자리에 삽입)

- [ ] **Step 1: 4개 phase 함수 추가**

```bash
phase_terraform() {
  run "terraform -chdir=$TFDIR init -input=false"
  run "terraform -chdir=$TFDIR apply -auto-approve -input=false"
}

phase_eks_auth() {
  local mode
  mode=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" \
    --query cluster.accessConfig.authenticationMode --output text 2>/dev/null || echo "")
  if [ "$mode" = "API_AND_CONFIG_MAP" ] || [ "$mode" = "API" ]; then
    ok "auth mode 이미 $mode"; return
  fi
  run "aws eks update-cluster-config --name $CLUSTER_NAME --region $AWS_REGION --access-config authenticationMode=API_AND_CONFIG_MAP"
  run "aws eks wait cluster-active --name $CLUSTER_NAME --region $AWS_REGION"
}

phase_access_entry() {
  local me; me=$(aws sts get-caller-identity --query Arn --output text)
  if aws eks describe-access-entry --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION" \
       --principal-arn "$me" >/dev/null 2>&1; then
    ok "access entry 이미 존재: $me"; return
  fi
  run "aws eks create-access-entry --cluster-name $CLUSTER_NAME --region $AWS_REGION --principal-arn $me --type STANDARD"
  run "aws eks associate-access-policy --cluster-name $CLUSTER_NAME --region $AWS_REGION --principal-arn $me --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --access-scope type=cluster"
}

phase_sg() {
  local eks_sg rds redis msk os
  eks_sg=$(terraform -chdir=$TFDIR output -raw eks_cluster_security_group_id)
  rds=$(terraform -chdir=$TFDIR output -raw sg_rds_id)
  redis=$(terraform -chdir=$TFDIR output -raw sg_redis_id)
  msk=$(terraform -chdir=$TFDIR output -raw sg_msk_id)
  os=$(terraform -chdir=$TFDIR output -raw sg_opensearch_id)
  _sg_ingress() { # $1=target sg $2=port
    aws ec2 authorize-security-group-ingress --region "$AWS_REGION" \
      --group-id "$1" --protocol tcp --port "$2" --source-group "$eks_sg" 2>&1 \
      | grep -q "already exists" && ok "SG $1:$2 규칙 이미 존재" || ok "SG $1:$2 추가"
  }
  if $DRY_RUN; then echo "+ SG ingress: rds:5432 redis:6379 msk:9094 os:443 from $eks_sg"; return; fi
  _sg_ingress "$rds" 5432; _sg_ingress "$redis" 6379; _sg_ingress "$msk" 9094; _sg_ingress "$os" 443
}
```

- [ ] **Step 2: dry-run 흐름 확인**

Run: `bash scripts/bring-up.sh --dry-run --from sg`
Expected: `+ SG ingress: ...` 라인 + 이후 phase들의 `+ ...` 출력 (실제 미실행).

- [ ] **Step 3: shellcheck + 커밋**

```bash
shellcheck scripts/bring-up.sh
git add scripts/bring-up.sh
git commit -m "feat(scripts): local phases (terraform/eks-auth/access-entry/sg)"
```

### Task S3: cluster phases (tunnel, argocd, eso)

**Files:**
- Modify: `scripts/bring-up.sh`

- [ ] **Step 1: 3개 phase 함수 추가**

```bash
phase_tunnel() {
  source scripts/lib/eks-tunnel.sh
  trap tunnel_down EXIT
  if $DRY_RUN; then echo "+ tunnel_up (SSM 포트포워딩 + 터널 kubeconfig)"; return; fi
  tunnel_up && ok "터널 연결, kubectl 도달"
}

phase_argocd() {
  run "kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -"
  run "kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
  run "kubectl -n argocd patch deploy argocd-server --type=json -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--insecure\"}]' || true"
  run "kubectl -n argocd rollout status deploy/argocd-server --timeout=300s"
}

phase_eso() {
  run "helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true"
  run "helm repo update external-secrets >/dev/null"
  run "helm upgrade --install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace --wait --timeout 5m"
  run "kubectl -n external-secrets annotate sa external-secrets eks.amazonaws.com/role-arn=arn:aws:iam::${ACCOUNT_ID}:role/synapse-dev-eso-role --overwrite"
  run "kubectl -n external-secrets rollout restart deploy external-secrets"
  run "kubectl -n external-secrets rollout status deploy external-secrets --timeout=180s"
}
```

- [ ] **Step 2: dry-run 확인**

Run: `bash scripts/bring-up.sh --dry-run --from argocd`
Expected: argocd/eso phase의 `+ kubectl ...`, `+ helm ...` 라인 출력.

- [ ] **Step 3: shellcheck + 커밋**

```bash
shellcheck scripts/bring-up.sh
git add scripts/bring-up.sh
git commit -m "feat(scripts): cluster phases (tunnel/argocd/eso)"
```

### Task S4: oidc-fix + manifests phases

**Files:**
- Modify: `scripts/bring-up.sh`

- [ ] **Step 1: 2개 phase 함수 추가**

```bash
phase_oidc_fix() {
  local cur trust
  cur=$(terraform -chdir=$TFDIR output -raw eks_oidc_id)
  trust=$(aws iam get-role --role-name synapse-dev-eso-role \
    --query 'Role.AssumeRolePolicyDocument' --output json 2>/dev/null | jq -r '.Statement[0].Principal.Federated' | awk -F'/' '{print $NF}')
  if [ "$cur" = "$trust" ]; then ok "ESO role OIDC 일치 ($cur)"; return; fi
  warn "ESO role OIDC 불일치: trust=$trust, 현재=$cur → 갱신"
  local pol="{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Federated\":\"arn:aws:iam::${ACCOUNT_ID}:oidc-provider/oidc.eks.${AWS_REGION}.amazonaws.com/id/${cur}\"},\"Action\":\"sts:AssumeRoleWithWebIdentity\",\"Condition\":{\"StringEquals\":{\"oidc.eks.${AWS_REGION}.amazonaws.com/id/${cur}:aud\":\"sts.amazonaws.com\",\"oidc.eks.${AWS_REGION}.amazonaws.com/id/${cur}:sub\":\"system:serviceaccount:external-secrets:external-secrets\"}}}]}"
  run "aws iam update-assume-role-policy --role-name synapse-dev-eso-role --policy-document '$pol'"
  run "kubectl -n external-secrets rollout restart deploy external-secrets"
}

phase_manifests() {
  run "kubectl apply -f infra/external-secrets/cluster-secret-store.yaml"
  run "kubectl apply -f argocd/projects.yaml"
  run "kubectl apply -f argocd/applicationset.yaml"
  run "kubectl apply -f argocd/applicationset-staging.yaml"
  if $DRY_RUN; then return; fi
  kubectl wait --for=condition=Ready clustersecretstore/aws-secrets-manager --timeout=120s || warn "ClusterSecretStore 미Ready"
  kubectl -n synapse-dev wait --for=condition=Ready externalsecret --all --timeout=180s || warn "일부 ExternalSecret 미Synced"
}
```

- [ ] **Step 2: dry-run 확인**

Run: `bash scripts/bring-up.sh --dry-run --from oidc-fix`
Expected: oidc-fix/manifests의 명령 라인 출력.

- [ ] **Step 3: shellcheck + 커밋**

```bash
shellcheck scripts/bring-up.sh
git add scripts/bring-up.sh
git commit -m "feat(scripts): oidc-fix + manifests phases"
```

### Task S5: observability + status phases

**Files:**
- Modify: `scripts/bring-up.sh`

- [ ] **Step 1: 2개 phase 함수 추가**

```bash
phase_observability() {
  run "kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -"
  run "kubectl apply -f infra/monitoring/storageclass-gp3.yaml"
  # 기본 SC였던 gp2의 default 해제(존재 시)
  run "kubectl patch storageclass gp2 -p '{\"metadata\":{\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"false\"}}}' 2>/dev/null || true"
  # AWS SM 시크릿 존재 확인 (없으면 경고 후 ESO sync 실패 가능)
  for s in synapse/monitoring/grafana synapse/monitoring/alertmanager; do
    if ! aws secretsmanager describe-secret --secret-id "$s" --region "$AWS_REGION" >/dev/null 2>&1; then
      warn "AWS SM 시크릿 없음: $s → aws secretsmanager create-secret로 1회 등록 필요(실 Slack/Grafana)"
    fi
  done
  run "kubectl apply -f infra/monitoring/grafana-admin-externalsecret.yaml -f infra/monitoring/alertmanager-slack-externalsecret.yaml"
  run "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true"
  run "helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true"
  run "helm repo update >/dev/null"
  run "helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring -f infra/monitoring/kube-prometheus-stack-values.yaml --timeout 8m"
  run "kubectl apply -f infra/monitoring/servicemonitor-synapse.yaml -f infra/monitoring/prometheus-rules.yaml -f infra/monitoring/grafana-dashboard-synapse.yaml"
  run "helm upgrade --install loki grafana/loki -n monitoring -f infra/monitoring/loki-values.yaml --timeout 6m"
  run "helm upgrade --install promtail grafana/promtail -n monitoring --set 'config.clients[0].url=http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push' --timeout 5m"
}

phase_status() {
  if $DRY_RUN; then echo "+ status 출력"; return; fi
  echo "--- ArgoCD apps ---"; kubectl -n argocd get applications 2>/dev/null || true
  echo "--- synapse-dev pods ---"; kubectl -n synapse-dev get pods 2>/dev/null || true
  echo "--- synapse-staging pods ---"; kubectl -n synapse-staging get pods 2>/dev/null || true
  echo "--- monitoring pods ---"; kubectl -n monitoring get pods 2>/dev/null || true
}
```

- [ ] **Step 2: dry-run 전체 확인**

Run: `bash scripts/bring-up.sh --dry-run`
Expected: 11개 phase 전체의 명령 라인이 순서대로 출력, exit 0.

- [ ] **Step 3: shellcheck + 커밋**

```bash
shellcheck scripts/bring-up.sh
git add scripts/bring-up.sh
git commit -m "feat(scripts): observability + status phases"
```

### Task S6: `--verify` 모드

**Files:**
- Modify: `scripts/bring-up.sh`

- [ ] **Step 1: verify 함수 추가**

```bash
verify_all() {
  local report="verification-$(date +%Y%m%d-%H%M).md"
  { echo "# Bring-up 검증 $(date -u +%FT%TZ)"; echo; } > "$report"

  # 1) staging N/5 Healthy
  echo "## staging Healthy" | tee -a "$report"
  kubectl -n argocd get applications -o json \
    | jq -r '.items[] | select(.metadata.name|test("staging")) | "\(.metadata.name)\t\(.status.sync.status)/\(.status.health.status)"' \
    | tee -a "$report"
  warn "platform-svc/learning-ai 미Healthy는 app 레포 의존 — 조건부"

  # 2) 메트릭 E2E (Prometheus targets)
  echo "## 메트릭 타깃" | tee -a "$report"
  kubectl -n monitoring exec sts/prometheus-kube-prometheus-stack-prometheus -c prometheus -- \
    wget -qO- 'http://localhost:9090/api/v1/targets?state=active' 2>/dev/null \
    | jq -r '.data.activeTargets[] | select(.labels.namespace|test("synapse-")) | "\(.labels.job)\t\(.health)"' \
    | tee -a "$report" || warn "타깃 조회 실패(앱 미배포/메트릭 미노출 가능)"

  # 3) 실 Slack 도달 (즉발 룰)
  echo "## Slack 도달" | tee -a "$report"
  verify_slack | tee -a "$report"

  ok "검증 리포트: $report"
}

verify_slack() {
  kubectl apply -f - <<'YAML'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: test-slack-delivery
  namespace: monitoring
  labels: {release: kube-prometheus-stack}
spec:
  groups:
    - name: test.slack
      rules:
        - alert: TestSlackDelivery
          expr: vector(1)
          for: 0s
          labels: {severity: critical}
          annotations: {summary: "bring-up --verify Slack 도달 테스트"}
YAML
  sleep 60
  kubectl -n monitoring exec sts/alertmanager-kube-prometheus-stack-alertmanager -c alertmanager -- \
    wget -qO- 'http://localhost:9093/api/v2/alerts?filter=alertname=TestSlackDelivery' 2>/dev/null \
    | jq -r '.[] | "firing=\(.status.state) receiver=\(.receivers[0].name)"' || echo "Alertmanager 조회 실패"
  kubectl -n monitoring delete prometheusrule test-slack-delivery
  echo "→ Slack 채널 #synapse-gitops에서 TestSlackDelivery 수신 여부를 눈으로 확인하세요."
}
```

> **wget 폴백**: Prometheus/Alertmanager 이미지는 busybox 기반이라 보통 `wget`이 있으나, 없으면(지난 세션 Loki처럼) exec 대신 임시 curl pod로 대체:
> ```bash
> kubectl -n monitoring run tmp-curl --rm -i --restart=Never --image=curlimages/curl --command -- \
>   curl -s 'http://kube-prometheus-stack-prometheus:9090/api/v1/targets?state=active'
> ```
> (Alertmanager는 `http://kube-prometheus-stack-alertmanager:9093/api/v2/alerts`)

- [ ] **Step 2: shellcheck (verify는 클러스터 필요 — dry 흐름만)**

Run: `shellcheck scripts/bring-up.sh`
Expected: 통과 (heredoc/`wget`은 클러스터 pod 내부 실행이라 정적 검증만).

- [ ] **Step 3: 커밋**

```bash
git add scripts/bring-up.sh
git commit -m "feat(scripts): --verify 모드 (staging/메트릭/Slack 즉발룰)"
```

### Task S7: `--destroy` 모드

**Files:**
- Modify: `scripts/bring-up.sh`

- [ ] **Step 1: destroy 함수 추가**

```bash
phase_destroy() {
  warn "terraform destroy — dev 인프라 전체 삭제(비용 차단). S3 state/DynamoDB lock은 유지."
  run "terraform -chdir=$TFDIR destroy -auto-approve -input=false"
}
```

- [ ] **Step 2: dry-run 확인**

Run: `bash scripts/bring-up.sh --destroy --dry-run`
Expected: `+ terraform -chdir=infra/aws/dev destroy ...` 1줄.

- [ ] **Step 3: shellcheck + 커밋**

```bash
shellcheck scripts/bring-up.sh
git add scripts/bring-up.sh
git commit -m "feat(scripts): --destroy 모드"
```

---

## Group D — 문서

### Task D1: 런북을 스크립트 1차 경로로 갱신

**Files:**
- Modify: `docs/runbooks/w2-session-bootstrap-runbook.md`

- [ ] **Step 1: 상단에 스크립트 경로 섹션 추가**

`docs/runbooks/w2-session-bootstrap-runbook.md`의 `## 전체 흐름` 바로 위에 삽입:
```markdown
## 빠른 경로 (권장): bring-up.sh

```bash
# 1) AWS 자격증명 + session-manager-plugin 준비
# 2) (최초 1회) AWS SM에 monitoring 시크릿 등록 — 실 Slack/Grafana
aws secretsmanager create-secret --name synapse/monitoring/grafana --region ap-northeast-2 \
  --secret-string '{"admin-user":"admin","admin-password":"<강한값>"}'
aws secretsmanager create-secret --name synapse/monitoring/alertmanager --region ap-northeast-2 \
  --secret-string '{"slack-webhook-url":"https://hooks.slack.com/services/..."}'

# 3) 한 명령 기동
bash scripts/bring-up.sh            # 전체
bash scripts/bring-up.sh --from eso # 중간 재개
bash scripts/bring-up.sh --verify   # W3 잔여 3항목 검증
bash scripts/bring-up.sh --destroy  # 비용 차단
```

스크립트가 실패하면 아래 수동 12단계를 fallback으로 사용하세요.
```

- [ ] **Step 2: staging 단계 갱신 (auto-sync 반영)**

`## Step 11. staging sync (선택)` 제목 아래 첫 줄에 추가:
```markdown
> **갱신(W3)**: staging ApplicationSet은 이제 **auto-sync**다. main 머지 시 자동 반영되며, 아래 manual patch는 즉시 sync가 필요한 경우에만 사용.
```

- [ ] **Step 3: 커밋**

```bash
git add docs/runbooks/w2-session-bootstrap-runbook.md
git commit -m "docs: 런북에 bring-up.sh 빠른 경로 + staging auto-sync 갱신"
```

---

## Group A — 수용

### Task A1: 정적 검증 (무비용)

**Files:** (검증)

- [ ] **Step 1: shellcheck 전체**

Run: `shellcheck scripts/bring-up.sh scripts/lib/eks-tunnel.sh`
Expected: 출력 없음(통과).

- [ ] **Step 2: dry-run 전체 흐름**

Run: `bash scripts/bring-up.sh --dry-run`
Expected: terraform→…→status 11개 phase 명령 라인 순서대로, exit 0.

- [ ] **Step 3: terraform validate**

Run: `terraform -chdir=infra/aws/dev validate`
Expected: `Success! The configuration is valid.`

### Task A2: 실 사이클 수용 테스트 (클러스터 1회 과금)

**Files:** (검증 — 사용자 승인 필요)

- [ ] **Step 1: 실 bring-up**

Run: `bash scripts/bring-up.sh`
Expected: 11개 phase 완료, `bring-up 완료` 메시지.

- [ ] **Step 2: 검증**

Run: `bash scripts/bring-up.sh --verify`
Expected: staging 표(조건부 허용) + 메트릭 타깃 + Slack 즉발룰 결과 + 리포트 파일.

- [ ] **Step 3: 멱등성 재실행**

Run: `bash scripts/bring-up.sh --from eks-auth`
Expected: 각 phase가 "이미 존재" skip/upgrade로 안전 통과.

- [ ] **Step 4: 정리**

Run: `bash scripts/bring-up.sh --destroy`
Expected: terraform destroy 완료, 비용 차단.

---

## 스펙 커버리지

| spec 섹션 | 태스크 |
|---|---|
| §2 실행모델(터널) | L1, S3 |
| §2 EBS CSI addon | T2, T3 |
| §2 argocd 제거 | T4 |
| §2 SG/OIDC output | T1, S2(sg), S4(oidc-fix) |
| §3 파일구조 | 전체 |
| §4 phase 1-11 | S1–S5 |
| §5 verify 3항목 | S6 |
| §6 에러/정리/테스트 | S1(set -e/trap), S7, A1, A2 |
