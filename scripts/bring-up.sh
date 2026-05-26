#!/usr/bin/env bash
# synapse-dev 멱등 bring-up: destroy된 상태 → dev/staging + observability
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-northeast-2}"
CLUSTER_NAME="${CLUSTER_NAME:-synapse-dev}"
ACCOUNT_ID="${ACCOUNT_ID:-963773969059}"
TFDIR="infra/aws/dev"
DRY_RUN=false
START_PHASE=""
MODE="bringup" # bringup | verify | destroy

log() { echo -e "\033[1;34m[*]\033[0m $*"; }
ok() { echo -e "\033[1;32m[OK]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERR]\033[0m $*" >&2; }
run() { if $DRY_RUN; then echo "+ $*"; else eval "$*"; fi; }

require() { command -v "$1" >/dev/null 2>&1 || {
  err "필수 도구 없음: $1"
  exit 1
}; }

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

# ─── phase 함수 ───────────────────────────────────────────────────────────
phase_terraform() {
  run "terraform -chdir=$TFDIR init -input=false"
  run "terraform -chdir=$TFDIR apply -auto-approve -input=false"
}

phase_eks_auth() {
  local mode
  mode=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" \
    --query cluster.accessConfig.authenticationMode --output text 2>/dev/null || echo "")
  if [ "$mode" = "API_AND_CONFIG_MAP" ] || [ "$mode" = "API" ]; then
    ok "auth mode 이미 $mode"
    return
  fi
  run "aws eks update-cluster-config --name $CLUSTER_NAME --region $AWS_REGION --access-config authenticationMode=API_AND_CONFIG_MAP"
  run "aws eks wait cluster-active --name $CLUSTER_NAME --region $AWS_REGION"
}

phase_access_entry() {
  local me
  me=$(aws sts get-caller-identity --query Arn --output text)
  if aws eks describe-access-entry --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION" \
    --principal-arn "$me" >/dev/null 2>&1; then
    ok "access entry 이미 존재: $me"
    return
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
      --group-id "$1" --protocol tcp --port "$2" --source-group "$eks_sg" 2>&1 |
      grep -q "already exists" && ok "SG $1:$2 규칙 이미 존재" || ok "SG $1:$2 추가"
  }
  if $DRY_RUN; then
    echo "+ SG ingress: rds:5432 redis:6379 msk:9094 os:443 from $eks_sg"
    return
  fi
  _sg_ingress "$rds" 5432
  _sg_ingress "$redis" 6379
  _sg_ingress "$msk" 9094
  _sg_ingress "$os" 443
}

# (phase 함수들은 후속 Task에서 추가)

main() {
  require aws
  require kubectl
  require helm
  require terraform
  require jq
  case "$MODE" in
  destroy)
    phase_destroy
    return
    ;;
  verify)
    source scripts/lib/eks-tunnel.sh
    trap tunnel_down EXIT
    tunnel_up
    verify_all
    return
    ;;
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

while [ $# -gt 0 ]; do
  case "$1" in
  --from)
    START_PHASE="$2"
    shift 2
    ;;
  --verify)
    MODE="verify"
    shift
    ;;
  --destroy)
    MODE="destroy"
    shift
    ;;
  --dry-run)
    DRY_RUN=true
    shift
    ;;
  --help)
    usage
    exit 0
    ;;
  *)
    err "알 수 없는 옵션: $1"
    usage
    exit 1
    ;;
  esac
done
main
