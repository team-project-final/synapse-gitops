#!/usr/bin/env bash
# nip.io 임시 도메인용 self-signed 인증서 생성 + ACM import (#121, W5 clearance window)
# 전제: ALB 프로비저닝 완료(ingress apply 후), openssl/aws/dig 사용 가능.
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-northeast-2}"
OUTDIR="${OUTDIR:-./.nipio-certs}"
SKIP_IMPORT=false

log() { echo -e "\033[1;34m[*]\033[0m $*"; }
ok()  { echo -e "\033[1;32m[OK]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERR]\033[0m $*" >&2; }

usage() {
  cat <<USAGE
사용법: gen-nipio-selfsigned.sh <ALB_DNS_또는_IP> [옵션]
  --skip-import   ACM import 생략(로컬 인증서 생성만 — 오프라인 검증용)
  --region <r>    AWS 리전 (기본 ap-northeast-2 / 환경변수 AWS_REGION)
  --out <dir>     출력 디렉토리 (기본 ./.nipio-certs)
  --help          도움말
출력:
  <out>/ca.crt, <out>/ca.key, <out>/leaf.crt, <out>/leaf.key
  ACM import 시 stdout 마지막 줄에 CERT_ARN=<arn>
USAGE
}

[ $# -ge 1 ] || { usage; exit 1; }
TARGET="$1"; shift
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-import) SKIP_IMPORT=true ;;
    --region) AWS_REGION="$2"; shift ;;
    --out) OUTDIR="$2"; shift ;;
    --help) usage; exit 0 ;;
    *) err "알 수 없는 옵션: $1"; usage; exit 1 ;;
  esac
  shift
done

require() { command -v "$1" >/dev/null 2>&1 || { err "필수 도구 없음: $1"; exit 1; }; }
require openssl

# 입력이 IP면 그대로, hostname이면 dig로 IP 추출
if echo "$TARGET" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
  IP="$TARGET"
else
  require dig
  IP="$(dig +short "$TARGET" | grep -E '^[0-9]+\.' | head -n1)"
  [ -n "$IP" ] || { err "ALB DNS에서 IP 추출 실패: $TARGET"; exit 1; }
fi
log "대상 IP: $IP (nip.io 베이스: ${IP}.nip.io)"

mkdir -p "$OUTDIR"
ARGOCD_HOST="argocd.${IP}.nip.io"
DEV_HOST="dev.${IP}.nip.io"

# 1) self-signed CA (window 폐기 전제 → 7일 유효)
openssl req -x509 -newkey rsa:2048 -nodes -days 7 \
  -keyout "$OUTDIR/ca.key" -out "$OUTDIR/ca.crt" \
  -subj "/CN=synapse-nipio-ca"

# 2) leaf key + CSR
openssl req -newkey rsa:2048 -nodes \
  -keyout "$OUTDIR/leaf.key" -out "$OUTDIR/leaf.csr" \
  -subj "/CN=${ARGOCD_HOST}"

# 3) SAN 확장 (argocd/dev/와일드카드)
cat > "$OUTDIR/san.ext" <<EXT
subjectAltName = DNS:${ARGOCD_HOST}, DNS:${DEV_HOST}, DNS:*.${IP}.nip.io
EXT

# 4) CA로 leaf 서명
openssl x509 -req -in "$OUTDIR/leaf.csr" -days 7 \
  -CA "$OUTDIR/ca.crt" -CAkey "$OUTDIR/ca.key" -CAcreateserial \
  -extfile "$OUTDIR/san.ext" -out "$OUTDIR/leaf.crt"
ok "인증서 생성: $OUTDIR/leaf.crt (SAN: ${ARGOCD_HOST}, ${DEV_HOST}, *.${IP}.nip.io)"

if $SKIP_IMPORT; then
  ok "--skip-import: ACM import 생략(로컬 생성만)"
  exit 0
fi

# 5) ACM import → ARN
require aws
ARN="$(aws acm import-certificate \
  --region "$AWS_REGION" \
  --certificate "fileb://$OUTDIR/leaf.crt" \
  --private-key "fileb://$OUTDIR/leaf.key" \
  --certificate-chain "fileb://$OUTDIR/ca.crt" \
  --query CertificateArn --output text)"
ok "ACM import 완료 (region=$AWS_REGION)"
echo "CERT_ARN=${ARN}"
