# prod NetworkPolicy 조이기 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** prod 5개 per-svc NetworkPolicy의 ingress를 실제 호출자 파드로 한정하고, 외부 0.0.0.0/0:443 egress를 실제 필요한 platform·learning-ai만 유지(나머지 3개 제거)한다.

**Architecture:** gitops 단일 PR. 각 `apps/<svc>/overlays/prod/netpol.yaml`의 ingress `from: [podSelector: {}]`를 호출자 라벨 셀렉터로 교체하고, 외부 443 egress 블록을 서비스별로 유지/제거. intra-ns egress(`podSelector: {}`)·VPC 데이터스토어 egress·DNS는 보수적으로 현행 유지(schema-registry prod 미배포·Redis 불확실성 회피).

**Tech Stack:** Kubernetes NetworkPolicy, Kustomize, yamllint(flow 표기 `{protocol: TCP, port: 8080}`는 브레이스 안쪽 공백 없어 통과 — 동일 스타일 유지).

**환경:** `D:/workspace/final-project-syn/synapse-gitops`, 브랜치 `feat/prod-netpol-tighten`(spec 커밋 `9949906` 포함). 검증은 `kubectl kustomize`. yamllint은 `C:/Users/deepe/AppData/Local/Python/pythoncore-3.14-64/python.exe -m yamllint`(로컬 CRLF의 new-lines 에러는 무시 — CI는 LF).

**호출 그래프(k8s):** gateway→platform·engagement·knowledge·learning-card(8080). knowledge→learning-ai(8090). learning-ai→platform·learning-card(8080). 외부443: platform·learning-ai만.

---

## File Structure

수정:
- `apps/platform-svc/overlays/prod/netpol.yaml` — ingress: gateway+learning-ai. 외부443 유지.
- `apps/engagement-svc/overlays/prod/netpol.yaml` — ingress: gateway. 외부443 제거.
- `apps/knowledge-svc/overlays/prod/netpol.yaml` — ingress: gateway. 외부443 제거.
- `apps/learning-card/overlays/prod/netpol.yaml` — ingress: gateway+learning-ai. 외부443 제거.
- `apps/learning-ai/overlays/prod/netpol.yaml` — ingress: knowledge-svc(8090). 외부443 유지.
- `docs/runbooks/networkpolicy-validation.md` — B4 변경/리스크 addendum.

**공통 패턴.** 모든 파일의 현재 ingress 블록은 동일:
```yaml
  ingress:
    # 같은 네임스페이스(gateway·타 svc)에서만 ingress 허용 — 외부/타 ns 직접 접근 차단
    - from:
        - podSelector: {}
      ports:
        - {protocol: TCP, port: 8080}
```
(learning-ai만 port 8090.)

제거 대상 외부443 egress 블록(해당 서비스에서):
```yaml
    # 외부 HTTPS(Stripe/OAuth/OpenAI/AWS API) — VPC·메타데이터(169.254.169.254) 제외
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except: [10.0.0.0/16, 169.254.169.254/32]
      ports:
        - {protocol: TCP, port: 443}
```

---

## Task 1: platform-svc netpol (ingress 한정, 외부443 유지)

**Files:** Modify `apps/platform-svc/overlays/prod/netpol.yaml`

- [ ] **Step 1: ingress 블록 교체**

위 "공통 패턴"의 ingress 블록을 다음으로 교체:
```yaml
  ingress:
    # gateway(공개 경로) + learning-ai(노트 조회)만 허용
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: gateway
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: learning-ai
      ports:
        - {protocol: TCP, port: 8080}
```
egress는 변경 없음(외부443 유지).

- [ ] **Step 2: 렌더 확인**

Run: `kubectl kustomize apps/platform-svc/overlays/prod | grep -A12 "ingress:"`
Expected: from에 gateway + learning-ai podSelector 2개, port 8080. egress에 0.0.0.0/0:443 블록 여전히 존재.

- [ ] **Step 3: 커밋**

```bash
git add apps/platform-svc/overlays/prod/netpol.yaml
git commit -m "feat(netpol): platform-svc ingress를 gateway+learning-ai로 한정 (B4)"
```

---

## Task 2: engagement-svc netpol (ingress: gateway, 외부443 제거)

**Files:** Modify `apps/engagement-svc/overlays/prod/netpol.yaml`

- [ ] **Step 1: ingress 블록 교체**

"공통 패턴" ingress 블록을 다음으로 교체:
```yaml
  ingress:
    # gateway(공개 경로)에서만 허용
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: gateway
      ports:
        - {protocol: TCP, port: 8080}
```

- [ ] **Step 2: 외부443 egress 블록 제거**

위 "제거 대상 외부443 egress 블록"(주석 줄 포함)을 파일에서 삭제. DNS·intra-ns·VPC 데이터스토어 egress는 유지.

- [ ] **Step 3: 렌더 확인**

Run: `kubectl kustomize apps/engagement-svc/overlays/prod`
Expected: ingress from에 gateway만. egress에 `0.0.0.0/0` 블록이 **없음**(VPC ipBlock 10.0.0.0/16은 유지).

