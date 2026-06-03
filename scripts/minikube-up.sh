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
build_docker synapse-learning-card  "$SIB/synapse-learning-svc/learning-card"
# learning-card는 이제 Dockerfile(멀티스테이지)이 있어 일반 docker build로 빌드합니다.
# (이전엔 Dockerfile이 없어 bootBuildImage를 썼으나, paketo 빌드팩 이미지는 docker-save→containerd import가
#  "wrong diff id"로 실패하는 문제가 있었습니다.)

# 알려진 이슈: learning-ai는 OPENAI_API_KEY 시크릿이 없으면 기동에 실패합니다(이미지 빌드는 정상).
# 키 없이 띄우려면 learning-ai만 ImagePullBackOff/CrashLoop 상태로 남고 나머지는 정상 동작합니다.

echo "==> 3) 매니페스트 적용"
kubectl apply -k "$ROOT/local-k8s"

echo "==> 3.5) learning-ai OpenAI 키 자동주입 (LEARNING_AI_OPENAI_API_KEY env 또는 ../.learning-ai-key 파일 존재 시)"
LAI_KEY="${LEARNING_AI_OPENAI_API_KEY:-}"
if [ -z "$LAI_KEY" ] && [ -f "$SIB/.learning-ai-key" ]; then LAI_KEY="$(cat "$SIB/.learning-ai-key" 2>/dev/null || true)"; fi
if [ -n "$LAI_KEY" ]; then
  # merge-patch: secrets.yaml(learning-ai-secret)의 나머지 키는 그대로 두고 OpenAI 키만 주입.
  # (create secret | apply 는 시크릿을 통째 교체해 secrets.yaml에 향후 추가될 키를 유실시킴)
  kubectl -n synapse-local patch secret learning-ai-secret --type=merge \
    -p "{\"stringData\":{\"LEARNING_AI_OPENAI_API_KEY\":\"$LAI_KEY\"}}"
  kubectl -n synapse-local rollout restart deploy/learning-ai
  echo "    키 주입 완료."
else
  echo "    키 없음 — learning-ai는 CrashLoop으로 남습니다(나머지 10개 워크로드는 정상). README 참조."
fi

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
