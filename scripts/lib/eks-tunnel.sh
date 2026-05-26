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
