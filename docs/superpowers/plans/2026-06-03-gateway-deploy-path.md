# gateway EKS 배포 경로 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Spring Cloud Gateway를 dev ApplicationSet에 추가해 ArgoCD가 배포하게 하고, ALB Ingress(단일 호스트→gateway)를 신설해 Gateway 패턴(ALB→gateway→services)으로 EKS 노출 경로를 확정한다.

**Architecture:** gitops 단일 PR. `argocd/applicationset.yaml` 매트릭스에 `gateway` 추가(→ ArgoCD가 `apps/gateway/overlays/dev`를 synapse-dev에 배포, image-updater ECR semver 포함). `infra/ingress/dev-ingress.yaml` 신설(staging-ingress 패턴, 단일 호스트 → gateway service:80). README로 prod 후속·B4 정합 문서화.

**Tech Stack:** ArgoCD ApplicationSet, AWS ALB Ingress(aws-load-balancer-controller), Kustomize, yamllint.

**환경:** `D:/workspace/final-project-syn/synapse-gitops`, 브랜치 `feat/gateway-deploy-path`(spec 커밋 `168d9f0` 포함). yamllint은 `C:/Users/deepe/AppData/Local/Python/pythoncore-3.14-64/python.exe -m yamllint`(로컬 CRLF new-lines 에러 무시). 클러스터 부재 → 렌더/lint만.