- [ ] **Step 4: 커밋**

```bash
git add apps/engagement-svc/overlays/prod/netpol.yaml
git commit -m "feat(netpol): engagement-svc ingress gateway 한정 + 외부443 egress 제거 (B4)"
```

---

## Task 3: knowledge-svc netpol (ingress: gateway, 외부443 제거)

**Files:** Modify `apps/knowledge-svc/overlays/prod/netpol.yaml`

- [ ] **Step 1: ingress 블록 교체** (Task 2 Step 1과 동일 내용)

"공통 패턴" ingress 블록을 다음으로 교체:
```yaml
  ingress:
    # gateway(공개 경로)에서만 허용
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: gateway
      ports:
        - {protocol: TCP, port: 8080}
```

- [ ] **Step 2: 외부443 egress 블록 제거** (Task 2 Step 2와 동일 — 외부443 블록 삭제)

- [ ] **Step 3: 렌더 확인**

Run: `kubectl kustomize apps/knowledge-svc/overlays/prod`
Expected: ingress from gateway만, egress에 `0.0.0.0/0` 없음(VPC 10.0.0.0/16:443은 유지 — OpenSearch용).

- [ ] **Step 4: 커밋**

```bash
git add apps/knowledge-svc/overlays/prod/netpol.yaml
git commit -m "feat(netpol): knowledge-svc ingress gateway 한정 + 외부443 egress 제거 (B4)"
```

---

## Task 4: learning-card netpol (ingress: gateway+learning-ai, 외부443 제거)

**Files:** Modify `apps/learning-card/overlays/prod/netpol.yaml`

- [ ] **Step 1: ingress 블록 교체**

"공통 패턴" ingress 블록을 다음으로 교체:
```yaml
  ingress:
    # gateway(공개 경로) + learning-ai(카드 저장)만 허용
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: gateway
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: learning-ai
      ports:
        - {protocol: TCP, port: 8080}
```

- [ ] **Step 2: 외부443 egress 블록 제거** (Task 2 Step 2와 동일)

- [ ] **Step 3: 렌더 확인**

Run: `kubectl kustomize apps/learning-card/overlays/prod`
Expected: ingress from gateway+learning-ai, egress에 `0.0.0.0/0` 없음.

- [ ] **Step 4: 커밋**

```bash
git add apps/learning-card/overlays/prod/netpol.yaml
git commit -m "feat(netpol): learning-card ingress gateway+learning-ai 한정 + 외부443 egress 제거 (B4)"
```

---

## Task 5: learning-ai netpol (ingress: knowledge-svc 8090, 외부443 유지)

**Files:** Modify `apps/learning-ai/overlays/prod/netpol.yaml`

learning-ai의 현재 ingress 블록은 port **8090**임에 주의:
```yaml
  ingress:
    # 같은 네임스페이스(gateway·타 svc)에서만 ingress 허용 — 외부/타 ns 직접 접근 차단
    - from:
        - podSelector: {}
      ports:
        - {protocol: TCP, port: 8090}
```

- [ ] **Step 1: ingress 블록 교체**

```yaml
  ingress:
    # knowledge-svc(시맨틱 검색)만 허용 — gateway는 learning-ai를 직접 호출하지 않음
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: knowledge-svc
      ports:
        - {protocol: TCP, port: 8090}
```
egress 변경 없음(외부443 유지 — OpenAI/Anthropic).

- [ ] **Step 2: 렌더 확인**

Run: `kubectl kustomize apps/learning-ai/overlays/prod | grep -A10 "ingress:"`
Expected: from knowledge-svc, port 8090. egress에 0.0.0.0/0:443 유지.

- [ ] **Step 3: 커밋**

```bash
git add apps/learning-ai/overlays/prod/netpol.yaml
git commit -m "feat(netpol): learning-ai ingress를 knowledge-svc로 한정 (B4)"
```

---

## Task 6: Runbook addendum

**Files:** Modify `docs/runbooks/networkpolicy-validation.md`

- [ ] **Step 1: 파일 끝에 B4 섹션 추가**

먼저 파일 내용을 읽어 형식을 맞춘 뒤, 끝에 다음 섹션 추가:
```markdown
## B4 — ingress 호출자 한정 + 외부443 차등 (2026-06-03)

per-svc netpol을 cookie-cutter(ns 전체 ingress + 전 서비스 외부443)에서 호출 그래프 기반으로 조임:
- ingress `from`: platform←gateway,learning-ai / engagement←gateway / knowledge←gateway /
  learning-card←gateway,learning-ai / learning-ai←knowledge-svc.
- 외부 0.0.0.0/0:443: platform·learning-ai만 유지, engagement·knowledge·learning-card 제거.
- intra-ns egress(`podSelector {}`)·VPC 데이터스토어 egress는 보수적으로 유지.

### EKS 프로비저닝 시 확인
- **gateway 의존성(B1)**: ingress가 `app.kubernetes.io/name: gateway` 라벨 의존. gateway가 prod에
  배포되어야 공개 API 경로가 열림. gateway 파드 라벨이 정확히 그 값인지 확인.
- **외부443 제거 영향**: engagement/knowledge/learning-card가 향후 AWS SDK(CloudWatch/S3/SQS) 등
  외부 호출을 추가하면 차단됨 → 해당 netpol에 외부443 재추가 또는 VPC 엔드포인트 사용.
- **VPC CNI 정책 컨트롤러** 활성 선행(이 문서 상단 절차). 미활성 시 정책 무시.
- inter-svc egress는 intra-ns 전체 허용이라 별도 조정 불필요(SR/신규 svc 대비). 추후 추가 조이기 시
  schema-registry(prod 배포 시)·Redis 사용 서비스 매핑 후 진행.
```

