# Runbook: W1 ArgoCD 부트스트랩 실행 가이드

> **대상**: gitops 트랙 담당자 (@VelkaressiaBlutkrone) 또는 후속 환경 부트스트랩 작업자
> **소요 시간**: 약 50~60분 (terraform apply 단계가 가장 김)
> **전제**: PR #6 + PR #7이 main에 머지된 상태 (스펙: [2026-05-16-w1-argocd-bootstrap-design.md](../superpowers/specs/2026-05-16-w1-argocd-bootstrap-design.md))

---

## 0. 준비물 체크리스트

실행 전에 모두 확보:

- [ ] AWS 계정의 IAM 사용자 Access Key + Secret Key (`AdministratorAccess` 또는 동등 권한)
- [ ] 로컬 도구: `aws` CLI, `kubectl`, `terraform`, `argocd` CLI, `jq`, `openssl`, `bash`
- [ ] `gh` CLI 로그인 + 본 레포 admin 권한
- [ ] 작업 디렉토리: `synapse-gitops` 레포 루트, main 최신 sync 완료 (`git pull origin main`)

도구 부재 시:
```bash
# macOS (Homebrew)
brew install awscli kubernetes-cli terraform argocd jq

# Windows (Chocolatey)
choco install awscli kubernetes-cli terraform argocd-cli jq

# Linux
# 각 도구는 공식 문서 참조
```

---

## 1. AWS 크레덴셜 설정 (25분, 첫 실행 시)

AWS 계정만 있고 IAM 사용자 / Access Key / AWS CLI 설정이 아직이라면, 별도 가이드를 따른다:

📖 **[aws-account-setup.md](./aws-account-setup.md)** — Budget 알람 → IAM 사용자 → Access Key → AWS CLI 설치 → configure → 검증까지 1-A~1-F 단계별로 안내.

이미 `aws configure`가 완료됐다면 다음 한 줄로 검증만 하고 Step 2로 진행:

```bash
aws sts get-caller-identity
```

**Expected**: `Arn`이 `arn:aws:iam::<ACCOUNT>:user/synapse-admin` 형식.

**실패 시**:
- `Unable to locate credentials` → `aws configure` 다시 실행 (또는 [aws-account-setup.md](./aws-account-setup.md) 1-E)
- `AccessDenied` → IAM 사용자 권한 점검 (`AdministratorAccess` 또는 EKS/EC2/VPC/RDS/IAM 권한 필요)
- `Arn`이 `:root`로 끝남 → Root 계정으로 작업 중. [aws-account-setup.md](./aws-account-setup.md) 1-B로 가서 IAM 사용자 사용

---

## 2. Terraform 변수 채우기 (8분)

OS별 시크릿 생성 방법(openssl vs PowerShell native vs Git Bash), 비용 최소화 override, gitignore 재검증까지 별도 가이드로 분리:

📖 **[terraform-tfvars-setup.md](./terraform-tfvars-setup.md)** — 2-A 변수 파일 생성 / 2-B 비번 생성 / 2-C 편집 / 2-D gitignore 검증 / 2-E Terraform 설치 확인.

요약: `infra/aws/dev/terraform.tfvars`를 만들고 `rds_password` + `redis_auth_token` 두 시크릿 + 비용 최소화 override 3개(`eks_node_count=2`, `rds_instance_class="db.t3.micro"`, `msk_broker_count=2`) 작성. 시크릿은 1Password 등에 보관 (학습 destroy 후 폐기).

검증: `terraform version` 출력 + `git status`에 `terraform.tfvars`가 보이지 않음.

---

## 3. Terraform Apply (25~45분, 실패 + 재시도 포함)

State backend 사전 생성(S3 bucket + DynamoDB), terraform init/plan/apply 절차, 실제 발생했던 트러블슈팅 케이스(EKS AMI 미지원, RDS parameter group, OpenSearch VPC policy, Free Tier 제약 등)는 별도 가이드로 분리:

📖 **[terraform-apply-step3.md](./terraform-apply-step3.md)** — 3-Pre backend 생성 / 3-A init / 3-B plan / 3-C apply / 3-D 비용 모니터링 / 3-Cleanup destroy. 트러블슈팅 9건.

⚠️ AWS **신규 가입 계정**은 결제수단 verification 완료 전엔 EKS 노드 launch가 막힌다(Free Tier eligible 인스턴스만 허용). 그 경우 destroy 후 verification 대기 또는 kind 로컬 대체.

요약: `terraform init` → `terraform plan -out=tfplan` → `terraform apply tfplan` 후 output에 `argocd_namespace = "argocd"` 표시되면 Step 4로 진행.

---

