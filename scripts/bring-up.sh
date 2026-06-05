#!/usr/bin/env bash
# synapse-dev 멱등 bring-up: destroy된 상태 → dev/staging + observability
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-northeast-2}"
CLUSTER_NAME="${CLUSTER_NAME:-synapse-dev}"
ACCOUNT_ID="${ACCOUNT_ID:-963773969059}"
TFDIR="infra/aws/dev"
DRY_RUN=false
START_PHASE=""
END_PHASE=""
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
  --from <phase>   해당 phase부터 재개 (terraform|eks-auth|tunnel|argocd|eso|oidc-fix|alb-controller|kafka-config|manifests|metrics-server|image-updater|observability|status)
  --to <phase>     해당 phase까지만 실행 (예: --to manifests = metrics-server/observability 제외 dev-only)
  --verify         bring-up 대신 W3 잔여 3항목 검증
  --destroy        terraform destroy (비용 차단)
  --dry-run        명령 출력만, 미실행
  --help           도움말
USAGE
}

PHASES=(terraform eks-auth tunnel argocd eso oidc-fix alb-controller kafka-config manifests metrics-server image-updater observability status)

# ─── phase 함수 ───────────────────────────────────────────────────────────
phase_terraform() {
  if $DRY_RUN; then
    echo "+ terraform init + apply (인프라 + EBS CSI/IRSA)"
    return
  fi
  if [ ! -f "$TFDIR/terraform.tfvars" ] && [ -z "${TF_VAR_rds_password:-}" ]; then
    err "$TFDIR/terraform.tfvars 없음(gitignored secrets: rds_password/redis_auth_token)."
    err "  → 메인 체크아웃에서 복사하거나 TF_VAR_rds_password/TF_VAR_redis_auth_token 환경변수 설정."
    exit 1
  fi
  run "terraform -chdir=$TFDIR init -input=false"
  run "terraform -chdir=$TFDIR apply -auto-approve -input=false"
}

phase_eks_auth() {
  if $DRY_RUN; then echo "+ eks-auth: authenticationMode=API_AND_CONFIG_MAP (필요시)"; return; fi
  local mode
  mode=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" \
    --query cluster.accessConfig.authenticationMode --output text 2>/dev/null || echo "")
  if [ "$mode" = "API_AND_CONFIG_MAP" ] || [ "$mode" = "API" ]; then
    ok "auth mode 이미 $mode"
    return
  fi
  run "aws eks update-cluster-config --name $CLUSTER_NAME --region $AWS_REGION --access-config authenticationMode=API_AND_CONFIG_MAP"
  # cluster-active waiter는 auth-config 업데이트 완료를 기다리지 않음 → authenticationMode를 직접 폴링
  local i m
  for i in $(seq 1 30); do
    m=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" \
      --query cluster.accessConfig.authenticationMode --output text 2>/dev/null || echo "")
    if [ "$m" = "API_AND_CONFIG_MAP" ] || [ "$m" = "API" ]; then
      ok "auth mode → $m"
      return
    fi
    sleep 10
  done
  err "auth mode 변경이 시간 내 완료 안 됨"
  exit 1
}

phase_tunnel() {
  source scripts/lib/eks-tunnel.sh
  trap tunnel_down EXIT
  if $DRY_RUN; then
    echo "+ tunnel_up (SSM 포트포워딩 + 터널 kubeconfig)"
    return
  fi
  tunnel_up && ok "터널 연결, kubectl 도달"
}

