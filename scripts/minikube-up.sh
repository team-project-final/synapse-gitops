#!/usr/bin/env bash
set -euo pipefail
# Synapse MSA를 minikube에 기동. 형제 레포가 ../synapse-* 에 클론되어 있어야 함.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"          # synapse-gitops
SIB="$(cd "$ROOT/.." && pwd)"                      # team-project-final

echo "==> 1) minikube 시작"
minikube status >/dev/null 2>&1 || minikube start --driver=docker --memory=6144 --cpus=4

echo "==> 2) 이미지 빌드 + minikube 적재"
build_docker() { # <name> <context>
  docker build -t "$1:local" "$2"
  minikube image load "$1:local"
}
build_docker synapse-platform-svc   "$SIB/synapse-platform-svc"
build_docker synapse-engagement-svc "$SIB/synapse-engagement-svc"
build_docker synapse-knowledge-svc  "$SIB/synapse-knowledge-svc"
build_docker synapse-learning-ai    "$SIB/synapse-learning-svc/learning-ai"
# learning-card: Dockerfile 없음 → Spring Boot bootBuildImage 사용
( cd "$SIB/synapse-learning-svc/learning-card" && ./gradlew bootBuildImage --imageName=synapse-learning-card:local )
minikube image load synapse-learning-card:local

echo "==> 3) 매니페스트 적용"
kubectl apply -k "$ROOT/local-k8s"

echo "==> 4) 롤아웃 대기"
kubectl -n synapse-local rollout status deploy/postgres --timeout=120s
for d in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  kubectl -n synapse-local rollout status "deploy/$d" --timeout=300s || true
done

cat <<'EOF'
==> 완료. 접근(별도 터미널에서 port-forward):
  kubectl -n synapse-local port-forward svc/platform-svc   8080:80
  kubectl -n synapse-local port-forward svc/engagement-svc 8082:80
  kubectl -n synapse-local port-forward svc/knowledge-svc  8083:80
  kubectl -n synapse-local port-forward svc/learning-card  8084:80
  kubectl -n synapse-local port-forward svc/learning-ai    8000:80
그 다음: curl http://localhost:8080/actuator/health , 브라우저로 http://localhost:8000/docs
상태: kubectl -n synapse-local get pods
EOF