- [ ] **Step 2: 커밋**

```bash
git add docs/runbooks/networkpolicy-validation.md
git commit -m "docs(runbook): B4 netpol 조이기 변경/EKS 검증 항목 추가"
```

---

## Task 7: 통합 검증 + PR

- [ ] **Step 1: 전체 prod netpol 렌더 + 차등 확인**

Run:
```bash
cd D:/workspace/final-project-syn/synapse-gitops
for s in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  echo "=== $s ==="
  kubectl kustomize "apps/$s/overlays/prod" | grep -E "app.kubernetes.io/name:|0.0.0.0/0|port: 80" | grep -vE "part-of|managed-by"
done
```
Expected: platform/learning-ai 렌더에 `0.0.0.0/0` 존재, engagement/knowledge/learning-card엔 없음. ingress from 라벨이 설계표와 일치.

- [ ] **Step 2: 전체 overlay 렌더 회귀 + yamllint(LF)**

```bash
for d in apps/*/overlays/*; do kubectl kustomize "$d" >/dev/null 2>&1 && echo "OK $d" || echo "FAIL $d"; done
PY="C:/Users/deepe/AppData/Local/Python/pythoncore-3.14-64/python.exe"
for f in apps/platform-svc/overlays/prod/netpol.yaml apps/engagement-svc/overlays/prod/netpol.yaml apps/knowledge-svc/overlays/prod/netpol.yaml apps/learning-card/overlays/prod/netpol.yaml apps/learning-ai/overlays/prod/netpol.yaml; do tr -d '\r' < "$f" > /tmp/lf.yaml; "$PY" -m yamllint -c .yamllint /tmp/lf.yaml && echo "clean: $f"; done
```
Expected: 모든 overlay OK, 5개 netpol clean.

- [ ] **Step 3: 푸시 + PR**

```bash
git push -u origin feat/prod-netpol-tighten
gh pr create --repo team-project-final/synapse-gitops --base main --head feat/prod-netpol-tighten \
  --title "feat(netpol): prod ingress 호출자 한정 + 외부443 차등 (B4)" \
  --body "$(cat <<'EOF'
## 요약
#101 cookie-cutter netpol(ns 전체 ingress + 전 서비스 외부443)을 호출 그래프 기반으로 조임. B4.

| svc | ingress from | 외부 443 |
|-----|------|------|
| platform-svc | gateway, learning-ai | 유지 |
| engagement-svc | gateway | 제거 |
| knowledge-svc | gateway | 제거 |
| learning-card | gateway, learning-ai | 제거 |
| learning-ai | knowledge-svc (8090) | 유지 |

intra-ns egress + VPC 데이터스토어 egress는 보수적으로 유지(schema-registry prod 미배포·Redis 불확실성).

## ⚠️ 의존성
- gateway가 prod 미배포(B1) → ingress의 gateway 라벨은 배포 전까지 매칭 0(공개 경로 비활성, 라벨 기반이라 무중단 실현).
- VPC CNI 정책 컨트롤러 활성 선행.

## 검증
- 5개 prod netpol kustomize 렌더 + 차등 확인, yamllint clean. EKS 런타임은 프로비저닝(A)/B1 후.

## 설계/계획
- spec: docs/superpowers/specs/2026-06-03-prod-netpol-tighten-design.md
- plan: docs/superpowers/plans/2026-06-03-prod-netpol-tighten.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
Expected: PR URL. CI `validate` 통과 확인.

---

## Self-Review (작성자 체크)

**Spec 커버리지:** ingress 호출자 한정 5개 → Task 1-5 ✓. 외부443 제거 3개 → Task 2·3·4 ✓. 외부443 유지 2개 → Task 1·5(변경 안 함) ✓. intra-ns/VPC 유지 → 전 태스크 egress 미변경 ✓. Runbook 리스크 → Task 6 ✓. 단일 PR → Task 7 ✓.

**플레이스홀더:** 없음. 각 ingress/egress 블록 실제 YAML 제공.

**일관성:** 호출자 라벨 `app.kubernetes.io/name: <svc>` 전 태스크 통일. 포트 8080(learning-ai 8090). flow 표기 `{protocol: TCP, port: N}` 기존 스타일 유지. egress 외부443 블록은 platform·learning-ai에서만 보존.
