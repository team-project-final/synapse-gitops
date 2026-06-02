# ArgoCD 부트스트랩 → dev/staging 5/5 (#91) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 재apply된 dev 클러스터에 ArgoCD 부트스트랩 후 dev/staging 서비스 5/5(Synced·Healthy·Running·ExternalSecret·롤백) 검증 (#91, FR-TL-402).

**Architecture:** 기존 `scripts/bring-up.sh` 오케스트레이터를 PR #90과 정합(중복 phase 제거 + #88 ConfigMap phase 추가) + RDS db.t3.medium 증설. 라이브 window에서 bring-up 실행 → `verify-argocd-deploy.sh` 5/5. bring-up은 SSM 터널로 로컬 kubectl/argocd 사용.

**Tech Stack:** bash(bring-up.sh), Terraform, AWS EKS(access entry)/SSM 터널, ArgoCD(HA install), External Secrets(helm), kustomize, MSK.

**참조 spec:** `docs/superpowers/specs/2026-06-02-argocd-bootstrap-dev-staging-design.md`. **브랜치:** `infra/argocd-bootstrap-dev-staging`(spec 커밋됨).

**운영 학습(재사용)**: SSM 셸 HOME 불일치→KUBECONFIG 명시. 터널 kubeconfig=`/tmp/kubeconfig-synapse-tunnel.yaml`(phase_tunnel가 export).

---

## File Structure

| 파일 | 책임 | 변경 |
|---|---|---|
| `infra/aws/dev/terraform.tfvars` | RDS db.t3.small→medium | Modify |
| `scripts/bring-up.sh` | PHASES 정합 + phase 함수(제거 2 / 추가 1) | Modify |

라이브 검증은 코드 변경 없음(기존 `verify-argocd-deploy.sh` 실행).

---

## Phase 0 — 오프라인 정합 (무과금)

### Task 1: RDS 증설 + bring-up.sh 정합

**Files:**
- Modify: `infra/aws/dev/terraform.tfvars` (RDS class)
- Modify: `scripts/bring-up.sh` (PHASES + phase 함수)

- [ ] **Step 1: RDS 클래스 증설**

`infra/aws/dev/terraform.tfvars`에서:
```
rds_instance_class     = "db.t3.small"
```
→
```
rds_instance_class     = "db.t3.medium"
```

- [ ] **Step 2: PHASES 배열에서 access-entry·sg 제거 + kafka-config 추가**

