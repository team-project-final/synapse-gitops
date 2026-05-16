# Runbook: AWS 계정 초기 설정 (Step 1 상세)

> **대상**: AWS 콘솔/CLI 사용 경험이 적은 작업자
> **소요 시간**: 약 25분
> **결과**: `aws sts get-caller-identity`가 `synapse-admin` IAM 사용자로 응답
> **상위 문서**: [w1-argocd-bootstrap-runbook.md](./w1-argocd-bootstrap-runbook.md) Step 1

본 문서는 AWS 계정 생성 직후의 상태에서 시작해, Terraform과 부트스트랩 스크립트가 동작할 수 있는 상태까지 끌어올린다.

---

## ⚠️ 비용 안내

본 작업으로 만들어지는 AWS 자원은 **시간당 비용이 발생**한다. 학습 완료 후 즉시 `terraform destroy`를 실행하지 않으면 월 약 $300 청구될 수 있다. 다음 두 가지를 반드시 지킨다:

1. **1-A 단계의 Budget 알람을 먼저 설정**한다.
2. 학습 완료 즉시 `cd infra/aws/dev && terraform destroy`를 실행한다.

추정 자원별 비용:

| 자원 | 시간당 (USD) | 월 환산 |
|---|---|---|
| EKS Control Plane | $0.10 | ~$73 |
| EC2 노드 (t3.medium × 2) | $0.083 | ~$60 |
| NAT Gateway | $0.045 + 트래픽 | ~$35 |
| RDS (db.t3.micro) | ~$0.02 | ~$15 |
| ElastiCache Redis (cache.t3.micro) | ~$0.02 | ~$15 |
| MSK (kafka.t3.small × 2) | ~$0.10 | ~$75 |
| OpenSearch (t3.small.search) | ~$0.04 | ~$30 |
| **합계 (대략)** | **~$0.40/시간** | **~$300/월** |

---

## 1-A. AWS Budget 알람 설정 (5분)

학습 중 비용 초과를 막는 안전망. 한도 도달 시 이메일 알림.

1. AWS 콘솔 로그인 → 우상단 본인 ID/Account 클릭 → **"Billing and Cost Management"**
   - 또는 상단 검색창에 "Billing" 입력 후 클릭
2. 좌측 메뉴 **"Budgets"** → **"Create budget"** 버튼
3. **"Use a template (simplified)"** 선택 → **"Monthly cost budget"**
4. 입력 값:
   - **Budget name**: `synapse-gitops-learning`
   - **Budgeted amount**: `10` (USD, 학습 1일 분량으로 충분)
   - **Email recipients**: 본인 이메일
5. **Create budget** 클릭
6. ✅ 완료. 80% 도달 + 100% 초과 시 두 번 이메일 알림.

> 콘솔이 한국어 등 다른 언어인 경우: 우상단 언어 선택 메뉴에서 English로 바꾸면 본 가이드와 메뉴 이름이 일치한다.

---

## 1-B. IAM 사용자 생성 (5분)

**왜 필요한가**: AWS 가입 시 만들어진 Root 계정은 권한이 무제한이라 실수가 곧 재앙이 된다. 일상 작업은 IAM 사용자로 한다.

1. 상단 검색창에 **"IAM"** 입력 → IAM 서비스 클릭
2. 좌측 메뉴 **"Users"** → **"Create user"** 버튼
3. 입력:
   - **User name**: `synapse-admin`
   - **"Provide user access to the AWS Management Console"** 체크박스는 **해제** (CLI만 쓸 거라 콘솔 로그인은 Root 계정으로 충분)
4. **Next** 클릭
5. **"Permissions options"**에서 **"Attach policies directly"** 선택
6. **"Permissions policies"** 검색창에 `AdministratorAccess` 입력 → 결과의 **AdministratorAccess** 체크
7. **Next** → 태그 생략 → **Create user**
8. ✅ 사용자 목록에 `synapse-admin`이 표시되면 완료.

> 보안 강화: 학습 후 destroy까지 끝나면, 이 IAM 사용자도 비활성화하거나 정책을 `ReadOnlyAccess`로 다운그레이드해 둔다.

---

## 1-C. Access Key 발급 (3분)

⚠️ **Secret Access Key는 이 화면을 떠나면 다시 못 본다.** 반드시 임시 보관소(메모장 + 1Password 등)에 즉시 복사한다.

1. IAM → Users → **`synapse-admin`** 클릭
2. 상단 탭에서 **"Security credentials"** 선택
3. 페이지 중간 **"Access keys"** 섹션의 **"Create access key"** 버튼
4. **Use case**에서 **"Command Line Interface (CLI)"** 선택
5. 하단 경고문 동의 체크 → **Next**
6. Description tag는 생략 → **Create access key**
7. 결과 페이지:
   - **Access key**: `AKIA...` (20자, 자동 표시)
   - **Secret access key**: `wXyZ...` (40자, **"Show"** 버튼 클릭 시 표시)
