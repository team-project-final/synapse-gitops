# Runbook: Terraform 변수 파일 설정 (Step 2 상세)

> **소요 시간**: 약 8분
> **결과**: `infra/aws/dev/terraform.tfvars`가 작성되고, 시크릿 두 개가 git에 노출되지 않은 상태로 로컬에 저장됨
> **상위 문서**: [w1-argocd-bootstrap-runbook.md](./w1-argocd-bootstrap-runbook.md) Step 2

본 문서는 [step1-aws-account-setup.md](./step1-aws-account-setup.md)에서 AWS CLI 설정을 마친 직후의 단계.

---

## 2-A. 변수 파일 생성

레포 루트에서 `infra/aws/dev`로 이동 후 example 복사.

### Linux / macOS / Git Bash (Windows)
```bash
cd infra/aws/dev
cp terraform.tfvars.example terraform.tfvars
```

### Windows PowerShell
```powershell
cd infra\aws\dev
Copy-Item terraform.tfvars.example terraform.tfvars
```

`*.tfvars`는 `infra/aws/dev/.gitignore`에 등록되어 있어 git에 들어가지 않는다 (단 `terraform.tfvars.example`은 예외로 추적됨).

---

## 2-B. 강력한 비번 두 개 생성

RDS Postgres와 ElastiCache Redis 두 곳에 시크릿이 필요하다. 절대 같은 값을 재사용하지 말 것.

### Linux / macOS / Git Bash (openssl 사용)

```bash
# RDS Postgres 비번 (24자, 영숫자만 — / @ " 등 RDS 금지 문자 제외)
openssl rand -base64 24 | tr -d '/@"' | head -c 24
echo

# Redis AUTH token (32자, 영숫자만)
openssl rand -base64 32 | tr -d '/=+@"' | head -c 32
echo
```

### Windows PowerShell (native, openssl 없을 때)

```powershell
# RDS Postgres 비번 (24자)
Write-Host "RDS:   $(-join ((48..57 + 65..90 + 97..122) | Get-Random -Count 24 | % {[char]$_}))"

# Redis AUTH token (32자)
Write-Host "REDIS: $(-join ((48..57 + 65..90 + 97..122) | Get-Random -Count 32 | % {[char]$_}))"
```

### 비번 보관

각 출력값을 **1Password / Bitwarden / 메모장**에 임시 저장. 학습 destroy 후엔 폐기.

```
RDS password: <첫 번째 출력>
Redis token:  <두 번째 출력>
```

### 시크릿 규칙 (참고)
- **RDS Postgres**: 8~128자, ASCII 출력 문자, `/ @ " 공백` 금지
- **ElastiCache Redis AUTH**: 16~128자, 영숫자 + `! & # $ ^ < > -` 허용

---

## 2-C. terraform.tfvars 편집

에디터 열기:

### Linux / macOS / Git Bash
```bash
vim terraform.tfvars      # 또는 nano, code 등
```

### Windows PowerShell
```powershell
notepad terraform.tfvars        # 메모장
# 또는 VS Code 사용 시:
code terraform.tfvars
```

다음 내용으로 **교체** (예시 placeholder를 실제 값으로):

```hcl
# 기본 환경
aws_region  = "ap-northeast-2"
environment = "dev"

# 시크릿 (반드시 2-B에서 생성한 실제 값으로 교체)
rds_password     = "<2-B의 RDS 비번 24자>"
redis_auth_token = "<2-B의 Redis 토큰 32자>"

# 비용 최소화 override (학습 후 즉시 destroy 전제)
eks_node_count     = 2             # 3 → 2 (월 ~$60 → ~$40)
rds_instance_class = "db.t3.micro" # medium → micro (월 ~$50 → ~$15)
msk_broker_count   = 2             # 3 → 2 (월 ~$75 → ~$50)
```

### 비용 영향 요약

