# W3 정리·마감(Consolidation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** W3의 남은 3일(5/27~5/29)을 정리·마감으로 운영 — 잔여·이월 항목을 비용 0으로 준비하고, 문서·포털 WIP를 main에 안착시키며, 레포/PM 문서를 정합화하고, 라이브 검증이 필요한 것만 주 마지막 단일 EKS 사이클로 묶는다.

**Architecture:** 세 트랙(A 잔여·이월 / B 문서·포털 / C 로컬·레포·PM)을 비용 게이트 배칭으로 배치한다. 비용 0 작업(terraform 코드·매니페스트·문서·git 위생)을 Day2~Day4 오전까지 끝내고, 라이브 EKS 검증(★)은 Day4 오후 조건부 단일 사이클에 모은다. cross-repo work order만 의존성 리드타임 때문에 Day2 아침으로 당긴다.

**Tech Stack:** Terraform(AWS provider, IRSA/IAM), Kustomize, ArgoCD ApplicationSet, ArgoCD Image Updater v0.15.2, Flutter Web(docs portal), Node.js(`build_docs.mjs`), `gh` CLI, git.

**관련 문서:** [W3 정리·마감 설계](../specs/2026-05-27-w3-consolidation-design.md) · [image-updater 런북](../../runbooks/image-updater-ecr-setup.md) · [ESO 런북 step5](../../runbooks/step5-eso-secrets.md) · [로컬 MSA 가이드 플랜(참조)](./2026-05-26-local-msa-setup-guide.md)

> **커밋 규칙:** 모든 커밋 메시지 말미에 다음 트레일러를 포함한다:
> `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`
> 명령은 Bash 도구(Git Bash) 기준. main 직접 작업 금지 — 각 태스크는 자체 브랜치에서 PR.

---

## File Structure

작업 대상 파일과 책임:

| 파일 | 작업 | 책임 |
|---|---|---|
| `infra/aws/dev/eso-irsa.tf` | Create | ESO IAM 정책(`synapse-dev-eso-secrets-read`) + 역할(`synapse-dev-eso-role`) IRSA — `synapse/*`(dev·staging·monitoring·gitops 포함) read |
| `infra/aws/dev/variables.tf` | Modify | `eks_node_count` 3→4, `domain_name`·`hosted_zone_id` 변수 추가 |
| `infra/aws/dev/acm.tf` | Create | `staging-*.<domain>` ACM 인증서 + DNS 검증(도메인 변수 가드) |
| `infra/ingress/staging-ingress.yaml` | Modify | ACM 인증서 ARN annotation 배선(값 치환은 라이브) |
| `apps/engagement-svc/overlays/dev/kustomization.yaml` | Modify | image-updater A안: `newTag` semver(`1.0.0`)로 핀 |
| `docs/runbooks/image-updater-bot-bypass.md` | Create | A안 전용 봇 bypass 실행 스크립트/절차(라이브 전 준비) |
| `docs/cross-repo/2026-05-27-platform-svc-staging-profile.md` | Create | platform-svc staging 프로필 work order 본문 |
| `docs/local-msa-setup.html` | Land(portal→main) | 로컬 MSA 온보딩 가이드(이미 작성됨, 안착 대상) |
| `site/lib/pages/dashboard_page.dart` | Land(portal→main) | 대시보드 Grafana/ArgoCD 링크 카드(이미 구현됨) |
| `site/README.md`, `README.md`, `docs/synapse-developer-guide.md` | Land/Modify | 포털 README + 가이드 교차 링크 |
| `docs/synapse-local-setup.html` | Delete | 미추적 번들러 아티팩트(정본은 `local-msa-setup.html`) |
| `site/lib/pages/handoff_page.dart` | Create(optional) | 핸드오프 허브 통합 뷰(P2 — 여유분, W4 폴백) |
| `local-k8s/README.md`, `scripts/minikube-up.sh` | Verify/Modify | 로컬 k8s 매니페스트 검증 + minikube 기동 문서 |
| `docs/superpowers/HANDOFF_W3.md`, `docs/project-management/task/TASK_gitops.md`, `docs/project-management/workflow/WORKFLOW_gitops_W3.md` | Modify | PM 정합 — W3 정리·마감 반영, D-0XX, W4 이월 |

---

# Day 2 (화 5/27) — 의존성 발행 + 잔여 코드/terraform 준비 (비용 0)

## Task 1: cross-repo work order — platform-svc staging 프로필 (A1)

가장 긴 의존(앱 레포)이므로 Day2 아침 최우선. work order 문서 작성 + 앱 레포에 GitHub 이슈 발행.

**Files:**
- Create: `docs/cross-repo/2026-05-27-platform-svc-staging-profile.md`

- [ ] **Step 1: 브랜치 생성**

```bash
cd /c/workspace/team-project-final/synapse-gitops
git switch main && git pull
git switch -c chore/w3-platform-svc-staging-workorder
```

- [ ] **Step 2: work order 문서 작성**

`docs/cross-repo/2026-05-27-platform-svc-staging-profile.md`를 아래 내용으로 생성:

