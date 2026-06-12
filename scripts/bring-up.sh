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
  --from <phase>   해당 phase부터 재개 (terraform|eks-auth|tunnel|argocd|eso|oidc-fix|alb-controller|kafka-config|kafka-topics|db-init|manifests|es-reindex|metrics-server|image-updater|observability|status)
  --to <phase>     해당 phase까지만 실행 (예: --to manifests = metrics-server/observability 제외 dev-only)
  --verify         bring-up 대신 W3 잔여 3항목 검증
  --destroy        terraform destroy (비용 차단)
  --dry-run        명령 출력만, 미실행
  --help           도움말
USAGE
}

PHASES=(terraform eks-auth tunnel argocd eso oidc-fix alb-controller kafka-config kafka-topics db-init manifests es-reindex metrics-server image-updater observability status)

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

phase_db_init() {
  # 후속 C(#166): 서비스 DB 5종을 dev + staging RDS에 멱등 생성(psql \gexec).
  # RDS는 private subnet → 클러스터 내 postgres Job으로 실행(bring-up 호스트 직접 도달 불가).
  # 자격: dev+staging 공통 master(username=output, password=TF_VAR_rds_password). 기본 db 'synapse' 접속.
  if $DRY_RUN; then echo "+ db-init: dev+staging RDS에 synapse_{platform,engagement,knowledge,learning,ai} 5종(postgres Job, \\gexec 멱등)"; return; fi
  local user pass dev_ep stg_ep
  user=$(terraform -chdir=$TFDIR output -raw rds_username)
  pass="${TF_VAR_rds_password:?phase_db_init: TF_VAR_rds_password 필요(RDS master)}"
  dev_ep=$(terraform -chdir=$TFDIR output -raw rds_endpoint)        # host:port
  stg_ep=$(terraform -chdir=$TFDIR output -raw rds_staging_endpoint)
  local dbs="synapse_platform synapse_engagement synapse_knowledge synapse_learning synapse_ai"
  # \gexec 멱등 SQL 생성
  # \gexec는 psql 메타명령 → -c(simple query)로는 미처리. SELECT 다음 줄에 \gexec, stdin으로 전달.
  local sql=""
  local db
  for db in $dbs; do
    sql+="SELECT 'CREATE DATABASE ${db}' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='${db}')"$'\n'"\\gexec"$'\n'
  done
  local ep host port
  for ep in "$dev_ep" "$stg_ep"; do
    host="${ep%%:*}"
    port="${ep##*:}"
    [ "$host" = "$port" ] && port=5432
    log "db-init → $host"
    printf '%s' "$sql" | kubectl -n synapse-dev run "db-init-${host%%.*}" --rm -i --restart=Never \
      --image=postgres:16 --timeout=180s \
      --env="PGPASSWORD=$pass" --command -- \
      psql "host=$host port=$port user=$user dbname=synapse sslmode=require" -v ON_ERROR_STOP=1 \
      || warn "db-init $host 실패(RDS 미기동/자격 가능) — 재시도: --from db-init"
  done
  ok "DB 5종 적용(dev+staging)"
}

