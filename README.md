# synapse-gitops

ArgoCD ApplicationSet + Kustomize 기반 GitOps 매니페스트 레포.
Synapse 백엔드 5개 앱(platform/engagement/knowledge/learning-card/learning-ai)을
EKS dev/staging/prod 환경에 자동 배포한다.

## 디렉토리

```
synapse-gitops/
├── apps/                          # Kustomize manifest (5개 svc × base + overlays/{dev,staging,prod})
├── argocd/                        # ArgoCD AppProject + ApplicationSet + bootstrap
│   ├── projects.yaml
│   ├── applicationset.yaml
│   └── bootstrap/
├── infra/aws/dev/                 # dev 환경 Terraform (EKS + VPC + RDS + ArgoCD)
├── scripts/
│   ├── bootstrap-argocd.sh        # ArgoCD 1회 부트스트랩 (admin 회전 + ApplicationSet 적용)
│   └── setup-branch-protection.sh # main 브랜치 보호 룰 적용
├── .github/workflows/             # CI (validate-manifests, parse-workflow)
└── docs/                          # 가이드 + project-management
```

## 환경

| 환경 | 외부 노출 | TLS | 자동 sync |
|---|---|---|---|
| dev | NLB (AWS DNS) | self-signed | yes |
| staging | (W3 추가) | (W3) | (W3) |
| prod | (W4 추가) | (W4) | no — Manual |

도메인 + ACM 적용은 [docs/argocd-tls-migration.md](docs/argocd-tls-migration.md) 참조.

## 신규 환경 부트스트랩 (1회 실행)

```bash
# 1) AWS 크레덴셜
aws configure  # region: ap-northeast-2

# 2) 인프라 생성
cd infra/aws/dev
cp terraform.tfvars.example terraform.tfvars  # 변수 채우기
terraform init && terraform apply
cd ../../..

# 3) kubeconfig
aws eks update-kubeconfig --name synapse-dev --region ap-northeast-2

# 4) ArgoCD 부트스트랩
bash scripts/bootstrap-argocd.sh

# 5) 브랜치 보호
REVIEWS=0 bash scripts/setup-branch-protection.sh
```

자세한 절차/검증은 [scripts/bootstrap-argocd.sh](scripts/bootstrap-argocd.sh)의 8단계 로그 참조.

## CI 검증

PR이 올라오면 `.github/workflows/validate-manifests.yml`이 자동 실행:
1. **yamllint** (`.yamllint` 룰)
2. **kustomize build** — 모든 `apps/*/overlays/*/kustomization.yaml` 빌드
3. **kubeconform** — 빌드 결과를 Kubernetes 스키마(+ CRD 카탈로그)로 검증

로컬 재현: [CONTRIBUTING.md](CONTRIBUTING.md#로컬-검증-pr-올리기-전-필수) 참조.

main은 보호되어 있어 CI 통과 + 리뷰 후에만 머지된다. (`scripts/setup-branch-protection.sh`)

## 새 앱 추가

[argocd/README.md](argocd/README.md#새-앱-추가-절차) 참조.

## ArgoCD 접속

```bash
# UI 호스트
kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# admin 비번 조회
aws secretsmanager get-secret-value --secret-id synapse/argocd/admin \
  --region ap-northeast-2 --query SecretString --output text | jq -r .password
```

## 문서

### Runbook (작업 단계별)
- **[dev-machine-setup.md](docs/runbooks/dev-machine-setup.md)** — 새 PC/환경에서 작업 이어받기 (도구 설치 + 인증 + 시크릿 인계)
- [w1-argocd-bootstrap-runbook.md](docs/runbooks/w1-argocd-bootstrap-runbook.md) — W1 EKS 부트스트랩 메인 흐름
- [aws-account-setup.md](docs/runbooks/aws-account-setup.md) — Step 1 AWS 계정/IAM/CLI 셋업
- [terraform-tfvars-setup.md](docs/runbooks/terraform-tfvars-setup.md) — Step 2 변수 파일 + 시크릿 생성
- [terraform-apply-step3.md](docs/runbooks/terraform-apply-step3.md) — Step 3 init/plan/apply + 트러블슈팅 14건
- [kind-local-bootstrap.md](docs/runbooks/kind-local-bootstrap.md) — kind 로컬 클러스터 대체 path (비용 0)

### 참고
- [Project Management](docs/project-management/) — KICKOFF, PRD, TASK, WORKFLOW, HISTORY
- [argocd/README.md](argocd/README.md) — ApplicationSet 구조 + 트러블슈팅
- [CONTRIBUTING.md](CONTRIBUTING.md) — 브랜치/커밋/PR 절차
- [docs/argocd-tls-migration.md](docs/argocd-tls-migration.md) — 도메인 확보 후 TLS 전환
- [docs/aws-infra-provisioning-workflow-guide.md](docs/aws-infra-provisioning-workflow-guide.md)
- [docs/docker-compose-workflow-guide.md](docs/docker-compose-workflow-guide.md)
