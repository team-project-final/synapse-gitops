#!/usr/bin/env bash
# main 브랜치 보호 적용 — GitHub Rulesets API 사용
# 전제: gh CLI 로그인 + repo admin 권한
#
# 참고:
# - Legacy Branch Protection API는 Private + GitHub Free 플랜에서 차단됨 (HTTP 403)
# - Public repo 또는 GitHub Pro/Team/Enterprise 플랜에서만 동작
# - 본 레포는 2026-05-16 E1 결정으로 Public 전환됨

set -euo pipefail

REPO="${REPO:-team-project-final/synapse-gitops}"
REVIEWS="${REVIEWS:-0}"
STATUS_CHECK="${STATUS_CHECK:-Validate Kubernetes Manifests}"
RULESET_NAME="${RULESET_NAME:-main-protection}"

log() { echo -e "\033[1;34m[*]\033[0m $*"; }
ok()  { echo -e "\033[1;32m[OK]\033[0m $*"; }

log "대상 레포: $REPO"
log "Ruleset 이름: $RULESET_NAME"
log "필수 status check: $STATUS_CHECK"
log "필수 리뷰 수: $REVIEWS (0=단독, 1=팀)"

PAYLOAD=$(cat <<JSON
{
  "name": "$RULESET_NAME",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/main"],
      "exclude": []
    }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "required_status_checks",
      "parameters": {
        "required_status_checks": [
          { "context": "$STATUS_CHECK" }
        ],
        "strict_required_status_checks_policy": false
      }
    },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": $REVIEWS,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      }
    }
  ]
}
JSON
)

EXISTING_ID=$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name == \"$RULESET_NAME\") | .id" 2>/dev/null || true)

if [ -n "$EXISTING_ID" ]; then
  log "기존 ruleset 발견 (id=$EXISTING_ID) — PUT으로 갱신"
  echo "$PAYLOAD" | gh api -X PUT "repos/$REPO/rulesets/$EXISTING_ID" \
    -H "Accept: application/vnd.github+json" --input - >/dev/null
  ok "Ruleset 갱신 완료 (id=$EXISTING_ID)"
else
  log "신규 ruleset 생성"
  CREATED=$(echo "$PAYLOAD" | gh api -X POST "repos/$REPO/rulesets" \
    -H "Accept: application/vnd.github+json" --input - --jq '.id')
  ok "Ruleset 생성 완료 (id=$CREATED)"
fi

echo ""
echo "main 브랜치 보호 적용 완료"
echo "   - 필수 status check: $STATUS_CHECK"
echo "   - 필수 리뷰 수: $REVIEWS"
echo "   - non-fast-forward + deletion 차단"
echo "   - 변경하려면: REVIEWS=1 bash scripts/setup-branch-protection.sh"
echo "   - 콘솔 확인: https://github.com/$REPO/rules"