## 4. kubeconfig 갱신 + 노드 확인 (1분)

```bash
aws eks update-kubeconfig --name synapse-dev --region ap-northeast-2
kubectl config current-context   # arn:aws:eks:ap-northeast-2:...:cluster/synapse-dev

kubectl get nodes
kubectl get pods -n argocd
```

**Expected**:
- 노드 2개 이상 `Ready`
- argocd 네임스페이스에 pod 10여 개 Running (controller, server×3, repo-server×2, applicationset×2, redis-ha×3, dex, notifications)

**실패 시**:
- `error: You must be logged in to the server (Unauthorized)`: kubeconfig가 IAM 권한과 매칭 안 됨. EKS 콘솔의 "Access" 탭에서 IAM 사용자/롤 매핑 추가.
- argocd pod이 `Pending`: 노드 자원 부족. Node group 인스턴스 타입 업그레이드 또는 max_size 증설.

---

## 5. ArgoCD 부트스트랩 (5분)

```bash
bash scripts/bootstrap-argocd.sh
```

스크립트는 8단계로 진행 (각 단계 [OK] 출력):
1. 사전 도구 점검
2. kubeconfig 갱신
3. argocd-server pod readiness 대기 (최대 10분)
4. NLB 호스트 추출 (최대 10분)
5. admin 비번 회전 + AWS Secrets Manager 저장 (`synapse/argocd/admin`)
6. AppProject 적용
7. RBAC + Notifications ConfigMap 적용
8. ApplicationSet 적용 + 5개 Application 등록 검증

**Expected (스크립트 마지막 출력)**:
```
================================================================
 ArgoCD 부트스트랩 완료
================================================================
 UI: https://<nlb-dns>.elb.ap-northeast-2.amazonaws.com
 비번 조회:
   aws secretsmanager get-secret-value --secret-id synapse/argocd/admin ...
 등록된 Application:
 NAME                          ...
 synapse-platform-svc-dev      ...
 synapse-engagement-svc-dev    ...
 ... (총 5개)
================================================================
```

**실패 시**:
- "Application 등록 부족: 0 (기대 5)": ApplicationSet 컨트롤러가 아직 reconcile 안 함. 10초 대기 후 `argocd app list` 직접 확인.
- "초기 secret도, Secrets Manager 항목도 없음": ArgoCD가 이미 다른 비번으로 초기화됨. 수동 복구 — `kubectl -n argocd patch secret argocd-secret -p '{"stringData":{"admin.password":""}}'` 후 재실행.
- NLB 호스트 빈 채로 5분 대기: AWS Load Balancer Controller 미설치 가능성. 옵션 2는 in-tree NLB라 controller 불필요해야 하나, EKS 1.29에서 LoadBalancer Service 동작 확인.

---

## 6. 브라우저 접속 + 로그인 확인 (5분)

1. **NLB 호스트** = 스크립트 출력의 UI URL
2. **admin 비번 조회**:
   ```bash
   aws secretsmanager get-secret-value --secret-id synapse/argocd/admin \
     --region ap-northeast-2 --query SecretString --output text | jq -r .password
   ```
3. 브라우저로 `https://<nlb-dns>` 접속
4. **self-signed 경고 처리**:
   - Chrome/Edge: 고급 → "안전하지 않음으로 진행"
   - Firefox: 고급 → 예외 추가 → 인증서 확인 후 확정
   - Safari: 상세 정보 → "이 웹사이트 방문"
5. `admin` + 위 비번으로 로그인
6. UI에서 다음 확인:
   - 5개 Application 표시: `synapse-platform-svc-dev`, `synapse-engagement-svc-dev`, `synapse-knowledge-svc-dev`, `synapse-learning-card-dev`, `synapse-learning-ai-dev`
   - 각 Application 상태: **OutOfSync** (정상 — base/overlay manifest가 빈 상태)
7. **스크린샷 1장 캡처** (HISTORY 첨부용)

---

## 7. 의도적 오류 PR로 CI 실패 검증 (10분, FR-GO-104 검수)

```bash
git checkout main && git pull
git checkout -b test/intentional-ci-failure
sed -i 's|apiVersion: apps/v1|apiVersion: apps/v999|' apps/platform-svc/base/deployment.yaml
git add apps/platform-svc/base/deployment.yaml
git commit -m "test: intentional invalid apiVersion to verify CI"
git push -u origin test/intentional-ci-failure
gh pr create --title "test: CI failure verification (DO NOT MERGE)" \
  --body "FR-GO-104 검수용. 머지 금지. kubeconform이 잘못된 apiVersion을 잡는지 확인."
gh pr checks --watch
```