8. **반드시 두 값을 즉시 안전한 곳에 복사** + **`.csv` 다운로드** 버튼으로 백업
9. **Done** 클릭하고 페이지를 떠난다.

> 백업해둔 `.csv`는 1-E 단계 후 즉시 삭제(또는 1Password에만 저장).

---

## 1-D. AWS CLI 설치 확인 (5분, OS별)

현재 터미널에서 우선 확인:
```bash
aws --version
```

### Case A: `aws-cli/2.x.x` 이상 출력
이미 설치됨. **1-E로 진행**.

### Case B: "command not found" 또는 v1.x 출력

#### Windows

**옵션 1 — MSI installer (가장 간단)**:
1. https://awscli.amazonaws.com/AWSCLIV2.msi 다운로드
2. 다운로드된 `AWSCLIV2.msi` 더블클릭 → Next 연타 → Finish
3. **새 터미널을 열고** `aws --version` 재확인

**옵션 2 — winget (Windows 10/11)**:
```powershell
winget install --id Amazon.AWSCLI -e
```
설치 후 **새 터미널 창**에서 확인.

#### macOS
```bash
brew install awscli
```

#### Linux (x86_64)
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

설치 후 새 터미널에서 `aws --version` 확인.

---

## 1-E. aws configure 실행 (3분)

⚠️ 이 명령은 **prompt 4개를 받는다**. 별도 터미널에서 실행하거나, 본 세션에서 `! aws configure` 형식으로 실행한다. 입력만 받고 출력은 prompt뿐이라 Secret이 화면에 찍히지 않는다.

```bash
aws configure
```

순서대로 입력:

| Prompt | 입력 값 |
|---|---|
| `AWS Access Key ID [None]:` | 1-C의 Access key (`AKIA...`) 붙여넣기 + Enter |
| `AWS Secret Access Key [None]:` | 1-C의 Secret access key 붙여넣기 + Enter |
| `Default region name [None]:` | `ap-northeast-2` (서울 리전) |
| `Default output format [None]:` | `json` |

설정 파일 저장 위치:
- Windows: `C:\Users\<사용자명>\.aws\credentials`, `C:\Users\<사용자명>\.aws\config`
- macOS/Linux: `~/.aws/credentials`, `~/.aws/config`

---

## 1-F. 검증 (1분)

```bash
aws sts get-caller-identity
```

**Expected**:
```json
{
    "UserId": "AIDA...EXAMPLE",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/synapse-admin"
}
```

핵심 확인:
- `Arn` 끝이 `user/synapse-admin` (Root 계정으로 작업하면 끝이 `:root`로 나옴 — 그 경우 1-B로 돌아가 IAM 사용자로 다시 설정)
- `Account`가 본인 AWS 계정 번호 (Billing 화면에서 확인 가능)

이 출력이 나오면 Step 1 완료. 상위 runbook의 [Step 2](./w1-argocd-bootstrap-runbook.md#2-terraform-변수-채우기-3분)로 진행.

---

## 자주 막히는 지점

### 1-D 후에도 `command not found`
- 새 터미널을 다시 열어본다 (PATH 갱신은 새 세션에서 적용).
- Windows: 시스템 환경 변수 PATH에 `C:\Program Files\Amazon\AWSCLIV2\` 또는 `C:\Program Files\Amazon\AWSCLI\` 가 있는지 확인.
- macOS: `/usr/local/bin/aws`가 있는지 확인 (`which aws`).

### 1-F에서 `InvalidClientTokenId`
Access Key를 잘못 복사(앞뒤 공백, 마지막 줄바꿈 포함 등). `aws configure`를 다시 실행해 정확히 붙여넣는다. 그래도 안 되면 1-C로 가서 새 Access Key를 발급(기존 키는 같은 IAM 사용자에서 비활성화/삭제).

### 1-F에서 `ExpiredToken` 또는 `SignatureDoesNotMatch`
로컬 시계가 NTP와 어긋남. Windows: `w32tm /resync` (관리자 PowerShell). macOS: `sudo sntp -sS time.apple.com`. Linux: `sudo systemctl restart systemd-timesyncd`.

### 1-B에서 IAM 메뉴가 안 보임
Root 계정이 아닐 가능성. 우상단 사용자 ID 클릭 후 어떤 계정으로 로그인 중인지 확인. Root 계정으로 로그인해서 IAM 사용자를 만들어야 한다.

### 1-A의 Budgets 메뉴가 회색 처리됨
Account가 Billing 권한이 없는 IAM 사용자. Root 계정으로 다시 로그인 후 1-A부터 진행.

---

## Step 1 후속: 비용 모니터링 습관

학습 진행 중에 다음 습관을 둔다:

- 매시간 한 번 Budget 콘솔에서 spent 확인
- `terraform destroy` 직후에도 AWS 콘솔에서 EKS / RDS / NAT Gateway 자원이 진짜 사라졌는지 확인 (orphan 자원 방지)
- 학습 종료 후 IAM 사용자는 정책을 `ReadOnlyAccess`로 다운그레이드하거나 비활성화
