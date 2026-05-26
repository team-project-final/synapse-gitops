#!/usr/bin/env bash
set -euo pipefail
# Synapse MSA를 minikube에 기동. 형제 레포가 ../synapse-* 에 클론되어 있어야 함.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"          # synapse-gitops
SIB="$(cd "$ROOT/.." && pwd)"                      # team-project-final

echo "==> 1) minikube 시작"
minikube status >/dev/null 2>&1 || minikube start --driver=docker --memory=8192 --cpus=4
# 메모리 8GB 권장: 인프라(opensearch/kafka 등) + JVM 서비스 4개가 동시에 떠서 4GB로는 liveness가 파드를 죽일 수 있음.

echo "==> 2) 이미지 빌드 + minikube 적재 (한 이미지가 실패해도 계속 — 해당 파드만 ImagePullBackOff)"
build_docker() { # <name> <context>
  if docker build -t "$1:local" "$2"; then
    minikube image load "$1:local" || echo "WARN: $1:local 적재 실패"
  else
    echo "WARN: $1 이미지 빌드 실패 — 건너뜀(해당 파드는 ImagePullBackOff). 아래 '알려진 이미지 빌드 이슈' 참고."
  fi
}
build_docker synapse-gateway        "$SIB/synapse-gateway"
build_docker synapse-platform-svc   "$SIB/synapse-platform-svc"
build_docker synapse-engagement-svc "$SIB/synapse-engagement-svc"
build_docker synapse-knowledge-svc  "$SIB/synapse-knowledge-svc"
build_docker synapse-learning-ai    "$SIB/synapse-learning-svc/learning-ai"
# learning-card: Dockerfile 없음 → Spring Boot bootBuildImage 사용
{ ( cd "$SIB/synapse-learning-svc/learning-card" && ./gradlew bootBuildImage --imageName=synapse-learning-card:local ) \
  && minikube image load synapse-learning-card:local ; } \
  || echo "WARN: learning-card 이미지 빌드 실패 — 건너뜀(파드 ImagePullBackOff)."

# 알려진 이미지 빌드 이슈(업스트림): learning-ai Dockerfile은 app/ 복사 전에 pip install .을 실행해 실패하고,
# learning-card는 Dockerfile이 없어 bootBuildImage에 의존합니다. 두 서비스 이미지가 없으면 해당 파드만 ImagePullBackOff이며 나머지는 정상 동작합니다.

echo "==> 3) 매니페스트 적용"
kubectl apply -k "$ROOT/local-k8s"

echo "==> 4) 롤아웃 대기"
kubectl -n synapse-local rollout status deploy/postgres --timeout=120s
for d in platform-svc engagement-svc knowledge-svc learning-card learning-ai gateway; do
  kubectl -n synapse-local rollout status "deploy/$d" --timeout=300s || true
done

cat <<'EOF'
==> 완료. 접근(별도 터미널에서 port-forward):
  kubectl -n synapse-local port-forward svc/gateway       8080:80   # 메인 진입점
  kubectl -n synapse-local port-forward svc/learning-ai   8000:80
  # (직접 접근이 필요하면) svc/platform-svc·engagement-svc·knowledge-svc·learning-card 도 :80
그 다음: Gateway 경유 curl http://localhost:8080/api/platform/actuator/health , 브라우저로 http://localhost:8000/docs
상태: kubectl -n synapse-local get pods
EOF