`scripts/bring-up.sh` line 14:
```bash
PHASES=(terraform eks-auth access-entry sg tunnel argocd eso oidc-fix manifests image-updater observability status)
```
→
```bash
PHASES=(terraform eks-auth tunnel argocd eso oidc-fix kafka-config manifests image-updater observability status)
```
(`access-entry`·`sg` 제거 — PR #90 terraform이 소유. `kafka-config`를 `oidc-fix`와 `manifests` 사이 삽입.)

- [ ] **Step 3: phase_access_entry() 함수 정의 삭제**

`scripts/bring-up.sh`에서 `phase_access_entry() { ... }` 전체(약 79~91행, `me=$(aws sts get-caller-identity...)` 포함, cluster-admin associate까지) 삭제. 근거: `#87` `bootstrap_cluster_creator_admin_permissions=true`로 클러스터 생성자(synapse-admin)가 이미 admin.

- [ ] **Step 4: phase_sg() 함수 정의 삭제**

`scripts/bring-up.sh`에서 `phase_sg() { ... }` 전체(약 92~110행, `_sg_ingress` 헬퍼 포함) 삭제. 근거: `#89` terraform이 cluster SG ingress 소유.

- [ ] **Step 5: phase_kafka_config() 함수 추가**

`phase_oidc_fix() { ... }` 정의 **뒤**, `phase_manifests()` **앞**에 추가:
```bash
phase_kafka_config() {
  # #88: kafka-brokers ConfigMap을 3개 ns에 선생성 (앱 배포 전 KAFKA_BROKERS 주입원).
  # bring-up은 kubectl 스타일 — k8s-kafka-config terraform 모듈과 동일 리소스(터널 kubeconfig).
  if $DRY_RUN; then echo "+ kafka-config: ns×3 + kafka-brokers ConfigMap (브로커=terraform output)"; return; fi
  local brokers
  brokers=$(terraform -chdir=$TFDIR output -raw msk_bootstrap_brokers_tls)
  for ns in synapse-dev synapse-staging synapse-prod; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
    kubectl create configmap kafka-brokers -n "$ns" \
      --from-literal=KAFKA_BROKERS="$brokers" --dry-run=client -o yaml | kubectl apply -f -
  done
  ok "kafka-brokers ConfigMap 3 ns 적용"
}
```

- [ ] **Step 6: bash 구문 검사**

Run: `bash -n scripts/bring-up.sh && echo SYNTAX_OK`
Expected: `SYNTAX_OK` (구문 에러 없음).

- [ ] **Step 7: dry-run으로 phase 순서 확인**

Run: `bash scripts/bring-up.sh --dry-run 2>&1 | grep -E "phase:|kafka-config|access-entry|: sg"`
Expected: phase 순서에 `kafka-config` 등장, `access-entry`·`sg` **부재**. (dry-run은 무과금 — 각 phase의 `+ ...` 미리보기만.)

- [ ] **Step 8: 제거된 함수 참조 잔존 없음 확인**

Run: `grep -nE "phase_access_entry|phase_sg\b|_sg_ingress" scripts/bring-up.sh || echo NONE_LEFT`
Expected: `NONE_LEFT` (정의·호출 모두 제거됨; `phase_${p//-/_}` 디스패치는 PHASES에서 빠졌으므로 호출 안 됨).

- [ ] **Step 9: Commit**

```bash
git add infra/aws/dev/terraform.tfvars scripts/bring-up.sh
git commit -m "feat(infra): #91 bring-up.sh PR#90 정합(access-entry·sg phase 제거·kafka-config 추가) + RDS db.t3.medium"
```

---

## Phase 1 — 라이브 검증 window (유료 1회)

### Task 2: 부트스트랩 실행 (terraform→manifests, dev)

- [ ] **Step 1: bring-up 실행 (manifests까지)**

Run: `bash scripts/bring-up.sh --to manifests 2>&1 | tee /tmp/bringup.log`
Expected: 각 phase OK — terraform apply(RDS medium 포함) → tunnel 연결 → argocd rollout → eso → oidc-fix → kafka-config(ConfigMap 3 ns) → manifests(projects+applicationset). 마지막 "phase 'manifests'까지 완료". (image-updater/observability는 5/5 핵심 아니라 제외.)

- [ ] **Step 2: ArgoCD App 등록 + ExternalSecret 확인 (터널 유지 필요 → --from으로 재연결)**

bring-up 종료로 터널이 내려가므로, 검증은 터널을 다시 올려 수행. Run:
```bash
source scripts/lib/eks-tunnel.sh && tunnel_up
kubectl -n argocd get applications
kubectl -n synapse-dev get externalsecrets
```
Expected: 5개 dev App 등록(dev=auto-sync), ExternalSecret `SecretSynced`. (터널은 이후 Task 3에서도 사용 — 동일 셸 유지 또는 재연결.)

---

### Task 3: dev 5/5 검증 (+ platform-svc caveat)

- [ ] **Step 1: dev App Synced·Healthy 대기**

Run(터널 유지 상태): `kubectl -n argocd get applications -o wide`
Expected: 5개 App Sync=Synced. Health=Healthy 대기(이미지 pull+기동). 미Healthy 앱은 Step 2 진단.

- [ ] **Step 2: platform-svc 스키마 caveat 처리 (미Healthy 시에만)**

platform-svc가 `CrashLoopBackOff`(로그에 `missing table`/Hibernate validate)면 dev 프로파일이 validate임 → 스키마 시드:
```bash
# RDS에 dev DB 스키마가 비어 있으면, 기존 스키마 덤프로 시드 (W4 D-043 절차)
# (dev 프로파일이 ddl-auto=update/Flyway면 이 단계 불필요 — 로그로 먼저 확인)
kubectl -n synapse-dev logs deploy/platform-svc --tail=30
```
ddl-auto면 자동 생성되어 무관. validate면 W4 런북의 `pg_dump --schema-only` 시드 후 `kubectl -n synapse-dev rollout restart deploy/platform-svc`.

- [ ] **Step 3: verify-argocd-deploy.sh synapse-dev 5/5**

Run: `bash ../synapse-shared/scripts/verify-argocd-deploy.sh synapse-dev 2>&1 | tee /tmp/verify-dev.log; grep -E "PASS|FAIL|PASS_COUNT|총|Summary" /tmp/verify-dev.log | tail`
Expected: 모든 체크 **[PASS]**(App Synced·Healthy / Pod Running·restarts≤3 / ExternalSecret SecretSynced), FAIL 0. 증거 캡처.

---

### Task 4: staging 수동 Sync 5/5 + 롤백

- [ ] **Step 1: staging App 수동 Sync**

staging AppProject는 manual sync. Run(터널 유지):
```bash
for svc in engagement-svc knowledge-svc learning-ai learning-card platform-svc; do
  argocd app sync synapse-$svc-staging --insecure 2>/dev/null || kubectl -n argocd patch app synapse-$svc-staging --type merge -p '{"operation":{"sync":{}}}'
done
kubectl -n argocd get applications | grep staging
```
Expected: 5개 staging App Synced 진행. (argocd CLI 미로그인 시 kubectl patch로 sync 트리거.)

- [ ] **Step 2: verify-argocd-deploy.sh synapse-staging 5/5**

Run: `bash ../synapse-shared/scripts/verify-argocd-deploy.sh synapse-staging 2>&1 | tee /tmp/verify-staging.log; grep -E "PASS|FAIL" /tmp/verify-staging.log | tail`
Expected: staging 5/5 PASS, FAIL 0.

- [ ] **Step 3: 롤백 1회 (<3분)**

dev engagement-svc 1-step 롤백(History) — W4 FR-405 패턴:
```bash
argocd app history synapse-engagement-svc-dev --insecure
argocd app rollback synapse-engagement-svc-dev <직전ID> --insecure
# 또는 git revert→sync. 시간 측정(<3분).
kubectl -n synapse-dev get pods -l app.kubernetes.io/name=engagement-svc
```
Expected: 롤백 후 Synced/Healthy 복귀, 3분 이내. 증거 캡처.

---

### Task 5: 마감 — 이슈 close + destroy + HISTORY + PR

- [ ] **Step 1: 이슈 #91 결과 코멘트**

```bash
gh issue comment 91 --body "라이브 검증 완료 (PR <#>): bring-up.sh(PR#90 정합)로 ArgoCD HA+ESO+5 App 부트스트랩. verify-argocd-deploy.sh synapse-dev 5/5·synapse-staging 5/5·롤백<3분. RDS db.t3.medium로 dev+staging 연결 수용. [platform-svc caveat 결과 기재]"
```

- [ ] **Step 2: destroy (과금 차단)**

Run: `bash scripts/bring-up.sh --destroy 2>&1 | tail -3; aws kafka list-clusters --query 'length(ClusterInfoList)' --output text`
Expected: `Destroy complete!`(또는 terraform destroy 완료), MSK count 0.

- [ ] **Step 3: HISTORY D-046 + commit**

`docs/project-management/history/HISTORY_gitops.md`에 2026-06-02 항목 추가(D-046): bring-up 정합·RDS medium·dev/staging 5/5·롤백 결과, platform-svc caveat 처리 여부. Commit:
```bash
git add docs/project-management/history/HISTORY_gitops.md
git commit -m "docs(infra): #91 ArgoCD 부트스트랩 dev/staging 5/5 라이브 검증 — HISTORY D-046"
```

- [ ] **Step 4: push + PR**

```bash
git push -u origin infra/argocd-bootstrap-dev-staging
gh pr create --base main --title "feat(infra): ArgoCD 부트스트랩 dev/staging 5/5 (#91)" --body "bring-up.sh PR#90 정합 + RDS medium. dev/staging 5/5+롤백 라이브 검증 후 destroy. Closes #91"
```

---

## Self-Review (작성자 점검)

**Spec coverage:**
- §4 컴포넌트1(RDS medium·access-entry/sg 제거·kafka-config 추가) → Task 1 ✅
- §5 컴포넌트2(bring-up 실행, dev Synced/Healthy) → Task 2 ✅
- §6 컴포넌트3(dev 5/5·staging 5/5·롤백·platform-svc caveat) → Task 3·4 ✅
- §7 컴포넌트4(close·destroy·HISTORY·PR) → Task 5 ✅
- §8 의존(터널 안정성→--from 재개, #88 터널 경로→kubectl로 회피) → Task 2·phase_kafka_config ✅

**Placeholder scan:** TBD/TODO 없음. 모든 코드 스텝 실제 bash/명령. (Task 5 PR번호·platform-svc caveat 결과는 실행시점 확정 — 정상.)

**Type consistency:** phase 이름 `kafka-config`↔디스패치 `phase_kafka_config`(`${p//-/_}`) 일치. ConfigMap 이름 `kafka-brokers`·키 `KAFKA_BROKERS`(phase_kafka_config ↔ PR#90 overlay configMapKeyRef 일치). 터널 kubeconfig 경로 `/tmp/kubeconfig-synapse-tunnel.yaml`(eks-tunnel.sh export) 일치. `verify-argocd-deploy.sh` 경로 `../synapse-shared/scripts/`(shared repo).

**리스크(spec §8):** 터널 장시간 유지 — 끊기면 `bring-up.sh --from manifests`로 재개. platform-svc validate면 스키마 시드(Task 3 Step 2). bring-up은 kubectl 스타일이라 phase_kafka_config도 kubectl(터널 KUBECONFIG 정합, k8s-kafka-config 모듈과 동일 리소스).
