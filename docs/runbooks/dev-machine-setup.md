# Runbook: 새 PC / 환경 온보딩 (작업 이어받기)

> **목적**: 다른 PC 또는 새 환경에서 synapse-gitops 작업을 그대로 이어갈 수 있도록 동일 환경 + 도구 + 자격증명을 갖추는 절차.
> **소요 시간**: 약 1~2시간 (도구 설치 포함)
> **결과**: 현재 PC와 동일한 작업 상태에서 다음 step부터 즉시 진행 가능

본 문서는 W1 작업 중 발견된 모든 환경 셋업 요건을 통합한다. step별 상세 가이드는 각 `docs/runbooks/*.md` 문서를 참조하고, 본 문서는 entry point + 종합 체크리스트 역할.

---

## 0. 작업 진행 상태 파악 (가장 먼저)

새 PC에서 무엇부터 시작할지 정하려면 현재 진행 상태를 먼저 확인.

### 0-1. 핵심 문서 위치
- 트랙 정의: [docs/project-management/task/TASK_gitops.md](../project-management/task/TASK_gitops.md) — 12 Step Status
- 주차별 체크: [docs/project-management/workflow/WORKFLOW_gitops_W*.md](../project-management/workflow/) — Step별 체크박스
- 의사결정/이벤트 이력: [docs/project-management/history/HISTORY_gitops.md](../project-management/history/HISTORY_gitops.md) — D-001 ~ D-008
- 트랙 범위: [docs/project-management/scope/SCOPE_gitops.md](../project-management/scope/SCOPE_gitops.md)

### 0-2. 최근 활동 확인
```bash
git log --oneline -20
gh pr list --state merged --limit 15
gh pr list --state open
```

### 0-3. 다음 작업 path 결정
HISTORY 가장 최근 섹션을 읽고 다음 path 선택:
- **B-1 (EKS 실 환경)**: AWS 결제수단 verification 완료된 후 → [w1-argocd-bootstrap-runbook.md](./w1-argocd-bootstrap-runbook.md) Step 1~7 그대로 진행
- **B-2 (kind 로컬)**: 비용 없이 실증 또는 학습 → [kind-local-bootstrap.md](./kind-local-bootstrap.md)
- **W2 진행**: [docs/project-management/prd/PRD_W2.md](../project-management/prd/PRD_W2.md)부터 시작

---

## 1. 필수 도구 통합 설치 (OS별)

W1 모든 step에서 등장한 도구를 OS별로 통합 정리. 새 PC에서는 다음 모두 설치되어 있어야 함.

| 도구 | 용도 | Windows (winget) | macOS (brew) | Linux |
|---|---|---|---|---|
| Git | 버전관리 | `winget install --id Git.Git` | `brew install git` | apt/yum |
| Git Bash | bash 환경 | Git for Windows에 번들 | (기본 bash) | (기본 bash) |
| GitHub CLI | PR/이슈/Actions | `winget install --id GitHub.cli` | `brew install gh` | apt/yum |
| AWS CLI v2 | AWS 자원 관리 | `winget install --id Amazon.AWSCLI` | `brew install awscli` | curl install |
| Terraform | IaC | `winget install --id Hashicorp.Terraform` | `brew install hashicorp/tap/terraform` | apt (HashiCorp repo) |
| kubectl | K8s CLI | `winget install --id Kubernetes.kubectl` | `brew install kubectl` | apt/curl |
| Docker Desktop | 컨테이너 런타임 | https://docker.com/products/docker-desktop | https://docker.com/... | docker engine |
| kind | 로컬 K8s | `winget install --id Kubernetes.kind` | `brew install kind` | curl |
| argocd CLI | ArgoCD 조작 | https://github.com/argoproj/argo-cd/releases | `brew install argocd` | curl |
| jq | JSON 처리 | `winget install --id jqlang.jq` | `brew install jq` | apt/yum |
| openssl | 비번 생성 | Git Bash에 번들 | (기본) | (기본) |

### 일괄 설치 (Windows PowerShell 관리자)
```powershell
winget install --id Git.Git -e
winget install --id GitHub.cli -e
winget install --id Amazon.AWSCLI -e
winget install --id Hashicorp.Terraform -e
winget install --id Kubernetes.kubectl -e
winget install --id Kubernetes.kind -e
winget install --id jqlang.jq -e
# Docker Desktop은 GUI 인스톨러
# argocd CLI는 GitHub Release에서 binary 직접 다운로드
```

### 일괄 설치 (macOS)
```bash
brew install git gh awscli hashicorp/tap/terraform kubectl kind argocd jq
# Docker Desktop: https://docker.com/products/docker-desktop
```