phase_kafka_topics() {
  # 후속 C(#166): MSK 토픽을 클러스터 내 apache/kafka Job(SSL)으로 멱등 생성(--if-not-exists).
  # MSK private subnet → 클러스터 내부 실행만 도달. 토픽 정본 = infra/kafka/topics.txt(ConfigMap 적재).
  # 무인증 TLS-only(MSK SSL 서버인증) → client.properties=security.protocol=SSL.
  # #199: 공유 MSK 환경 교차 격리 — 각 베이스 토픽을 ""(레거시)·dev.·staging.·prod. 4종 프리픽스로 생성.
  if $DRY_RUN; then echo "+ kafka-topics: infra/kafka/topics.txt × {레거시,dev.,staging.,prod.} 프리픽스(apache/kafka:3.9.0 Job, SSL, --if-not-exists, RF=2)"; return; fi
  local brokers
  brokers=$(terraform -chdir=$TFDIR output -raw msk_bootstrap_brokers_tls)
  # 토픽 리스트를 ConfigMap으로 적재(파일 단일 출처)
  kubectl create configmap kafka-topics-list -n synapse-dev \
    --from-file=topics.txt=infra/kafka/topics.txt --dry-run=client -o yaml | kubectl apply -f -
  # Job: client.properties + 각 토픽 --if-not-exists 생성 (CRLF 안전: \r 제거)
  kubectl -n synapse-dev delete job kafka-topics-init --ignore-not-found
  kubectl apply -f - <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: kafka-topics-init
  namespace: synapse-dev
spec:
  backoffLimit: 2
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: kafka-topics
          image: apache/kafka:3.9.0
          env:
            - name: BROKERS
              value: "$brokers"
          command: ["/bin/sh", "-c"]
          args:
            - |
              set -eu
              echo "security.protocol=SSL" > /tmp/client.properties
              BIN=/opt/kafka/bin/kafka-topics.sh
              # #199: dev·staging이 공유 MSK를 같은 컨슈머그룹으로 소비 → 파티션 환경 교차 분산(이벤트 누수).
              # 토픽명에 환경 프리픽스(dev./staging./prod.)로 완전 격리. 빈 프리픽스(레거시 미접두)는
              # 서비스가 KAFKA_TOPIC_PREFIX를 채택하기 전까지 마이그레이션 기간 병존(이후 정리).
              for PFX in "" "dev." "staging." "prod."; do
              while IFS= read -r line || [ -n "\$line" ]; do
                t=\$(printf '%s' "\$line" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*\$//')
                case "\$t" in ''|\#*) continue;; esac
                full="\${PFX}\${t}"
                echo "Creating \$full"
                "\$BIN" --bootstrap-server "\$BROKERS" --command-config /tmp/client.properties \
                  --create --if-not-exists --topic "\$full" \
                  --partitions 3 --replication-factor 2 \
                  --config min.insync.replicas=2 --config retention.ms=604800000
              done < /etc/kafka-topics/topics.txt
              done
              echo "--- topics ---"
              "\$BIN" --bootstrap-server "\$BROKERS" --command-config /tmp/client.properties --list
          volumeMounts:
            - name: topics
              mountPath: /etc/kafka-topics
      volumes:
        - name: topics
          configMap:
            name: kafka-topics-list
YAML
  kubectl -n synapse-dev wait --for=condition=complete job/kafka-topics-init --timeout=180s \
    || warn "kafka-topics-init 미완료(MSK 미기동/SG 가능) — 로그: kubectl -n synapse-dev logs job/kafka-topics-init; 재시도: --from kafka-topics"
  ok "MSK 토픽 적용(멱등, 환경 프리픽스 레거시+dev/staging/prod)"
}

phase_manifests() {
  # gp3 기본 StorageClass 선행(ES·observability 등 PVC 의존). 없으면 PVC가 unbound로 Pending → 워크로드 미기동.
  run "kubectl apply -f infra/monitoring/storageclass-gp3.yaml"
  run "kubectl patch storageclass gp2 -p '{\"metadata\":{\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"false\"}}}' 2>/dev/null || true"
  run "kubectl apply -f infra/external-secrets/cluster-secret-store.yaml"
  run "kubectl apply -f argocd/projects.yaml"
  run "kubectl apply -f argocd/applicationset.yaml"
  run "kubectl apply -f argocd/applicationset-staging.yaml"
  # 워크로드 앱(ApplicationSet)이 의존하는 infra standalone App. ES/schema-registry는
  # ApplicationSet 목록에 없어 별도 적용 필요(미적용 시 knowledge=ES없음·avro 깨짐, es-reindex NotFound).
  run "kubectl apply -f argocd/elasticsearch.yaml"
  run "kubectl apply -f argocd/schema-registry.yaml"
  if $DRY_RUN; then return; fi
  kubectl wait --for=condition=Ready clustersecretstore/aws-secrets-manager --timeout=120s || warn "ClusterSecretStore 미Ready"
  kubectl -n synapse-dev wait --for=condition=Ready externalsecret --all --timeout=180s || warn "일부 ExternalSecret 미Synced"
}

phase_es_reindex() {
  # #174: nori 커스텀 이미지 반영 보장 + notes-v1을 nori로 정합화.
  # ephemeral 클러스터(매 윈도우 새 ES)에선 보통 no-op지만, EBS 유지/이전 윈도우 잔재
  # (nori 없는 notes-v1)를 방어한다. ES는 xpack.security 비활성이라 :9200 직접 접근(무인증).
  local ns="synapse-dev" es_pod mapping i
  if $DRY_RUN; then echo "+ es-reindex: nori 플러그인 가드 + stale notes-v1 삭제"; return; fi

  # manifests 직후엔 ArgoCD reconcile이 비동기라 ES StatefulSet이 아직 없을 수 있다(레이스).
  # 생성될 때까지 대기, 끝내 없으면(앱 미배포) graceful skip — 윈도우 전체를 막지 않는다.
  for i in $(seq 1 30); do
    kubectl -n "$ns" get statefulset/elasticsearch >/dev/null 2>&1 && break
    [ "$i" = 30 ] && { warn "ES StatefulSet 미생성(ArgoCD sync 지연) — es-reindex 건너뜀(verify에서 재확인)"; return 0; }
    sleep 10
  done
  run "kubectl -n $ns rollout status statefulset/elasticsearch --timeout=300s"
  es_pod=$(kubectl -n $ns get pod -l app.kubernetes.io/name=elasticsearch -o jsonpath='{.items[0].metadata.name}')

  # 1) nori 플러그인 가드 — 없으면 stock 이미지(synapse/elasticsearch:nori-9.2.1 아님) → 즉시 실패.
  #    라이브에서 잘못된 이미지로 조용히 검색 깨지는 것을 차단(#174 근본원인).
  if ! kubectl -n "$ns" exec "$es_pod" -- bin/elasticsearch-plugin list 2>/dev/null | grep -q analysis-nori; then
    err "ES에 analysis-nori 미설치 — statefulset 이미지가 nori 커스텀인지 확인(#174, shared#53)"
    exit 1
  fi
  ok "ES analysis-nori 설치 확인"

  # 2) notes-v1이 존재하나 nori 매핑이 아니면(이전 윈도우 잔재) 삭제 → 다음 인덱싱/검색에서 nori로 재생성.
  #    존재 판정은 HTTP 상태코드로 — 404 본문에 "index":"notes-v1"이 들어가 _mapping 본문 grep은 오탐.
  #    ES 이미지 curl 의존 회피 위해 임시 curl pod 사용(verify_all과 동일 패턴).
  local code
  code=$(kubectl -n "$ns" run tmp-es-head --rm -i --restart=Never --image=curlimages/curl --command --timeout=60s -- \
    curl -s -o /dev/null -w '%{http_code}' "http://elasticsearch:9200/notes-v1" 2>/dev/null | tr -dc '0-9')
  if [ "$code" = "200" ]; then
    mapping=$(kubectl -n "$ns" run tmp-es-mapping --rm -i --restart=Never --image=curlimages/curl --command --timeout=60s -- \
      curl -s "http://elasticsearch:9200/notes-v1/_mapping" 2>/dev/null || echo "")
    if echo "$mapping" | grep -q nori; then
      ok "notes-v1 이미 nori 적용 — 유지"
    else
      warn "notes-v1 존재하나 nori 미적용(stale) → 삭제(다음 인덱싱/검색에서 nori로 재생성)"
      kubectl -n "$ns" run tmp-es-del --rm -i --restart=Never --image=curlimages/curl --command --timeout=60s -- \
        curl -s -X DELETE "http://elasticsearch:9200/notes-v1" >/dev/null 2>&1 || true
    fi
  else
    log "notes-v1 미존재(HTTP ${code:-?}) — 첫 인덱싱/검색에서 knowledge가 nori로 생성(ephemeral 정상)"
  fi
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
  # gp3 StorageClass는 phase_manifests로 선이동(ES 등 PVC가 더 일찍 필요).
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
  run "kubectl apply -f infra/monitoring/servicemonitor-synapse.yaml -f infra/monitoring/prometheus-rules.yaml -f infra/monitoring/grafana-dashboard-synapse.yaml -f infra/monitoring/grafana-dashboard-apps.yaml"
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

  echo "## ES nori / 검색 (#174)" | tee -a "$report"
  verify_search | tee -a "$report"

  echo "## Slack 도달" | tee -a "$report"
  verify_slack | tee -a "$report"

  ok "검증 리포트: $report"
}

verify_search() {
  local ns="synapse-dev" es_pod mapping
  es_pod=$(kubectl -n "$ns" get pod -l app.kubernetes.io/name=elasticsearch -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [ -z "$es_pod" ]; then echo "ES pod 없음 — 검증 불가"; return; fi
  # 1) nori 플러그인 설치(#174 근본원인 회귀 가드)
  if kubectl -n "$ns" exec "$es_pod" -- bin/elasticsearch-plugin list 2>/dev/null | grep -q analysis-nori; then
    echo "analysis-nori: 설치됨 ✅"
  else
    echo "analysis-nori: 미설치 ❌ (stock 이미지 — statefulset 이미지 확인)"
  fi
  # 2) notes-v1 nori 매핑(존재 시) — ES xpack 비활성이라 무인증 조회.
  #    존재 판정은 HTTP 상태코드로(404 본문에 "notes-v1" 포함되어 _mapping grep 오탐 방지).
  local code
  code=$(kubectl -n "$ns" run tmp-verify-eshead --rm -i --restart=Never --image=curlimages/curl --command --timeout=60s -- \
    curl -s -o /dev/null -w '%{http_code}' "http://elasticsearch:9200/notes-v1" 2>/dev/null | tr -dc '0-9')
  if [ "$code" = "200" ]; then
    mapping=$(kubectl -n "$ns" run tmp-verify-esmap --rm -i --restart=Never --image=curlimages/curl --command --timeout=60s -- \
      curl -s "http://elasticsearch:9200/notes-v1/_mapping" 2>/dev/null || echo "")
    echo "notes-v1: $(echo "$mapping" | grep -q nori && echo 'nori 적용 ✅' || echo 'nori 미적용 ❌(stale)')"
  else
    echo "notes-v1: 미생성(HTTP ${code:-?}) — 앱 활동/인증검색 전 정상(첫 연산에서 nori로 생성)"
  fi
  # 3) 검색 API 200 E2E는 @CurrentUserAuth(인증) 필요 → 게이트웨이 토큰으로 수동 확인.
  echo "→ 인증 검색 E2E: 게이트웨이 경유 \`GET /api/v1/notes/search?q=...\` 200 수동 확인(토큰 필요)."
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

# destroy 전 orphan LB 선정리.
# aws-load-balancer-controller가 Ingress(infra/ingress/*, nipio/* — 전부 internet-facing)/
# LoadBalancer-Service로 만든 ALB·ENI·공인IP는 terraform state 밖이다. 곧장 terraform destroy
# 하면 이 orphan 때문에 subnet "DependencyViolation"·IGW "mapped public address(es)"로
# ~20분 행 끝에 실패한다(2026-06-10 재현, destroy.out). k8s LB 객체 선삭제 + ELB 소멸 대기로 차단.
predestroy_lb_cleanup() {
  local vpc=""
  vpc=$(terraform -chdir=$TFDIR output -raw vpc_id 2>/dev/null || true)
  if [ -z "$vpc" ]; then
    warn "vpc_id 미확인(state 비어있음?) — LB 선정리 생략"
    return 0
  fi
  log "destroy 선정리: VPC $vpc 의 ALB/NLB 제거(orphan ENI/EIP 차단)"

  # 1) 클러스터 접근(private endpoint → SSM 터널). 실패해도 AWS 레벨 대기로 폴백.
  if $DRY_RUN; then
    echo "+ tunnel_up; kubectl delete ingress/svc(LoadBalancer); ELB 소멸 대기; orphan ENI reap"
    return 0
  fi
  if source scripts/lib/eks-tunnel.sh && tunnel_up; then
    # Ingress/LoadBalancer-Service 삭제 → 컨트롤러가 ALB/NLB 디프로비저닝(finalizer로 동기 대기).
    run "kubectl delete ingress -A --all --ignore-not-found --timeout=180s || true"
    run "kubectl delete svc -A --field-selector spec.type=LoadBalancer --ignore-not-found --timeout=180s || true"
    tunnel_down
  else
    warn "터널/kubectl 도달 실패 — k8s LB 객체 선삭제 생략(AWS 레벨 대기로 진행)"
    tunnel_down
  fi

  # 2) ELB(v2/classic)가 VPC에서 완전 삭제될 때까지 대기(컨트롤러 비동기 백스톱, 최대 ~5분).
  local i n
  for i in $(seq 1 20); do
    n=$( {
      aws elbv2 describe-load-balancers --region "$AWS_REGION" \
        --query "length(LoadBalancers[?VpcId=='$vpc'])" --output text 2>/dev/null || echo 0
      aws elb describe-load-balancers --region "$AWS_REGION" \
        --query "length(LoadBalancerDescriptions[?VPCId=='$vpc'])" --output text 2>/dev/null || echo 0
    } | awk '{s+=$1} END{print s+0}')
    [ "$n" = "0" ] && { ok "VPC LB 0개 — destroy 진행"; break; }
    log "남은 LB ${n}개 — 컨트롤러 디프로비저닝 대기(${i}/20)"
    sleep 15
  done

  # 3) 폴백: 남은 미부착(available) ELB ENI 강제 삭제(컨트롤러 다운/이미 삭제 케이스).
  local eni
  for eni in $(aws ec2 describe-network-interfaces --region "$AWS_REGION" \
    --filters "Name=vpc-id,Values=$vpc" "Name=status,Values=available" \
    --query "NetworkInterfaces[?starts_with(Description, 'ELB ')].NetworkInterfaceId" \
    --output text 2>/dev/null || true); do
    warn "orphan ELB ENI 삭제: $eni"
    aws ec2 delete-network-interface --region "$AWS_REGION" --network-interface-id "$eni" 2>/dev/null || true
  done
}

phase_destroy() {
  warn "terraform destroy — dev 인프라 전체 삭제(비용 차단). S3 state/DynamoDB lock은 유지."
  predestroy_lb_cleanup
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
