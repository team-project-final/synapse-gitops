#!/usr/bin/env bash
# ArgoCD 부트스트랩 1회 실행 스크립트 (W1 옵션 2)
# 전제: terraform apply 완료, kubectl/aws/argocd/jq/openssl 사용 가능

set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-northeast-2}"
CLUSTER_NAME="${CLUSTER_NAME:-synapse-dev}"
SECRET_NAME="${SECRET_NAME:-synapse/argocd/admin}"
NAMESPACE="argocd"

log()  { echo -e "\033[1;34m[*]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[OK]\033[0m $*"; }
err()  { echo -e "\033[1;31m[ERR]\033[0m $*" >&2; }

require() {
  command -v "$1" >/dev/null 2>&1 || { err "필수 도구 없음: $1"; exit 1; }
}

log "1/8 사전 도구 점검"
require aws
require kubectl
require argocd
require jq
require openssl
aws sts get-caller-identity >/dev/null
ok "도구 OK"

log "2/8 kubeconfig 갱신"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null
kubectl get nodes >/dev/null
ok "kubeconfig OK"

log "3/8 ArgoCD pod readiness 대기 (최대 10분)"
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=argocd-server \
  -n "$NAMESPACE" --timeout=600s
ok "argocd-server Ready"

log "4/8 NLB 호스트 추출 (최대 10분)"
NLB_HOST=""
for i in $(seq 1 60); do
  NLB_HOST=$(kubectl get svc argocd-server -n "$NAMESPACE" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [ -n "$NLB_HOST" ]; then break; fi
  sleep 10
done
if [ -z "$NLB_HOST" ]; then
  err "NLB 호스트 추출 실패 — kubectl get svc argocd-server -n argocd 확인"
  exit 1
fi
ok "NLB: $NLB_HOST"

log "5/8 admin 비번 회전"
INITIAL=$(kubectl get secret argocd-initial-admin-secret -n "$NAMESPACE" \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)

if [ -z "$INITIAL" ]; then
  log "  초기 secret 없음 — Secrets Manager에서 기존 비번 조회"
  CURRENT=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" --region "$AWS_REGION" \
    --query SecretString --output text 2>/dev/null | jq -r '.password' || true)
  if [ -z "$CURRENT" ]; then
    err "초기 secret도, Secrets Manager 항목도 없음 — 수동 복구 필요"
    exit 1
  fi
  ok "이미 회전됨, Secrets Manager 비번 사용"
  argocd login "$NLB_HOST" --username admin --password "$CURRENT" --insecure --grpc-web
else
  NEW=$(openssl rand -base64 24)
  argocd login "$NLB_HOST" --username admin --password "$INITIAL" --insecure --grpc-web
  argocd account update-password \
    --account admin \
    --current-password "$INITIAL" \
    --new-password "$NEW"
  ok "비번 회전 완료"

  log "  AWS Secrets Manager 저장"
  PAYLOAD=$(jq -n --arg pw "$NEW" --arg host "$NLB_HOST" \
    '{password:$pw, host:$host, username:"admin"}')
  if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    aws secretsmanager put-secret-value \
      --secret-id "$SECRET_NAME" --secret-string "$PAYLOAD" --region "$AWS_REGION" >/dev/null
  else
    aws secretsmanager create-secret \
      --name "$SECRET_NAME" --secret-string "$PAYLOAD" --region "$AWS_REGION" \
      --description "ArgoCD admin password for synapse-dev cluster" >/dev/null
  fi
  ok "Secrets Manager 저장: $SECRET_NAME"

  log "  초기 secret 삭제"
  kubectl delete secret argocd-initial-admin-secret -n "$NAMESPACE" --ignore-not-found
fi

log "6/8 AppProject 적용"
kubectl apply -f argocd/projects.yaml
ok "AppProject 적용"

log "7/8 RBAC + Notifications ConfigMap 적용"
kubectl apply -f argocd/bootstrap/
ok "ConfigMap 적용"

log "8/8 ApplicationSet 적용 + 검증"
kubectl apply -f argocd/applicationset.yaml
sleep 5
APP_COUNT=$(argocd app list -o name | wc -l | tr -d ' ')
if [ "$APP_COUNT" -lt 5 ]; then
  err "Application 등록 부족: $APP_COUNT (기대 5)"
  argocd app list
  exit 1
fi
ok "Application $APP_COUNT 개 등록 확인"

echo ""
echo "================================================================"
echo " ArgoCD 부트스트랩 완료"
echo "================================================================"
echo " UI: https://$NLB_HOST"
echo " 비번 조회:"
echo "   aws secretsmanager get-secret-value --secret-id $SECRET_NAME \\"
echo "     --region $AWS_REGION --query SecretString --output text | jq -r .password"
echo ""
echo " 등록된 Application:"
argocd app list -o wide || true
echo "================================================================"