### 일괄 설치 (Linux Debian/Ubuntu)
```bash
sudo apt-get update
sudo apt-get install -y git curl jq
# 각 도구별 공식 가이드:
# - gh: https://cli.github.com/
# - aws cli: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
# - terraform: https://developer.hashicorp.com/terraform/install
# - kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
# - kind: https://kind.sigs.k8s.io/docs/user/quick-start/
# - argocd: https://github.com/argoproj/argo-cd/releases
# - docker: https://docs.docker.com/engine/install/
```

### 도구별 검증 명령 (일괄)
```bash
git --version
gh --version
aws --version
terraform version
kubectl version --client
kind version
argocd version --client
jq --version
docker version
openssl version
```

모두 정상 출력되면 도구 셋업 완료.

---

## 2. 레포 clone + GitHub 인증

### 2-1. gh CLI 인증
```bash
gh auth login
```
인터랙티브 prompt:
- GitHub.com 선택
- HTTPS 프로토콜 선택
- Git credential helper 사용 Yes
- 브라우저로 device flow 인증 (또는 Personal Access Token)
- 권한: `repo`, `read:org`, `workflow` 포함

검증:
```bash
gh auth status
```

`Logged in to github.com as <username>` + token scopes에 `repo`, `workflow` 표시.

### 2-2. 레포 clone
```bash
gh repo clone team-project-final/synapse-gitops
cd synapse-gitops
git remote -v
```

`origin https://github.com/team-project-final/synapse-gitops.git` 확인.

### 2-3. git 사용자 설정 (글로벌이면 생략)
```bash
git config user.name "VelkaressiaBlutkrone"
git config user.email "<본인 GitHub 이메일>"
```

---

## 3. AWS 자격증명 (B-1 또는 B-2의 일부 단계에서 필요)

### 3-1. IAM 사용자가 이미 있을 때 (이전 PC에서 만들었음)
Access Key는 PC당 새로 만들 필요 없음. 이전 PC의 `.csv` 백업이나 1Password에서 복원 후:
```bash
aws configure
# Access Key ID:     <기존 키>
# Secret Access Key: <기존 비번>
# region:            ap-northeast-2
# output:            json
```

검증:
```bash
aws sts get-caller-identity
```
`Arn`이 `arn:aws:iam::<ACCOUNT>:user/synapse-admin` 확인.

### 3-2. 새 IAM 사용자가 필요할 때 (첫 셋업)
[step1-aws-account-setup.md](./step1-aws-account-setup.md) 1-A ~ 1-F 그대로 따라 진행.

### 3-3. Access Key를 잃어버렸을 때
1. AWS 콘솔 → IAM → Users → `synapse-admin`
2. Security credentials → 기존 Access key 비활성화 또는 삭제
3. Create access key (1-C 다시) → 새 Key를 새 PC `aws configure`에 입력

### 3-4. AWS Secrets Manager의 ArgoCD admin 비번
EKS 부트스트랩 후 admin 비번은 `synapse/argocd/admin` secret에 저장됨. 새 PC에서 조회:
```bash
aws secretsmanager get-secret-value --secret-id synapse/argocd/admin \
  --region ap-northeast-2 --query SecretString --output text | jq -r .password
```
이 값으로 ArgoCD CLI 로그인 가능. 이전 PC의 로컬 백업은 불필요.

---

## 4. 시크릿 / state 인계

### 4-1. Terraform state
**중요**: state는 S3 backend(`synapse-terraform-state`)에 있어 PC 이동과 무관. 새 PC에서 `terraform init`만 하면 자동으로 state 가져옴. 별도 인계 불필요.

### 4-2. `terraform.tfvars`
시크릿(rds_password, redis_auth_token)이 들어있어 git에 안 들어감(.gitignore). 새 PC에서 다시 생성:
- 이미 자원이 있는 경우(부분 또는 전체 apply 됨): 같은 비번을 다시 입력해야 함. 1Password / Bitwarden에서 복원.
- 자원 없는 새 시작: [step2-terraform-tfvars.md](./step2-terraform-tfvars.md)로 새 비번 생성.

### 4-3. kubeconfig
EKS 클러스터 접근용. 새 PC에서:
```bash
aws eks update-kubeconfig --name synapse-dev --region ap-northeast-2
```
이전 PC의 kubeconfig 복사는 불필요. 위 명령이 새 entry를 `~/.kube/config`에 추가.

