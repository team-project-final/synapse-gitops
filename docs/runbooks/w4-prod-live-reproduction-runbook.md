# W4 prod 라이브 재현 Runbook

> **목적**: W4 prod 거버넌스는 이미 라이브 1회로 증명됨(FR-402/403/407/408). 본 런북은 **prod 5/5 Healthy + 롤백 라이브 검증(FR-404/405/406)** 을 완주하기 위한 재현 절차다.
> **결정 근거**: HISTORY D-042 / `specs/2026-05-27-w4-prod-design.md` / 메모리 `w4-prod-handoff`
> **비용**: 라이브 재현 프로파일 ~$0.55/hr (증설분 포함). 완주 후 반드시 `terraform destroy`.

---

## 0. 사전 점검 (비용 0)

- [ ] orphan 자원 선점검: `aws ec2 describe-nat-gateways --filter Name=state,Values=available` → 방치 NAT GW 없는지 (과거 ~$13 누적 사례)
- [ ] `terraform.tfvars` = **라이브 재현 프로파일(B)** 인지 확인 (`tfvars.example` 참조):
  - `eks_node_count = 4`, `eks_node_instance_type = "t3.large"`, `rds_instance_class = "db.t3.small"`
  - 이유: dev(5)+staging(10)+prod(15)=30 앱 파드 + 시스템 ~30-40 동시 수용. 비용 절감 프로파일(node 2/t3.medium/db.t3.micro)은 노드 maxSize=3·RDS ~112 conn으로 prod 5/5 차단.
- [ ] `terraform -chdir=infra/aws/dev fmt -check && terraform -chdir=infra/aws/dev validate` (validate는 `init -backend=false` 선행)

## 1. 인프라 기동 (과금 시작)

- [ ] **D-039 ESO role 충돌 선처리**: `terraform import aws_iam_role.eso synapse-dev-eso-role` 또는 기존 수동 role/policy 삭제 (`infra/aws/dev/eso-irsa.tf:4-6` 주석)
- [ ] `cd infra/aws/dev && terraform apply` (라이브 재현 프로파일, ~58리소스)
- [ ] `scripts/bring-up.sh` — ArgoCD/ESO/SSM 터널/access-entry/SG/dev·staging 부트스트랩 (W3 검증 11 phase)
  - EKS API 프라이빗 → bastion SSM 터널 필수 (`scripts/lib/eks-tunnel.sh`)

## 2. prod 사전조건 (라이브)

- [ ] **AWS SM 시크릿 21개** `synapse/prod/{app}/*` 생성 (ESO `synapse/*` 정책이 이미 커버 — W3 A2):
  - platform-svc 14 (db-password·redis-auth-token·jwt-secret·aes-secret-key·jwt-private/public-key·stripe-api-key·stripe-webhook-secret·google/github/apple-client-id/secret)
  - engagement-svc 1 (db-password) · knowledge-svc 2 (db-password·s3-access-key)
  - learning-card 2 (api-key·**공유** knowledge-svc/db-password) · learning-ai 2 (openai-api-key·db-password)
  - ⚠️ platform-svc Stripe price ID는 prod price로 치환 (overlay placeholder)
- [ ] **`synapse_prod` DB 생성**: 공유 RDS에 `CREATE DATABASE synapse_prod;` (클러스터 내 `kubectl run --image=postgres:16` psql 파드로 — 노드 SG가 RDS:5432 접근)
- [ ] **prod 이미지 ECR push**: 5개 svc `prod-latest` 태그. **빠른 방법(검증됨)**: dev-latest 서버사이드 리태그 — `aws ecr batch-get-image --image-ids imageTag=dev-latest` → `aws ecr put-image --image-tag prod-latest --image-manifest <manifest>` (Docker 불필요, prod=동일 이미지+overlay config)
- [ ] (선택) 실 Route53 도메인/ACM — 없으면 FR-404는 port-forward/readiness probe 대체

> **⚠️ 라이브 재현 학습 (2026-06-01, D-043) — 반드시 선처리:**
> 1. **platform-svc 스키마 시드**: prod 프로파일이 Hibernate `ddl-auto: validate`(Flyway 미실행)라 빈 `synapse_prod`에서 `missing table` 크래시. → DB 생성 직후 `pg_dump --schema-only --no-owner synapse | psql -d synapse_prod -v ON_ERROR_STOP=0`로 스키마 시드(다른 4개 svc는 auto-create라 무관). 또는 platform-svc Flyway를 prod에서 활성화.
> 2. **RDS 연결 용량**: db.t3.small(~225 conn)은 dev(5)+staging(10)+prod(15) **동시 운용 시 부족**(`remaining connection slots reserved` FATAL). → 셋 다 띄우려면 **db.t3.medium**(~450) 권장, 아니면 prod 데모 시 dev/staging ApplicationSet 일시 제거(`kubectl delete applicationset synapse-apps synapse-apps-staging`)로 연결 확보(재적용으로 복원).

## 3. prod 배포 + 검증 (FR-404)

- [ ] prod 매니페스트 적용: `kubectl apply -f argocd/projects.yaml -f argocd/bootstrap/rbac-cm.yaml -f argocd/bootstrap/argocd-cm.yaml -f argocd/applicationset-prod.yaml`
- [ ] `argocd account update-password --account gitops-admin`
- [ ] FR-402: `argocd app list -p synapse-prod` → 5개 **OutOfSync** (수동 게이트)
- [ ] FR-403: 일반 계정 `argocd account can-i sync ...` → **no** / gitops-admin → **yes**
- [ ] FR-404: gitops-admin 으로 5개 `argocd app sync` → `kubectl get pods -n synapse-prod` **5개 svc Running(replicas=3) = 15파드 5/5 Healthy**
- [ ] 논리분리 스모크: `kubectl exec -n synapse-prod deploy/platform-svc -- printenv | grep -E "DATABASE_NAME|SPRING_DATA_REDIS_DATABASE"` → `synapse_prod` / `1`
- [ ] 엔드포인트 200: port-forward 또는 도메인 → `/actuator/health` 200

## 4. 롤백 라이브 검증 (FR-405/406)

- [ ] FR-405: staging에서 무해한 변경 sync 후 `argocd app history` → `argocd app rollback <app> <직전-id>` → Synced/Healthy (1-step)
- [ ] FR-406: 테스트 커밋 `git revert` → revert PR → main 머지 → sync(staging auto / prod gitops-admin 수동) → 복원 확인
- [ ] (재확인) FR-407 일일 백업 / FR-408 복구 — 이미 증명, 재현 시 스모크

## 5. 종료 (과금 차단)

- [ ] `cd infra/aws/dev && terraform destroy -auto-approve` — S3 state bucket + DynamoDB lock만 유지
- [ ] destroy 실패 시(VPC DependencyViolation = EKS auto-SG 잔재): 수동 SG 삭제 후 재시도
- [ ] 종료 후 orphan 재점검 (§0)

## 6. 검증 결과 기록

- [ ] FR-404/405/406 결과 → TASK/WORKFLOW_W4 체크 갱신 + HISTORY 기록 (D-042 후속)
- [ ] RTO/RPO 측정값 + team-lead 사인오프
