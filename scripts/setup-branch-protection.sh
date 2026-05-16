#!/usr/bin/env bash
# main 브랜치 보호 룰 적용
# 전제: gh CLI 로그인 + repo admin 권한

set -euo pipefail

REPO="${REPO:-team-project-final/synapse-gitops}"
REVIEWS="${REVIEWS:-0}"
STATUS_CHECK="${STATUS_CHECK:-Validate Kubernetes Manifests}"

log() { echo -e "\033[1;34m[*]\033[0m $*"; }

log "대상 레포: $REPO"
log "필수 status check: $STATUS_CHECK"
log "필수 리뷰 수: $REVIEWS (0=단독, 1=팀)"

gh api -X PUT "repos/$REPO/branches/main/protection" \
  -F "required_status_checks[strict]=true" \
  -F "required_status_checks[contexts][]=$STATUS_CHECK" \
  -F "required_pull_request_reviews[required_approving_review_count]=$REVIEWS" \
  -F "required_pull_request_reviews[dismiss_stale_reviews]=true" \
  -F "enforce_admins=false" \
  -F "restrictions=" \
  -F "allow_force_pushes=false" \
  -F "allow_deletions=false" \
  -F "required_linear_history=false" \
  -F "required_conversation_resolution=true" >/dev/null

echo ""
echo "main 브랜치 보호 적용 완료"
echo "   - 필수 status check: $STATUS_CHECK"
echo "   - 필수 리뷰 수: $REVIEWS"
echo "   - 변경하려면: REVIEWS=1 bash scripts/setup-branch-protection.sh"