```markdown
# Cross-Repo Work Order — platform-svc staging 프로필

> **발행일**: 2026-05-27 (W3 Day2)
> **발행**: synapse-gitops (@VelkaressiaBlutkrone)
> **수신**: synapse-platform-svc (앱 트랙)
> **우선순위**: P0 (W3 staging 5/5 Healthy 차단 요인)

## 배경
A2 실 EKS 검증에서 staging은 **4/5 Healthy**였고, platform-svc만 Degraded였다.
원인은 platform-svc 앱에 `staging` Spring profile이 없어서다(cross-repo = 앱 레포 의존).
gitops 측 staging overlay(`apps/platform-svc/overlays/staging`)·ExternalSecret 경로
(`synapse/staging/platform-svc/*`)·ApplicationSet auto-sync는 이미 완비됨.

## 요청 사항
1. `application-staging.yml`(또는 `application.yml`의 `staging` 프로필) 추가:
   - DB/Redis/Kafka 연결을 staging ExternalSecret 키와 정합(`spring.data.redis.*` relaxed-binding 키 — gitops main 6ea673a 참조).
   - `ddl-auto`/Flyway는 dev와 동일 전략(현재 그린 상태 유지).
2. staging 프로필로 기동 시 `/actuator/health` → UP.
3. ECR 이미지에 staging 프로필 포함 빌드 → 태그 push.

## 검수 기준
- gitops staging ApplicationSet sync 후 platform-svc staging **Synced + Healthy** (5/5 달성).
- 검증은 gitops 조건부 EKS 사이클(W3 Day4 또는 W4)에서 수행.

## 참고
- gitops staging overlay: `apps/platform-svc/overlays/staging/kustomization.yaml`
- Redis 키 수정 이력: gitops main `7be0998`, `93150f2`
```

- [ ] **Step 3: 커밋 + PR**

```bash
git add docs/cross-repo/2026-05-27-platform-svc-staging-profile.md
git commit -m "docs(cross-repo): platform-svc staging 프로필 work order 발행 (A1)"
git push -u origin chore/w3-platform-svc-staging-workorder
gh pr create --fill --base main
```

- [ ] **Step 4: 앱 레포에 GitHub 이슈 발행**

```bash
gh issue create \
  --repo team-project-final/synapse-platform-svc \
  --title "[W3/staging] platform-svc staging Spring profile 추가 (gitops staging 5/5 차단)" \
  --body "synapse-gitops work order: docs/cross-repo/2026-05-27-platform-svc-staging-profile.md 참조. staging 프로필 + ExternalSecret 키 정합 + /actuator/health UP 필요. P0."
```

Expected: 이슈 URL 출력. (권한/레포명 오류 시 `gh repo list team-project-final`로 정확한 레포명 확인 후 재시도.)

- [ ] **Step 5: 검증**

Run: `gh issue list --repo team-project-final/synapse-platform-svc --search "staging profile"`
Expected: 방금 생성한 이슈가 목록에 보임.

---

## Task 2: ESO IAM 정책/역할 terraform화 (A2)

현재 ESO IRSA는 terraform이 아니라 런북(step5)에만 있고 수동 생성. `image-updater-irsa.tf`를 템플릿으로 미러링해 코드화한다.

**Files:**
- Read(template): `infra/aws/dev/image-updater-irsa.tf`
- Create: `infra/aws/dev/eso-irsa.tf`

- [ ] **Step 1: 브랜치 + 템플릿 확인**

```bash
git switch main && git pull
git switch -c feat/w3-eso-irsa-terraform
```

`infra/aws/dev/image-updater-irsa.tf`를 읽어 다음 3가지 **정확한 참조**를 확보한다(eso-irsa.tf에서 동일하게 사용):
1. OIDC provider를 참조하는 방식 (예: `aws_iam_openid_connect_provider.eks.arn`/`.url` 또는 data source 이름).
2. assume-role-policy의 `StringEquals` 조건 키 구성(`<oidc>:sub`, `<oidc>:aud`).
3. 역할에 정책을 붙이는 리소스 패턴(`aws_iam_role_policy_attachment` 또는 inline).

- [ ] **Step 2: `eso-irsa.tf` 작성**

`image-updater-irsa.tf`의 OIDC 참조 방식을 **그대로** 사용하되, ECR 정책 대신 Secrets Manager 정책을 붙인다. ServiceAccount는 ESO 컨트롤러 SA(런북 step5 기준 `external-secrets` 네임스페이스의 `external-secrets` SA — step5-eso-secrets.md에서 정확한 namespace/SA 확인 후 `sub` 값 치환).

```hcl
# infra/aws/dev/eso-irsa.tf
# External Secrets Operator IRSA — terraform화 (A2, 기존 수동 생성분 코드화)
# image-updater-irsa.tf의 OIDC 참조 패턴을 미러링한다.

resource "aws_iam_policy" "eso_secrets_read" {
  name        = "synapse-dev-eso-secrets-read"
  description = "ESO read access to synapse/* secrets (dev, staging, monitoring, gitops)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:ListSecrets",
      ]
      # synapse/* 와일드카드가 monitoring·gitops·staging 전부 포함 (런북 step5 정합)
      Resource = "arn:aws:secretsmanager:${var.aws_region}:*:secret:synapse/*"
    }]
  })
}

resource "aws_iam_role" "eso" {
  name = "synapse-dev-eso-role"

  # ↓ image-updater-irsa.tf 의 assume_role_policy 블록을 그대로 가져와
  #   StringEquals 의 sub 만 external-secrets SA 로 치환:
  #   "<OIDC_URL>:sub" = "system:serviceaccount:external-secrets:external-secrets"
  #   "<OIDC_URL>:aud" = "sts.amazonaws.com"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn } # ← 템플릿과 동일 참조로 치환
      Action   = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:external-secrets:external-secrets"
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eso" {
  role       = aws_iam_role.eso.name
  policy_arn = aws_iam_policy.eso_secrets_read.arn
}

output "eso_role_arn" {
  description = "ESO IRSA role ARN (annotate external-secrets SA with this)"
  value       = aws_iam_role.eso.arn
}
```

> **주의:** `aws_iam_openid_connect_provider.eks` 참조 이름이 `image-updater-irsa.tf`와 다르면(예: module 출력) 그 파일과 **동일한 참조**로 4곳(Principal, sub, aud)을 치환할 것. 추측 금지 — 템플릿 파일의 실제 참조를 복사.

- [ ] **Step 3: terraform validate (비용 0 — offline)**

```bash
cd infra/aws/dev
terraform fmt eso-irsa.tf
terraform validate
```

Expected: `Success! The configuration is valid.` (validate가 backend init을 요구하면 `terraform init -backend=false` 후 재실행 — apply/plan은 Day4 조건부 사이클에서.)

- [ ] **Step 4: 커밋 + PR**

```bash
cd /c/workspace/team-project-final/synapse-gitops
git add infra/aws/dev/eso-irsa.tf
git commit -m "feat(infra): ESO IRSA terraform화 — synapse/* read 정책+역할 (A2)"
git push -u origin feat/w3-eso-irsa-terraform
gh pr create --fill --base main
```

---

## Task 3: engagement-svc 노드 capacity ≥4 (A3)

W2 S4에서 2노드 capacity로 engagement-svc Pending. observability도 노드 ≥4 필요(HANDOFF). 변수 기본값만 올린다.

**Files:**
- Modify: `infra/aws/dev/variables.tf` (`eks_node_count` 기본값)

- [ ] **Step 1: 브랜치 + 현재값 확인**

```bash
git switch main && git pull
git switch -c feat/w3-node-capacity
```

`infra/aws/dev/variables.tf`에서 `eks_node_count` 블록 확인 (현재 `default = 3`).

- [ ] **Step 2: 기본값 3→4 수정**

`infra/aws/dev/variables.tf`의 해당 블록을 다음으로 수정:

```hcl
variable "eks_node_count" {
  description = "Number of EKS worker nodes (>=4 for observability + 5/5 app capacity)"
  type        = number
  default     = 4
}
```

(이 변경으로 `eks.tf`의 `scaling_config`가 desired=4/min=4/max=5가 됨.)

- [ ] **Step 3: validate**

```bash
cd infra/aws/dev && terraform validate
```

Expected: 유효. (apply는 Day4 조건부 사이클.)

- [ ] **Step 4: 커밋 + PR**

```bash
cd /c/workspace/team-project-final/synapse-gitops
git add infra/aws/dev/variables.tf
git commit -m "feat(infra): EKS 노드 기본값 3→4 — observability+5/5 capacity (A3)"
git push -u origin feat/w3-node-capacity
gh pr create --fill --base main
```

---

## Task 4: staging Ingress ACM/TLS terraform + 매니페스트 배선 (A4)

ACM 인증서·도메인 변수는 현재 부재. terraform 코드를 도메인 변수로 가드해 작성하고 Ingress에 ARN annotation을 배선한다. **라이브 apply는 실제 Route53 hosted zone이 있어야 가능 → 조건부/W4.**

**Files:**
- Modify: `infra/aws/dev/variables.tf`
- Create: `infra/aws/dev/acm.tf`
- Modify: `infra/ingress/staging-ingress.yaml`

- [ ] **Step 1: 브랜치**

```bash
git switch main && git pull
git switch -c feat/w3-staging-acm-tls
```

- [ ] **Step 2: 도메인 변수 추가** — `infra/aws/dev/variables.tf` 끝에 추가:

```hcl
variable "domain_name" {
  description = "Base domain for staging hosts (e.g. example.com). Empty disables ACM."
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID for domain_name. Required if domain_name set."
  type        = string
  default     = ""
}
```

- [ ] **Step 3: `acm.tf` 작성** (도메인 변수가 비면 리소스 0개 — 안전)

```hcl
# infra/aws/dev/acm.tf
# staging-*.<domain> 와일드카드 인증서 + DNS 검증.
# domain_name 이 비어있으면 count=0 → 라이브 zone 확보 전까지 무동작.

resource "aws_acm_certificate" "staging" {
  count             = var.domain_name == "" ? 0 : 1
  domain_name       = "staging-*.${var.domain_name}"
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
  tags = { Name = "synapse-staging-wildcard", env = "staging" }
}

resource "aws_route53_record" "staging_cert_validation" {
  for_each = var.domain_name == "" ? {} : {
    for dvo in aws_acm_certificate.staging[0].domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }
  zone_id = var.hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "staging" {
  count                   = var.domain_name == "" ? 0 : 1
  certificate_arn         = aws_acm_certificate.staging[0].arn
  validation_record_fqdns = [for r in aws_route53_record.staging_cert_validation : r.fqdn]
}

output "staging_acm_certificate_arn" {
  description = "ACM cert ARN for staging ALB Ingress (empty until domain_name set)"
  value       = var.domain_name == "" ? "" : aws_acm_certificate.staging[0].arn
}
```

- [ ] **Step 4: Ingress에 ARN annotation 배선** — `infra/ingress/staging-ingress.yaml`의 ALB annotation에 인증서 참조 줄을 추가(값 치환은 라이브). 기존 annotation 블록 아래에 추가:

```yaml
    # ACM 인증서 — 라이브 적용 시 terraform output staging_acm_certificate_arn 값으로 치환
    alb.ingress.kubernetes.io/certificate-arn: "REPLACE_WITH_ACM_ARN"
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
```

> `REPLACE_WITH_ACM_ARN`은 라이브 사이클에서 `terraform output -raw staging_acm_certificate_arn`으로 치환. 매니페스트엔 문자열 placeholder로 두되, 이 placeholder 존재를 런북에 명시(Task 11 PM 정합에서 D-0XX 추가).

- [ ] **Step 5: validate + kustomize 렌더 확인**

```bash
cd infra/aws/dev && terraform validate && cd /c/workspace/team-project-final/synapse-gitops
# ingress가 kustomize에 포함돼 있으면:
kubectl kustomize infra/ingress 2>/dev/null | grep -A2 certificate-arn || echo "ingress는 단독 yaml (kustomize 미포함) — yaml 문법만 확인"
```

Expected: terraform valid + ingress yaml에 certificate-arn 줄 존재.

- [ ] **Step 6: 커밋 + PR**

```bash
git add infra/aws/dev/variables.tf infra/aws/dev/acm.tf infra/ingress/staging-ingress.yaml
git commit -m "feat(infra): staging ACM/TLS terraform(도메인 가드) + Ingress ARN 배선 (A4)"
git push -u origin feat/w3-staging-acm-tls
gh pr create --fill --base main
```

---

## Task 5: image-updater A안 — bypass 준비 (A5, 비용 0 부분)

런북 `image-updater-ecr-setup.md`의 A 실행 절차 중 **비용 0 준비분**만: overlay semver 핀 + bypass 스크립트/절차 문서. (ruleset 변경·ECR push·write-back E2E는 Day4 조건부.)

**Files:**
- Modify: `apps/engagement-svc/overlays/dev/kustomization.yaml`
- Create: `docs/runbooks/image-updater-bot-bypass.md`

- [ ] **Step 1: 브랜치 + 현재 overlay 확인**

```bash
git switch main && git pull
git switch -c feat/w3-image-updater-a-prep
```

`apps/engagement-svc/overlays/dev/kustomization.yaml`의 `images:` 블록에서 `newTag` 확인(현재 `dev-latest` — semver 전략과 불일치).

- [ ] **Step 2: newTag를 semver로 핀** — `images:` 블록의 engagement-svc 항목 `newTag`를 `dev-latest` → `1.0.0`으로 수정 (런북 A절차 3번). 정확한 image name은 기존 블록 그대로 유지, `newTag`만 교체.

- [ ] **Step 3: kustomize 렌더 검증**

```bash
kubectl kustomize apps/engagement-svc/overlays/dev | grep "image:"
```

Expected: engagement-svc 이미지 태그가 `:1.0.0`으로 렌더됨.

- [ ] **Step 4: bypass 절차 문서 작성** — `docs/runbooks/image-updater-bot-bypass.md`:

```markdown
# Runbook: image-updater A안 — main 보호 bypass (dev/staging)

> 런북 `image-updater-ecr-setup.md` §A의 라이브 실행 절차를 스크립트화.
> ⚠️ 라이브 클러스터 1사이클(과금) + main ruleset 변경 포함.

## 사전 (비용 0, 완료)
- engagement-svc dev overlay `newTag: 1.0.0` (semver 전략 호환) — 본 PR에서 핀.
- 전용 봇 PAT(`contents:write`만)를 AWS SM `synapse/gitops/git-token`에 저장(라이브 전).

## 라이브 실행 (조건부 사이클)
1. ruleset ID 확인: `gh api repos/team-project-final/synapse-gitops/rulesets`
2. `bypass_actors`에 봇만 추가 (사람은 PR 유지):
   \`\`\`bash
   gh api -X PUT repos/team-project-final/synapse-gitops/rulesets/<ID> \
     --input ruleset-bypass.json   # bypass_actors=[{actor_id:<봇>,actor_type:"Integration",bypass_mode:"always"}]
   \`\`\`
3. ECR registries.conf + pullsecret(`argocd/ecr-creds`) 적용(bring-up image-updater phase).
4. ECR에 상위 semver(`2.0.0`) push → image-updater 감지 → write-back 커밋(main) → ArgoCD sync → dev 반영 확인.
5. 검증 후 토큰 갱신 CronJob 백로그 기록(12h 만료).
```

- [ ] **Step 5: 커밋 + PR**

```bash
git add apps/engagement-svc/overlays/dev/kustomization.yaml docs/runbooks/image-updater-bot-bypass.md
git commit -m "feat(image-updater): A안 준비 — engagement-svc semver 핀 + bypass 런북 (A5)"
git push -u origin feat/w3-image-updater-a-prep
gh pr create --fill --base main
```

---

# Day 3 (수 5/28) — 브랜치 위생 + 문서·포털 (비용 0)

## Task 6: 머지 완료 원격 브랜치 프루닝 (C3-1)

origin/main에 이미 머지된 원격 브랜치들을 정리. **삭제 전 각 브랜치가 정말 머지됐는지 재확인.**

- [ ] **Step 1: 머지된 브랜치 목록 산출**

```bash
cd /c/workspace/team-project-final/synapse-gitops
git fetch --prune origin
git branch -r --merged origin/main | grep -v 'origin/main\|origin/HEAD'
```

Expected: `docs/session8-*`, `docs/session9-*`, `docs/w3-*`, `feat/bringup-automation`, `feat/ci-pr-diff-comment`, `feat/image-updater-eks`, `feat/w2-staging-overlay`, `feat/w3-staging-observability`, `fix/*` 등이 나열됨.

- [ ] **Step 2: 각 브랜치 unique 커밋 0건 확인** (안전 게이트)

```bash
for b in $(git branch -r --merged origin/main | grep -v 'origin/main\|origin/HEAD' | sed 's#origin/##'); do
  n=$(git log --oneline origin/main..origin/$b | wc -l);
  echo "$b: $n unique commits";
done
```

Expected: 모든 브랜치 `0 unique commits`. **0이 아닌 브랜치는 삭제 목록에서 제외**하고 보고.

- [ ] **Step 3: 삭제 (0건 확인된 것만)**

```bash
# 예시 — Step2에서 0건 확인된 브랜치만:
git push origin --delete docs/session8-final docs/session8-handoff-final docs/session8-task-update \
  docs/session9-final docs/session9-handoff docs/w3-handoff-carryover docs/w3-schedule-update \
  feat/bringup-automation feat/ci-pr-diff-comment feat/image-updater-eks feat/w2-staging-overlay \
  feat/w3-staging-observability fix/deploy-pages-dart-version fix/eks-platform-redis-tls-auth \
  fix/kafka-brokers-and-docs fix/learning-ai-port-mismatch fix/liveness-probe-delay \
  fix/local-k8s-platform-redis-config fix/platform-svc-env-vars
```

> `feat/docs-portal-v2`·`docs/unified-handoff-hub-spoke`·`docs/local-msa-setup-guide`는 **삭제하지 말 것**(Task 7에서 처리/검토). Step2에서 unique 커밋이 있는 것으로 나오면 그대로 둔다.

- [ ] **Step 4: 검증**

```bash
git fetch --prune origin && git branch -r
```

Expected: 삭제한 브랜치들이 사라지고 `feat/docs-portal-v2` 등 보존 대상만 남음.

---

## Task 7: docs-portal-v2 가치 콘텐츠 재구성 → main 안착 (C3-2 + B1 + C1 landing)

로컬 `feat/docs-portal-v2`의 21커밋 중 가치 있는 산출물(가이드 HTML, 대시보드 Grafana 링크, site README)을 **end-state 파일 단위로** 새 브랜치에 가져온다. 중복 인프라 커밋(`ab1849b`/`91e508f`/`540b37b`)은 버림. 경로 발산(`docs/specs` vs `docs/superpowers/specs`) 때문에 cherry-pick 대신 파일 체크아웃.

**Files (portal 브랜치에서 가져옴):**
- `docs/local-msa-setup.html` (가이드 본체 — 이미 작성됨)
- `site/lib/pages/dashboard_page.dart` (Grafana/ArgoCD 링크 — 이미 구현됨)
- `site/README.md`, `site/pubspec.yaml`, `site/pubspec.lock`
- `README.md`, `docs/synapse-developer-guide.md` (교차 링크 — main 버전과 머지 필요)

- [ ] **Step 1: 브랜치 + 가치 파일 식별**

```bash
git switch main && git pull
git switch -c feat/w3-land-docs-portal
git log --oneline origin/feat/docs-portal-v2..feat/docs-portal-v2   # 21커밋 재확인
```

- [ ] **Step 2: 가이드 + 대시보드 파일 체크아웃** (main에 없는 신규/갱신만)

```bash
git checkout feat/docs-portal-v2 -- docs/local-msa-setup.html
git checkout feat/docs-portal-v2 -- site/lib/pages/dashboard_page.dart site/README.md site/pubspec.yaml site/pubspec.lock
git status
```

Expected: 위 파일들이 staged. (인프라/모니터링 파일은 가져오지 않음 — 이미 main에 있음.)

- [ ] **Step 3: README/developer-guide 교차 링크 수동 머지**

`README.md`("문서 > 시작하기" 목록 최상단)에 추가:

```markdown
- **[로컬 MSA 세팅 가이드 (HTML)](docs/local-msa-setup.html)** — 신규 팀원용 단계별 로컬 개발환경 세팅 (초보~준시니어, AWS 제외)
```

`docs/synapse-developer-guide.md`의 "## 3. 로컬 개발 환경 세팅" 바로 아래에 추가:

```markdown
> 🚀 처음이라면 단계별 HTML 가이드부터: **[로컬 MSA 세팅 가이드](local-msa-setup.html)**
```

> portal 브랜치 버전을 통째로 덮어쓰지 말 것 — main이 그 사이 갱신됐을 수 있으므로 위 두 줄만 수동 추가.

- [ ] **Step 4: 포털 빌드 검증 (Flutter analyze)**

```bash
cd site && flutter pub get && flutter analyze
```

Expected: `No issues found!` (Flutter 미설치 환경이면 이 스텝은 CI에 위임하고 스킵 — `flutter --version`으로 확인. dashboard_page.dart는 `GRAFANA_URL`/`ARGOCD_URL` dart-define 환경변수 사용, 미설정 시 빈 문자열 기본값이라 빌드 안전.)

- [ ] **Step 5: 가이드 렌더 확인** — `docs/local-msa-setup.html`를 브라우저로 연다 (playwright `browser_navigate` 또는 `file:///c:/workspace/team-project-final/synapse-gitops/docs/local-msa-setup.html`).

Expected: 좌측 TOC(8개 섹션 0~7) + 본문, §0~§7 콘텐츠 채워짐, 콘솔 에러 0, 복사 버튼/체크박스/탭 동작.

- [ ] **Step 6: 커밋 + PR**

```bash
cd /c/workspace/team-project-final/synapse-gitops
git add docs/local-msa-setup.html site/ README.md docs/synapse-developer-guide.md
git commit -m "docs(portal): 로컬 MSA 가이드 + 대시보드 Grafana/ArgoCD 링크 main 안착 (B1/C1)"
git push -u origin feat/w3-land-docs-portal
gh pr create --fill --base main
```

- [ ] **Step 7: 안착 후 portal 브랜치 정리 판단**

main 머지 확인 후, `feat/docs-portal-v2` 로컬/원격에 남은 unique 가치가 없으면 삭제, 있으면 보고. (P2 작업 base가 필요하면 Task 8까지 보존.)

```bash
git log --oneline main..feat/docs-portal-v2   # 머지 후 남은 unique 커밋
```

---

## Task 8 (여유분/Optional): 포털 P2 — 핸드오프 허브 통합 뷰 (B2)

**P2 — 시간 남을 때만. 압박 시 W4 이월(감점 아님).** 검색은 이미 구현됨(`search_page.dart`) → "고도화"는 선택. 핸드오프 허브 뷰는 부재 → 신규 페이지 스캐폴드.

**Files:**
- Create: `site/lib/pages/handoff_page.dart`
- Modify: `site/lib/app.dart` (라우트 등록)

- [ ] **Step 1: 착수 가능 여부 판단** — Day3 종료까지 Task 6·7 완료 + 여유 ≥2h일 때만 시작. 아니면 이 태스크 전체를 W4 백로그로 이월하고 Task 11(PM 정합)에 기록.

- [ ] **Step 2: 핸드오프 페이지 스캐폴드** — 기존 `dashboard_page.dart` 구조를 본떠 `handoff_page.dart` 생성: HANDOFF_W1~W3 + HANDOFF_HUB(shared) 링크 카드를 한 화면에. 데이터는 기존 `assets/docs/index.json`의 management 카테고리 문서 필터로 재사용(신규 데이터 소스 만들지 않음 — YAGNI).

- [ ] **Step 3: 라우트 등록** — `site/lib/app.dart`의 go_router 라우트에 `/handoff` → `HandoffPage` 추가 (기존 라우트 패턴 그대로).

- [ ] **Step 4: 빌드 검증**

```bash
cd site && flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 5: 커밋 + PR**

```bash
git add site/lib/pages/handoff_page.dart site/lib/app.dart
git commit -m "feat(portal): 핸드오프 허브 통합 뷰 (P2)"
git push -u origin feat/w3-portal-handoff-hub && gh pr create --fill --base main
```

---

# Day 4 (목 5/29) — 로컬 정리 + PM 정합 + (오후) 조건부 EKS

## Task 9: 미추적 아티팩트 처리 + 가이드 최종 QA (C1-tail)

정본은 `docs/local-msa-setup.html`(Task 7 안착). 미추적 `docs/synapse-local-setup.html`은 번들러 아티팩트 → 삭제.

**Files:**
- Delete: `docs/synapse-local-setup.html`
- Modify(조건부): `.gitignore`

- [ ] **Step 1: 브랜치 + 아티팩트 정체 재확인**

```bash
git switch main && git pull
git switch -c chore/w3-cleanup-artifact
head -25 docs/synapse-local-setup.html   # __bundler_thumbnail 셸인지 확인
```

Expected: `__bundler_loading`/`__bundler_thumbnail` 마크업 = 번들러 export 아티팩트(손으로 쓴 가이드 아님).

- [ ] **Step 2: 삭제** (미추적이므로 파일 시스템 삭제)

```bash
rm docs/synapse-local-setup.html
```

- [ ] **Step 3: 재발 방지 gitignore (export 도구가 또 떨굴 경우)** — `.gitignore`에 한 줄 추가(이미 있으면 스킵):

```
docs/synapse-local-setup.html
```

- [ ] **Step 4: 정본 가이드 최종 QA** — `docs/local-msa-setup.html`(main에 안착됨)를 브라우저로 다시 열어 8섹션·복사·탭·반응형(880px 이하 TOC 접힘) 최종 확인. 깨진 곳 있으면 별도 fix PR.

- [ ] **Step 5: 커밋 + PR**

```bash
git add .gitignore
git commit -m "chore(docs): 미추적 번들러 아티팩트 제거 + gitignore (C1)"
git push -u origin chore/w3-cleanup-artifact && gh pr create --fill --base main
```

---

## Task 10: local-k8s / minikube 정합화 (C2)

`local-k8s/` 매니페스트가 빌드되는지 검증하고 `minikube-up.sh` 기동 절차를 문서화. (최근 Redis/learning-ai/platform fix들이 main에 반영됐는지 확인 포함.)

**Files:**
- Verify: `local-k8s/` (kustomize build)
- Modify: `local-k8s/README.md` (기동 절차 + 검증된 fix 반영)
- Verify: `scripts/minikube-up.sh`

- [ ] **Step 1: 브랜치 + 매니페스트 빌드 검증**

```bash
git switch main && git pull
git switch -c docs/w3-local-k8s-consolidation
kubectl kustomize local-k8s | head -50
```

Expected: 에러 없이 렌더(namespace + infra + 5앱). 에러 시 원인 파일 기록.

- [ ] **Step 2: minikube-up.sh 점검** — `scripts/minikube-up.sh`를 읽어 기동 단계(메모리 8GB, enableServiceLinks, SPRING_DATASOURCE_* 등 — 메모리 노트 `local-k8s-runtime-gotchas` 정합)가 스크립트에 반영됐는지 확인. 누락 gotcha는 README에 명시.

- [ ] **Step 3: `local-k8s/README.md` 정합화** — 기동 절차(`minikube start --memory=8192` → `scripts/minikube-up.sh` → 검증 명령)와 알려진 gotcha(kafka enableServiceLinks, platform SPRING_DATASOURCE_*, learning-ai/card 이미지 이슈)를 한 곳에 정리. 최근 main에 머지된 Redis 키 수정(`7be0998`, `93150f2`)이 local-k8s에도 반영됐는지 대조.

- [ ] **Step 4: (가능 시) 로컬 minikube 스모크** — Docker/minikube 사용 가능 환경이면 `bash scripts/minikube-up.sh`로 1회 기동 후 `kubectl get pods -A` 확인. 불가하면 "매니페스트 렌더 검증 + 문서"로 한정하고 README에 명시.

- [ ] **Step 5: 커밋 + PR**

```bash
git add local-k8s/README.md scripts/minikube-up.sh
git commit -m "docs(local-k8s): 기동 절차+gotcha 정합화, 최근 fix 반영 (C2)"
git push -u origin docs/w3-local-k8s-consolidation && gh pr create --fill --base main
```

---

## Task 11: PM 문서 정합 (C4)

W3 정리·마감 결과를 PM 문서에 반영. WORKFLOW 파서 문법(`- [ ]`/`- [x]`, `## Step N:`) 정확히 유지.

**Files:**
- Modify: `docs/superpowers/HANDOFF_W3.md`
- Modify: `docs/project-management/task/TASK_gitops.md`
- Modify: `docs/project-management/workflow/WORKFLOW_gitops_W3.md`

- [ ] **Step 1: 브랜치**

```bash
git switch main && git pull
git switch -c docs/w3-pm-consolidation
```

- [ ] **Step 2: HANDOFF_W3 갱신** — "W3 추가(2026-05-27~29) — 정리·마감" 세션 항목 추가: A1~A5 코드 완료/조건부, B1 포털 안착, C1~C4 정리 결과. 신규 발견사항 D-038+ 기록(예: D-038 staging Ingress `REPLACE_WITH_ACM_ARN` placeholder — 라이브 시 `terraform output staging_acm_certificate_arn` 치환; D-039 ESO/노드capacity/ACM terraform화는 코드 완료, 라이브 검증 조건부/W4).

- [ ] **Step 3: TASK_gitops 갱신** — W2 Step 4 engagement-svc 항목에 "노드 ≥4 terraform화 완료(A3), 라이브 5/5는 조건부 사이클" 주석. Step 6/7 잔여(image-updater A안 준비 완료, platform-svc staging work order 발행)를 상태 노트로 반영. W4(Step 9/10) 이월 항목 명시.

- [ ] **Step 4: WORKFLOW_W3 갱신** — Step 7/8은 Done 유지. 정리·마감 결과를 Step 헤더 하단 노트로 추가(체크박스 카운트는 건드리지 않음 — 파서 정합). 포털 P2(Task 8) 미완 시 "W4 이월"로 명시.

- [ ] **Step 5: 파서 문법 검증**

```bash
grep -nE '^- \[[ x]\] ' docs/project-management/workflow/WORKFLOW_gitops_W3.md | head
grep -nE '^## Step [0-9]+:' docs/project-management/workflow/WORKFLOW_gitops_W3.md
```

Expected: 체크박스/Step 헤더 패턴이 깨지지 않음(parse-workflow.yml이 인식).

- [ ] **Step 6: 커밋 + PR**

```bash
git add docs/superpowers/HANDOFF_W3.md docs/project-management/task/TASK_gitops.md docs/project-management/workflow/WORKFLOW_gitops_W3.md
git commit -m "docs(pm): W3 정리·마감 반영 — A/B/C 결과, D-038/039, W4 이월 (C4)"
git push -u origin docs/w3-pm-consolidation && gh pr create --fill --base main
```

---

## Task 12 (조건부/Gated): 단일 EKS 사이클 — 라이브 검증 (★)

**게이트:** Day4 오후 + 시간/예산 여유 + (가능하면) cross-repo platform-svc 프로필 도착. 미충족 시 **실행하지 않고** A3/A4/A5 라이브 항목을 W4로 이월(Task 11에 기록). ⚠️ 과금 ~$0.41/hr — 종료 시 반드시 destroy.

**전제:** A2~A5 PR이 main에 머지된 상태(terraform/매니페스트 반영).

- [ ] **Step 1: 기동** — `scripts/bring-up.sh` (W3 Day1 검증된 11 phase 멱등 자동화). terraform apply가 새 변수(eks_node_count=4) 반영하는지 확인.

```bash
bash scripts/bring-up.sh
```

Expected: 11/11 phase 통과, 노드 4개 Ready.

- [ ] **Step 2: A2 검증 — ESO IRSA** — ESO SA가 terraform 역할로 annotate되고 ExternalSecret SecretSynced(monitoring 포함).

```bash
kubectl get externalsecret -A | grep -v 'SecretSynced' || echo "모든 ExternalSecret SecretSynced"
```

- [ ] **Step 3: A3 검증 — capacity** — engagement-svc 포함 dev 5/5 Running(Pending 없음).

```bash
kubectl get pods -n synapse-dev | grep -i pending && echo "FAIL: Pending 존재" || echo "PASS: Pending 없음"
```

- [ ] **Step 4: A4 검증 — staging TLS** (도메인/zone 있을 때만) — `terraform output -raw staging_acm_certificate_arn`로 ARN 확보 → Ingress `REPLACE_WITH_ACM_ARN` 치환 → ALB HTTPS 리스너 확인. 도메인 없으면 "ACM W4 이월" 기록 후 스킵.

- [ ] **Step 5: A5 검증 — image-updater write-back E2E** — `docs/runbooks/image-updater-bot-bypass.md` 라이브 절차 실행: ruleset bypass → ECR `2.0.0` push → write-back 커밋(main) → ArgoCD sync → dev 반영.

- [ ] **Step 6: platform-svc staging 5/5** (work order 도착 시) — staging ApplicationSet sync 후 platform-svc Synced+Healthy 확인 → staging 5/5 달성. 미도착이면 "조건부 done" 유지.

- [ ] **Step 7: destroy (필수)**

```bash
cd infra/aws/dev && terraform destroy -auto-approve
```

Expected: 모든 리소스 삭제. S3 state bucket + DynamoDB lock만 유지.

- [ ] **Step 8: HANDOFF_W3에 라이브 결과 기록** — 검증/미검증 항목과 잔여 W4 이월을 갱신(Task 11 문서에 append). 커밋 + PR.

---

## Self-Review

플랜 작성 후 스펙(`2026-05-27-w3-consolidation-design.md`) 대비 점검 결과:

**1. 스펙 커버리지:** A1→Task1, A2→Task2, A3→Task3, A4→Task4, A5→Task5, B1→Task7, B2→Task8(여유분), C1→Task7(안착)+Task9(아티팩트/QA), C2→Task10, C3→Task6(프루닝)+Task7(docs-portal 분리), C4→Task11, ★조건부 EKS→Task12. 스펙 전 항목에 태스크 존재.

**2. 플레이스홀더 스캔:** 의도적 placeholder는 2곳뿐이며 모두 "라이브 치환" 명시 — Ingress의 `REPLACE_WITH_ACM_ARN`(terraform output으로 치환, D-038 기록), `eso-irsa.tf`의 OIDC 참조(템플릿 `image-updater-irsa.tf`에서 정확값 복사 지시 + 추측 금지 경고). 그 외 모든 명령·경로·코드는 실제 검증값.

**3. 타입/이름 일관성:** 리소스명(`synapse-dev-eso-secrets-read`/`synapse-dev-eso-role`/`synapse-dev-image-updater-role`), 변수(`eks_node_count`/`domain_name`/`hosted_zone_id`), output(`staging_acm_certificate_arn`/`eso_role_arn`), 브랜치/PR 네이밍이 태스크 전반 일관. 의존: Task12는 Task2~5 머지 전제 — 명시됨.

**4. 비용 게이트:** Task1~11은 전부 비용 0(terraform validate offline, kustomize/flutter analyze, git, 문서). 라이브 apply/push/destroy는 Task12 게이트 안에만 존재 — 스펙의 "조건부 단일 사이클"과 정합.