phase_argocd() {
  run "kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -"
  # --force-conflicts: 재실행 시 --insecure 패치(kubectl-patch 매니저)와의 field 충돌 방지
  run "kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
  if $DRY_RUN; then
    echo "+ argocd-server --insecure patch (없을 때만)"
  elif ! kubectl -n argocd get deploy argocd-server -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null | grep -q -- '--insecure'; then
    kubectl -n argocd patch deploy argocd-server --type=json -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--insecure"}]'
  fi
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

phase_oidc_fix() {
  if $DRY_RUN; then echo "+ oidc-fix: ESO role trust policy OIDC ID 비교/갱신"; return; fi
  local cur trust
  cur=$(terraform -chdir=$TFDIR output -raw eks_oidc_id)
  trust=$(aws iam get-role --role-name synapse-dev-eso-role \
    --query 'Role.AssumeRolePolicyDocument' --output json 2>/dev/null | jq -r '.Statement[0].Principal.Federated' | awk -F'/' '{print $NF}')
  if [ "$cur" = "$trust" ]; then
    ok "ESO role OIDC 일치 ($cur)"
    return
  fi
  warn "ESO role OIDC 불일치: trust=$trust, 현재=$cur → 갱신"
  local pol="{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Federated\":\"arn:aws:iam::${ACCOUNT_ID}:oidc-provider/oidc.eks.${AWS_REGION}.amazonaws.com/id/${cur}\"},\"Action\":\"sts:AssumeRoleWithWebIdentity\",\"Condition\":{\"StringEquals\":{\"oidc.eks.${AWS_REGION}.amazonaws.com/id/${cur}:aud\":\"sts.amazonaws.com\",\"oidc.eks.${AWS_REGION}.amazonaws.com/id/${cur}:sub\":\"system:serviceaccount:external-secrets:external-secrets\"}}}]}"
  run "aws iam update-assume-role-policy --role-name synapse-dev-eso-role --policy-document '$pol'"
  run "kubectl -n external-secrets rollout restart deploy external-secrets"
}

phase_alb_controller() {
  # ALB Ingress(infra/ingress/*, infra/ingress/nipio/*) 프로비저닝용 aws-load-balancer-controller.
  # IRSA: synapse-dev-alb-controller-role (alb-controller-irsa.tf). (W5: 미부트스트랩 → #121 차단 해소)
  if $DRY_RUN; then echo "+ alb-controller: helm install aws-load-balancer-controller (IRSA + vpcId)"; return; fi
  local vpc
  vpc=$(terraform -chdir=$TFDIR output -raw vpc_id)
  run "helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true"
  run "helm repo update eks >/dev/null"
  helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system \
    --set clusterName="$CLUSTER_NAME" \
    --set serviceAccount.create=true \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::${ACCOUNT_ID}:role/synapse-dev-alb-controller-role" \
    --set region="$AWS_REGION" \
    --set vpcId="$vpc" \
    --wait --timeout 5m
  run "kubectl -n kube-system rollout status deploy/aws-load-balancer-controller --timeout=180s"
}

phase_kafka_config() {
  # #88: kafka-brokers ConfigMap을 3개 ns에 선생성 (앱 배포 전 KAFKA_BROKERS 주입원).
  # bring-up은 kubectl 스타일 — k8s-kafka-config terraform 모듈과 동일 리소스(터널 kubeconfig).
  if $DRY_RUN; then echo "+ kafka-config: ns×3 + kafka-brokers ConfigMap (terraform output 브로커 사용)"; return; fi
  local brokers
  brokers=$(terraform -chdir=$TFDIR output -raw msk_bootstrap_brokers_tls)
  for ns in synapse-dev synapse-staging synapse-prod; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
    kubectl create configmap kafka-brokers -n "$ns" \
      --from-literal=KAFKA_BROKERS="$brokers" --dry-run=client -o yaml | kubectl apply -f -
  done
  ok "kafka-brokers ConfigMap 3 ns 적용"
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

phase_metrics_server() {
  # HPA 선행 조건: metrics-server 없이는 HPA TARGETS가 <unknown>을 반환해 스케일링 불가.
  # prod overlays(apps/*/overlays/prod/hpa.yaml) 적용 전 필수. (WS4-2)
  run "kubectl apply -f infra/k8s-addons/metrics-server.yaml"
  run "kubectl -n kube-system rollout status deploy/metrics-server --timeout=180s" \
    || warn "metrics-server rollout timeout — HPA TARGETS may show <unknown>; 재실행: --from metrics-server"
}

phase_image_updater() {
  if $DRY_RUN; then
    echo "+ image-updater: 컨트롤러 설치 + ECR IRSA(annotate) + git write-back 자격 확인"
    return
  fi
  kubectl apply -n argocd --server-side --force-conflicts \
    -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/v0.15.2/manifests/install.yaml
  kubectl -n argocd annotate sa argocd-image-updater \
    eks.amazonaws.com/role-arn=arn:aws:iam::${ACCOUNT_ID}:role/synapse-dev-image-updater-role --overwrite
  # #122: ECR 인증 — registries.conf(ext 스크립트) + ecr-login.sh를 executable(/app/scripts, 0555)로 마운트.
  #   IRSA가 ECR read 권한 제공. (W5: registries 자격 미설정으로 태그 조회 실패 → 해소)
  run "kubectl apply --server-side --force-conflicts -f argocd/image-updater-ecr-auth.yaml"
  kubectl -n argocd patch deploy argocd-image-updater --type=strategic -p \
    '{"spec":{"template":{"spec":{"volumes":[{"name":"ecr-auth","configMap":{"name":"argocd-image-updater-ecr-auth","defaultMode":365}}],"containers":[{"name":"argocd-image-updater","volumeMounts":[{"name":"ecr-auth","mountPath":"/app/scripts"}]}]}}}}'
  # git write-back용 ArgoCD repo 자격 — AWS SM(synapse/gitops/git-token) → ESO → repository 시크릿
  run "kubectl apply -f infra/external-secrets/argocd-repo-externalsecret.yaml"
  if ! aws secretsmanager describe-secret --secret-id synapse/gitops/git-token --region "$AWS_REGION" >/dev/null 2>&1; then
    warn "AWS SM 시크릿 없음: synapse/gitops/git-token → git write-back 불가. PAT 등록 필요(S6 E2E)."
  fi
  kubectl -n argocd rollout restart deploy argocd-image-updater
  kubectl -n argocd rollout status deploy argocd-image-updater --timeout=180s
}

phase_observability() {
  run "kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -"
  run "kubectl apply -f infra/monitoring/storageclass-gp3.yaml"
  run "kubectl patch storageclass gp2 -p '{\"metadata\":{\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"false\"}}}' 2>/dev/null || true"
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
  if $DRY_RUN; then
    echo "+ status 출력"
    return
  fi
  echo "--- ArgoCD apps ---"
  kubectl -n argocd get applications 2>/dev/null || true
  echo "--- synapse-dev pods ---"
  kubectl -n synapse-dev get pods 2>/dev/null || true
  echo "--- synapse-staging pods ---"
  kubectl -n synapse-staging get pods 2>/dev/null || true
  echo "--- monitoring pods ---"
  kubectl -n monitoring get pods 2>/dev/null || true
}

verify_all() {
  local report
  report="verification-$(date +%Y%m%d-%H%M).md"
  {
    echo "# Bring-up 검증 $(date -u +%FT%TZ)"
    echo
  } >"$report"

  echo "## staging Healthy" | tee -a "$report"
  kubectl -n argocd get applications -o json |
    jq -r '.items[] | select(.metadata.name|test("staging")) | "\(.metadata.name)\t\(.status.sync.status)/\(.status.health.status)"' |
    tee -a "$report"
  warn "platform-svc/learning-ai 미Healthy는 app 레포 의존 — 조건부"

  echo "## 메트릭 타깃" | tee -a "$report"
  # Prometheus 이미지에 wget/curl이 없어 exec 불가 → 임시 curl pod로 API 조회
  kubectl -n monitoring run tmp-verify-targets --rm -i --restart=Never --image=curlimages/curl --command --timeout=90s -- \
    curl -s 'http://kube-prometheus-stack-prometheus:9090/api/v1/targets?state=active' 2>/dev/null |
    jq -r '.data.activeTargets[] | select(.labels.namespace|test("synapse-")) | "\(.labels.job)\t\(.health)"' |
    tee -a "$report" || warn "타깃 조회 실패(앱 미배포/메트릭 미노출 가능)"

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
  kubectl -n monitoring run tmp-verify-am --rm -i --restart=Never --image=curlimages/curl --command --timeout=90s -- \
    curl -s 'http://kube-prometheus-stack-alertmanager:9093/api/v2/alerts?filter=alertname=TestSlackDelivery' 2>/dev/null |
    jq -r '.[] | "state=\(.status.state) receiver=\(.receivers[0].name)"' || echo "Alertmanager 조회 실패"
  kubectl -n monitoring delete prometheusrule test-slack-delivery
  echo "→ Slack 채널 #synapse-gitops에서 TestSlackDelivery 수신 여부를 눈으로 확인하세요."
}

phase_destroy() {
  warn "terraform destroy — dev 인프라 전체 삭제(비용 차단). S3 state/DynamoDB lock은 유지."
  run "terraform -chdir=$TFDIR destroy -auto-approve -input=false"
}

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
    [ "$p" = "$END_PHASE" ] && {
      ok "phase '$END_PHASE'까지 완료"
      return
    }
  done
  ok "bring-up 완료. 검증: bring-up.sh --verify"
}

while [ $# -gt 0 ]; do
  case "$1" in
  --from)
    START_PHASE="$2"
    shift 2
    ;;
  --to)
    END_PHASE="$2"
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