**호출 그래프:** ALB(ACM TLS) → gateway:80 → 파드:8080 → /api/platform→platform-svc, /api/engagement→engagement-svc, /api/knowledge→knowledge-svc, /api/learning→learning-card (gateway-config `*_SVC_URI` = http://<svc>:80).

---

## File Structure

수정:
- `argocd/applicationset.yaml` — list 제너레이터에 `- service: gateway` 추가.

생성:
- `infra/ingress/dev-ingress.yaml` — ALB Ingress, 단일 호스트 → gateway.
- `infra/ingress/README.md` — gateway 패턴 근거 + prod 후속 + staging 차이 문서화.

---

## Task 1: dev ApplicationSet에 gateway 추가

**Files:** Modify `argocd/applicationset.yaml`

현재 list 제너레이터(10-16행):
```yaml
          - list:
              elements:
                - service: platform-svc
                - service: engagement-svc
                - service: knowledge-svc
                - service: learning-card
                - service: learning-ai
```

- [ ] **Step 1: gateway 엔트리 추가**

`- service: learning-ai` 다음 줄에 추가(들여쓰기 동일, 공백 16칸 + `- service: gateway`):
```yaml
                - service: gateway
```
결과:
```yaml
          - list:
              elements:
                - service: platform-svc
                - service: engagement-svc
                - service: knowledge-svc
                - service: learning-card
                - service: learning-ai
                - service: gateway
```
(다른 부분 변경 없음. 템플릿이 path `apps/gateway/overlays/dev`, ns synapse-dev, image-updater
`.../synapse/gateway` 주석을 자동 생성.)

- [ ] **Step 2: gateway dev overlay 렌더 확인** (AS가 가리키는 경로가 정상 빌드되는지)

Run: `kubectl kustomize apps/gateway/overlays/dev >/dev/null && echo OK`
Expected: `OK`. (이미 존재하는 overlay라 빌드 정상.)

- [ ] **Step 3: ApplicationSet yaml 유효성(yamllint)**

Run:
```bash
PY="C:/Users/deepe/AppData/Local/Python/pythoncore-3.14-64/python.exe"
tr -d '\r' < argocd/applicationset.yaml > /tmp/lf.yaml && "$PY" -m yamllint -c .yamllint /tmp/lf.yaml && echo clean
```
Expected: `clean`.

- [ ] **Step 4: 커밋**

```bash
git add argocd/applicationset.yaml
git commit -m "feat(argocd): dev ApplicationSet에 gateway 추가 (B1)"
```

---

## Task 2: dev ALB Ingress 신설

**Files:** Create `infra/ingress/dev-ingress.yaml`

- [ ] **Step 1: dev-ingress.yaml 작성**

`infra/ingress/dev-ingress.yaml`:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: synapse-dev
  namespace: synapse-dev
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    # NOTE: 라이브 세션에서 ACM 인증서 ARN으로 치환
    #   acm.tf 적용 후 `terraform -chdir=infra/aws/dev output` 의 인증서 ARN 값
    alb.ingress.kubernetes.io/certificate-arn: <ACM_ARN>
    # gateway(Spring Boot actuator) readiness
    alb.ingress.kubernetes.io/healthcheck-path: /actuator/health/readiness
spec:
  rules:
    # 단일 진입: gateway가 /api/** 경로 라우팅 + rate-limit (ALB→gateway→services)
    # NOTE: <domain>을 프로젝트 도메인(terraform var.domain_name)으로 치환
    - host: dev.<domain>
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: gateway
                port:
                  number: 80
```

- [ ] **Step 2: yamllint 확인**

Run:
```bash
PY="C:/Users/deepe/AppData/Local/Python/pythoncore-3.14-64/python.exe"
tr -d '\r' < infra/ingress/dev-ingress.yaml > /tmp/lf.yaml && "$PY" -m yamllint -c .yamllint /tmp/lf.yaml && echo clean
```
Expected: `clean`. (staging-ingress.yaml과 동일 표기 — `'[{"HTTPS":443}]'` 포함 통과.)

- [ ] **Step 3: 커밋**

```bash
git add infra/ingress/dev-ingress.yaml
git commit -m "feat(ingress): dev ALB Ingress 신설 (ALB→gateway 단일 진입, B1)"
```

---

## Task 3: infra/ingress README 문서화

**Files:** Create `infra/ingress/README.md`

- [ ] **Step 1: README 작성**

`infra/ingress/README.md`:
```markdown
# infra/ingress

EKS 외부 노출(AWS ALB Ingress, aws-load-balancer-controller).

## dev — Gateway 패턴 (`dev-ingress.yaml`)
ALB(internet-facing, ACM TLS) → **gateway** service:80 → gateway 파드:8080.
gateway(Spring Cloud Gateway)가 `/api/**`를 경로 라우팅 + Redis rate-limit으로 백엔드
(platform/engagement/knowledge/learning-card)에 전달. 단일 API 진입점.

이 패턴은 B4 prod NetworkPolicy(`apps/*/overlays/prod/netpol.yaml`)와 정합한다 —
백엔드 ingress가 `app.kubernetes.io/name: gateway` 파드만 허용하므로, 트래픽은
ALB→gateway→backend 경로로 흐른다.

## staging — ALB 직결 (`staging-ingress.yaml`)
ALB가 서비스별 호스트(`staging-<svc>.<domain>`)로 각 svc에 **직접** 라우팅(gateway 우회).
직접 테스트 편의용. dev의 gateway 패턴과는 다른 철학.

## 치환 플레이스홀더
- `<ACM_ARN>`: `terraform -chdir=infra/aws/dev output` 의 ACM 인증서 ARN.
- `<domain>`: terraform `var.domain_name`.

## 후속 (prod 구성 시)
- gateway prod/staging 오버레이 신설(현재 `apps/gateway/overlays/dev`만 존재).
- **prod gateway NetworkPolicy**: ALB(target-type ip, VPC ENI)→gateway:8080 ingress 허용 +
  gateway→백엔드(intra-ns) egress. B4 prod netpol은 백엔드 측만 gateway 호출자로 한정했고
  gateway 자체 netpol은 prod 배포 경로 확정(이 문서) 후속으로 남겨둠.
- prod ingress(`prod-ingress.yaml`): dev와 동일 Gateway 패턴 권장.
```

- [ ] **Step 2: 커밋**

```bash
git add infra/ingress/README.md
git commit -m "docs(ingress): gateway 패턴 근거 + prod 후속(gateway netpol) 문서화 (B1)"
```

---

## Task 4: 통합 검증 + PR

- [ ] **Step 1: 전체 overlay 렌더 회귀 + lint**

Run:
```bash
cd D:/workspace/final-project-syn/synapse-gitops
for d in apps/*/overlays/*; do kubectl kustomize "$d" >/dev/null 2>&1 && echo "OK $d" || echo "FAIL $d"; done
PY="C:/Users/deepe/AppData/Local/Python/pythoncore-3.14-64/python.exe"
for f in argocd/applicationset.yaml infra/ingress/dev-ingress.yaml; do tr -d '\r' < "$f" > /tmp/lf.yaml; "$PY" -m yamllint -c .yamllint /tmp/lf.yaml && echo "clean: $f"; done
```
Expected: 모든 overlay OK(apps/gateway/overlays/dev 포함), 2개 파일 clean.

- [ ] **Step 2: 푸시 + PR**

```bash
git push -u origin feat/gateway-deploy-path
gh pr create --repo team-project-final/synapse-gitops --base main --head feat/gateway-deploy-path \
  --title "feat: gateway EKS 배포 경로 — Gateway 패턴(ALB→gateway) (B1)" \
  --body "$(cat <<'EOF'
## 요약
gateway(Spring Cloud Gateway)를 dev ApplicationSet에 추가 + ALB Ingress 신설로 EKS 노출 경로 확정. B1.

- **패턴**: ALB(ACM TLS) → gateway service:80 → /api/** 경로 라우팅+rate-limit → 백엔드.
- B4(#104) prod netpol(백엔드 ingress ← gateway)과 정합.
- dev 한정(gateway 오버레이는 dev만). prod/staging gateway 오버레이 + prod gateway netpol은 후속(README 명시).

## 변경
- argocd/applicationset.yaml: `- service: gateway` 추가(image-updater ECR semver 자동).
- infra/ingress/dev-ingress.yaml: 단일 호스트 dev.<domain> → gateway:80.
- infra/ingress/README.md: 패턴 근거 + 후속.

## ⚠️ 의존성
- B2(synapse-gateway#3) 머지로 USER 포함 gateway 이미지가 ECR에 올라온 뒤 배포 권장.
- aws-load-balancer-controller + ACM/도메인(<ACM_ARN>/<domain> 라이브 치환).

## 검증
- apps/gateway/overlays/dev 렌더 OK, 17/17 overlay 회귀 없음, yamllint clean. EKS 런타임은 프로비저닝(A).

## 설계/계획
- spec: docs/superpowers/specs/2026-06-03-gateway-deploy-path-design.md
- plan: docs/superpowers/plans/2026-06-03-gateway-deploy-path.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
Expected: PR URL. CI `validate` 통과 확인.

---

## Self-Review (작성자 체크)

**Spec 커버리지:** 표면1 ApplicationSet gateway 추가 → Task 1 ✓. 표면2 dev ALB Ingress → Task 2 ✓. 표면3 문서 → Task 3 ✓. 단일 PR → Task 4 ✓. B2/B4 의존성·prod 후속 → Task 3 README + PR 본문 ✓.

**플레이스홀더:** `<ACM_ARN>`/`<domain>`은 staging-ingress와 동일한 의도적 라이브 치환 토큰(코드 placeholder 아님).

**일관성:** 서비스명 `gateway`, service port 80→8080, 호스트 `dev.<domain>`, ALB 주석은 staging-ingress와 동일. image-updater는 gateway가 ECR semver라 매트릭스 포함 적합(schema-registry는 제외했던 것과 대비).