위 override를 적용한 학습 시나리오:
- 사용 시간당 약 $0.30
- 1일 사용 + destroy 시 약 **$7~8**
- destroy 잊을 경우 월 약 $230 (1-A의 Budget $10 알람이 80%에서 이메일)

### 다른 변수는 default로 둠

`variables.tf`에 정의된 나머지 변수(`vpc_cidr`, `eks_node_instance_type`, `rds_db_name` 등)는 default로 충분하다. 학습 후 사용 패턴이 명확해지면 override.

---

## 2-D. 시크릿이 git에 안 들어가는지 재검증

```bash
cd ../../..   # 레포 루트로 (또는 PowerShell: cd ..\..\..)
git status
```

**Expected**: `infra/aws/dev/terraform.tfvars`가 출력에 **없음** (Untracked로도, modified로도). gitignore 정상.

만약 출력에 보이면:
```bash
cat infra/aws/dev/.gitignore | head -3
# *.tfvars
# !terraform.tfvars.example
# *.tfstate
```
이 출력이 나와야 정상. 안 나오면 알려주세요.

**시크릿이 staged 됐을 때 응급 처치**:
```bash
git rm --cached infra/aws/dev/terraform.tfvars
git status   # 더 이상 안 보여야 함
```
그리고 이미 commit/push 된 적이 있는지 확인. push됐다면 시크릿이 노출된 상태이므로 즉시 회전(2-B 재실행 + RDS/Redis 비번 변경) 필요.

---

## 2-E. Terraform 설치 확인

```bash
terraform version
```

**Expected**: `Terraform v1.x.x`

### 설치 안 됐을 때

#### Windows
```powershell
# winget (Windows 10/11)
winget install --id Hashicorp.Terraform -e
```
또는 https://developer.hashicorp.com/terraform/install 에서 Windows AMD64 ZIP 다운로드 → 압축 풀어서 `terraform.exe`를 PATH(예: `C:\Tools\terraform\`)에 두기.

#### macOS
```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

#### Linux
```bash
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```

설치 후 **새 터미널을 열고** `terraform version` 재확인.

---

## 자주 막히는 지점

### PowerShell에서 `openssl` not recognized
PowerShell에는 openssl이 기본 없음. 본 문서의 PowerShell 변종 명령을 사용하거나, **Git Bash**(Git for Windows에 번들)에서 동작. PowerShell에서도 `& "C:\Program Files\Git\usr\bin\openssl.exe" rand -base64 24` 처럼 풀 경로로 호출하면 동작.

### 비번에 `/` 또는 `@` 같은 문자가 섞여서 RDS가 거부
`tr` 명령(또는 PowerShell의 영숫자만 사용 변종)으로 제외했으니, 다시 생성하면 OK.

### `cd infra/aws/dev`가 안 됨
현재 위치가 레포 루트가 아닐 가능성. `pwd` (Linux/Mac/Git Bash) 또는 `Get-Location` (PowerShell)로 확인. 레포 루트(예: `D:\workspace\final-project-syn\synapse-gitops`)에서 시작.

### `terraform.tfvars`가 git status에 빨간색으로 표시
gitignore 동작 안 함. `infra/aws/dev/.gitignore`가 존재하고 `*.tfvars` 패턴이 있는지 확인. 단 한 번이라도 `git add infra/aws/dev/terraform.tfvars`로 강제 추가하면 gitignore이 무력해짐 — `git rm --cached`로 해제.

### Terraform 설치 후에도 `terraform: command not found`
- 새 터미널 열기 (PATH 갱신)
- Windows: 시스템 환경 변수 PATH에 terraform.exe 경로 추가되어 있는지 확인
- macOS: `which terraform`으로 위치 확인 (`/usr/local/bin/terraform` 정상)

---

## 다음 단계

`terraform version`까지 정상 출력되면 Step 2 완료. 상위 runbook의 [Step 3 (terraform apply)](./w1-argocd-bootstrap-runbook.md#3-terraform-apply-2025분)로 진행.