**Expected**: `validate` 단계가 FAIL. 로그에 `apps/platform-svc/overlays/dev` 또는 base 빌드 실패 메시지 + `apiVersion: apps/v999` 관련 에러.

**Expected (정리)**:
```bash
gh pr close --delete-branch
git checkout main
```

---

## 8. HISTORY 최종 갱신 (5분)

`docs/project-management/history/HISTORY_gitops.md`의 2026-05-16 섹션에서 다음 자리를 실제 값으로 치환:

```diff
 #### 산출물
 - 디자인 스펙: ...
 - 구현 플랜: ...
- - PR: (PR 번호는 생성 후 추가)
+ - PR #6 (W1 보강), PR #7 (Ruleset 정리), PR #<TEST_PR>(닫힘, CI 실패 검증)

 #### 이벤트
- - 검증: 의도적 오류 PR로 kubeconform CI 실패 확인 (PR 번호는 실행 후 추가)
+ - 검증: 의도적 오류 PR #<TEST_PR>로 kubeconform CI 실패 확인 (스크린샷 첨부: <링크>)
```

```bash
git checkout -b docs/w1-history-finalize
# 위 변경 반영
git add docs/project-management/history/HISTORY_gitops.md
git commit -m "docs(pm): finalize W1 HISTORY with PR numbers and screenshots"
git push -u origin docs/w1-history-finalize
gh pr create --title "docs(pm): finalize W1 HISTORY" --body "Task 14 사용자 액션 결과 반영"
gh pr merge --merge --delete-branch
```

---

## 검증 체크리스트 (Done 표시용)

W1 PRD 검수 기준 최종 검증:

- [ ] FR-GO-101: `kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server | grep Running` 3개 출력
- [ ] FR-GO-102: 브라우저로 NLB URL HTTPS 접속 성공 (self-signed 경고 후) — **부분 충족, 도메인 확보 시 [docs/argocd-tls-migration.md](../argocd-tls-migration.md) 따라 옵션 1 마이그레이션**
- [ ] FR-GO-103: `argocd app list` 출력에 5개 `synapse-*-dev` 표시
- [ ] FR-GO-104: 의도적 오류 PR의 CI `validate`가 FAIL
- [ ] FR-GO-105: main 직접 push 시도가 거부됨 (`git push origin main` from feature branch → blocked)

---

## 트러블슈팅

### terraform apply가 도중에 멈춤

원인 대부분이 AWS 자원 한도 또는 인증. 다음 순서로 진단:

1. `aws sts get-caller-identity` — 크레덴셜 유효성
2. `terraform plan` 다시 — diff가 새로 생기면 외부 변경
3. AWS 콘솔의 Service Quotas + CloudTrail에서 실패 자원 검색

### bootstrap-argocd.sh 5단계에서 멈춤

```bash
# pod 상태 직접 확인
kubectl get pods -n argocd
kubectl describe pod -n argocd <pending-pod>

# Service 상태
kubectl get svc argocd-server -n argocd -o yaml

# AWS 콘솔 EC2 Load Balancers 탭에서 NLB 생성 진행 상황
```

### 브라우저 self-signed 경고를 못 넘김

- Chrome: 주소창에 `thisisunsafe` 직접 타이핑 (페이지 클릭 후)
- 또는 `curl -k https://<nlb-dns>/api/version` 으로 CLI 검증만 진행 후 가이드는 그대로

### 5개 Application이 표시 안 됨

```bash
kubectl get applicationset -n argocd
kubectl describe applicationset synapse-apps -n argocd
# generator 평가 에러 또는 RBAC 거부 확인
```

---

## 실 환경 정리 (학습 완료 후 비용 절감)

```bash
# ArgoCD Application 먼저 삭제 (orphan 자원 방지)
argocd app delete -y synapse-platform-svc-dev synapse-engagement-svc-dev \
  synapse-knowledge-svc-dev synapse-learning-card-dev synapse-learning-ai-dev

kubectl delete applicationset synapse-apps -n argocd

# Terraform destroy
cd infra/aws/dev
terraform destroy
# 약 15분 — EKS, RDS, ElastiCache, MSK, OpenSearch 모두 삭제됨
```

**주의**: `terraform destroy` 후에도 다음은 수동 정리 필요:
- AWS Secrets Manager의 `synapse/argocd/admin` (7일 복구 대기 후 영구 삭제)
- CloudWatch Logs (EKS 로그)
- ECR 이미지 (있다면)

---

## 도움 요청

- 본 runbook의 단계가 막힐 때: HISTORY에 "도움 요청" 항목으로 기록 + Slack #synapse-gitops 채널
- ArgoCD 자체 문제: https://argo-cd.readthedocs.io/
- Terraform AWS provider: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