### 4-4. ArgoCD 자체 로그인
ArgoCD CLI에 새 PC에서 다시 로그인:
```bash
NLB_HOST=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
PW=$(aws secretsmanager get-secret-value --secret-id synapse/argocd/admin \
       --query SecretString --output text | jq -r .password)
argocd login "$NLB_HOST" --username admin --password "$PW" --insecure --grpc-web
```

### 4-5. 1Password / 비밀 저장소 추천 항목

다른 PC로 이동 시 다음을 미리 1Password 등에 백업:
- AWS IAM `synapse-admin` Access Key + Secret
- 학습 destroy 후 자원이 다시 만들어졌을 때의 새 RDS / Redis 비번
- GitHub Personal Access Token (gh CLI device flow 안 쓸 때만)

⚠️ git에 직접 commit 금지 — 모두 `.gitignore` 처리되어 있음.

---

## 5. 작업 path별 entry point

| Path | 진입 문서 | 사전 조건 |
|---|---|---|
| **W1 마무리 / 검수** | [w1-argocd-bootstrap-runbook.md](./w1-argocd-bootstrap-runbook.md) | 도구 설치 + AWS 인증 + 자원 destroy 안 됐으면 그대로 |
| **B-1 EKS 실 환경 재시도** | [step1-aws-account-setup.md](./step1-aws-account-setup.md) → [step2-terraform-tfvars.md](./step2-terraform-tfvars.md) → [step3-terraform-apply.md](./step3-terraform-apply.md) | 결제수단 verification 완료 |
| **B-2 kind 로컬 학습** | [kind-local-bootstrap.md](./kind-local-bootstrap.md) | Docker Desktop 실행 중 |
| **W2 시작** | [PRD_W2.md](../project-management/prd/PRD_W2.md) → [WORKFLOW_gitops_W2.md](../project-management/workflow/WORKFLOW_gitops_W2.md) | W1 검수 결론 확인 (HISTORY) |

---

## 6. 자주 만나는 OS별 차이

### Windows PowerShell vs Git Bash
- 본 레포의 bash 스크립트(`scripts/*.sh`): Git Bash에서 직접 실행, PowerShell에서는 `bash scripts/...` 형태로 호출
- `openssl` 등 unix 도구: PowerShell에 없음, Git Bash에서 동작
- 경로 구분자: PowerShell은 `\`, Git Bash는 `/` (단 modern 도구는 둘 다 허용)

### macOS vs Linux
- 대부분 동일. `sed -i`는 macOS에서 인자 다름 (`sed -i ''` 필요)
- Homebrew (macOS) vs apt/yum (Linux) 차이

### 권한 (Linux/macOS)
- 스크립트 실행 전: `chmod +x scripts/*.sh`

---

## 7. 새 PC에서 작업 시작 체크리스트

복사해서 한 줄씩 체크:

```
[ ] 도구 설치 완료: git/gh/aws/terraform/kubectl/kind/argocd/jq/docker
[ ] 각 도구 버전 명령으로 검증 통과
[ ] gh CLI 로그인 (repo + workflow scope)
[ ] 레포 clone + main 최신 sync (git pull)
[ ] HISTORY/TASK/WORKFLOW 최근 섹션 읽고 다음 path 결정
[ ] AWS 인증 (필요 시 Access Key 복원 또는 새 발급)
[ ] AWS Secrets Manager에서 비번 복원 (이전 자원 살아있을 때)
[ ] 진입 문서(path별) 첫 단계부터 진행
[ ] 발생하는 문제는 HISTORY + 해당 step runbook 트러블슈팅 섹션 참조
```

---

## 8. 도움 요청 / 문제 해결

- 도구 설치 / 환경 차이: 본 문서 1~3절
- 작업 step별 막힘: 각 step 가이드의 트러블슈팅 섹션
- AWS 비용 / 청구 우려: [step1-aws-account-setup.md](./step1-aws-account-setup.md) Budget 알람 / 비용 추정
- ArgoCD 자체: https://argo-cd.readthedocs.io/
- Terraform AWS provider: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- HISTORY에 "도움 요청" 항목 기록 (다음 작업자가 참고할 수 있도록)

---

## 9. 정기 점검 (PC 사용 끝낼 때)

PC 사용 종료 직전:
- [ ] 작업 결과를 PR로 main에 머지하거나 feature 브랜치로 push (로컬 commit이 남지 않도록)
- [ ] `terraform destroy` (학습용 자원이 떠있으면 비용 출혈)
- [ ] kind cluster 정리: `kind delete cluster --name synapse-dev`
- [ ] `terraform.tfvars` 파일의 비번이 1Password에 저장돼 있는지 재확인
- [ ] HISTORY에 오늘 진행 내용 한 줄 추가 (다음 작업자/본인의 참고용)
