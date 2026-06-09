# #156 staging 전용 RDS 분리 — 설계

> **작성**: 2026-06-09 · **상태**: 설계 승인됨 · **이슈**: #156 · **다음**: writing-plans
> **결정**: 인스턴스 레벨 격리(staging 전용 별도 RDS 인스턴스) — 사용자 승인

## 1. 목적

staging 5앱(engagement·knowledge·learning-ai·learning-card·platform)이 현재 **dev RDS 인스턴스 + dev와 동일 DB명**(`synapse_platform` 등)을 공유 → 환경 격리 0. staging 전용 RDS 인스턴스를 신설해 **인스턴스 레벨 격리**를 확보한다(항목8, W3/W4 감사 §4).

## 2. 현재 상태 (근거)

- dev RDS: `aws_db_instance.main`(`synapse-dev-postgres`, db.t3.medium, engine 16.9, `infra/aws/dev/rds.tf`).
- 서비스별 DB 5종(`synapse_platform`/`synapse_engagement`/`synapse_knowledge`/`synapse_learning`/`synapse_ai`)은 psql 수동 `CREATE DATABASE`로 생성(PR #136 전제). 4 Spring=Flyway 자동 스키마, learning-ai=Python/asyncpg 자동.
- staging 5앱 오버레이가 `synapse-dev-postgres.c7emuq20mhyy.ap-northeast-2.rds.amazonaws.com:5432/synapse_<svc>`를 직접 참조(`apps/*/overlays/staging/kustomization.yaml`). gateway(redis만)·frontend(DB 없음)는 무관.

## 3. 설계

### Part 1 — Terraform (`infra/aws/dev/`)

신규 리소스 `aws_db_instance.staging`:
- identifier `synapse-staging-postgres`, engine postgres 16.9
- `instance_class = var.rds_staging_instance_class` (신규 변수, default **db.t3.small** — dev medium 대비 비용 절감)
- 재사용: `db_subnet_group_name = aws_db_subnet_group.main.name`, `vpc_security_group_ids = [aws_security_group.rds.id]`(EKS 노드 5432 ingress 이미 허용), `parameter_group_name = aws_db_parameter_group.postgres16.name`(force_ssl=1)
- `username = var.rds_username`, `password = var.rds_password`(dev와 동일 마스터 자격 재사용), `db_name = var.rds_db_name`
- allocated_storage 20 / max 50 / gp3 / storage_encrypted=true / publicly_accessible=false / multi_az=false / skip_final_snapshot=true / apply_immediately=true / backup_retention 1

`variables.tf`: 신규
```hcl
variable "rds_staging_instance_class" {
  description = "Staging RDS instance class (separate from dev)"
  type        = string
  default     = "db.t3.small"
}
```

`outputs.tf`: 신규
```hcl
output "rds_staging_endpoint" {
  description = "Staging RDS PostgreSQL endpoint"
  value       = aws_db_instance.staging.endpoint
}
```

### Part 2 — DB 생성 (라이브, 1회)

staging RDS 기동 후 psql 파드로 DB 5종 생성(dev와 동일 절차, `w4-prod-live-reproduction-runbook.md` 패턴):
```bash
# 클러스터 내 psql 파드(노드 SG가 staging RDS:5432 접근). PGHOST=staging 엔드포인트.
for db in synapse_platform synapse_engagement synapse_knowledge synapse_learning synapse_ai; do
  psql -h <staging-endpoint> -U synapse_admin -d synapse -c "CREATE DATABASE $db;"
done
```
platform-svc staging 프로파일 ddl-auto가 `validate`이면 스키마 시드 필요(`pg_dump --schema-only synapse_platform(dev) | psql synapse_platform(staging)`); Flyway/`update`면 자동.

### Part 3 — 오버레이 전환 (5앱)

`apps/{engagement-svc,knowledge-svc,learning-ai,learning-card,platform-svc}/overlays/staging/kustomization.yaml`의 DB 호스트를 dev→staging 엔드포인트로:
- `DATABASE_HOST`: `synapse-dev-postgres.c7emuq20mhyy…` → `synapse-staging-postgres.<신규>.ap-northeast-2.rds.amazonaws.com`
- `SPRING_DATASOURCE_URL` / `DB_URL`(platform) / `LEARNING_AI_DATABASE_URL`(learning-ai, asyncpg 포맷) 의 호스트 동일 치환
- DB명(`synapse_*`)·포트(5432)·유저는 유지
- 엔드포인트는 terraform apply 후 확정값을 하드코딩(dev 패턴 — RDS 생성 서브도메인은 사전 미상)

## 4. 구현/검증 타이밍

라이브 윈도우 3건(#144/#155/#157) 완료 후 **같은 윈도우**에서:
1. `terraform -chdir=infra/aws/dev apply`(증분 — staging RDS 신설, ~10분)
2. DB 5종 생성(psql 파드)
3. staging 오버레이 5앱 엔드포인트 치환 → PR → main 머지
4. ArgoCD staging 앱 sync → DB 연결·Healthy 확인(평면 격리: dev RDS와 다른 인스턴스)
5. 검증 후 destroy(staging RDS 포함 전체 — 윈도우 종료 시 과금 0)

윈도우가 과도히 길어지거나 라이브 3건에서 문제 발생 시 → #156 구현은 별도 윈도우로 폴백(PR은 미리 준비).

## 5. 비용

staging db.t3.small ≈ 윈도우 가동 중에만 ~$0.03–0.05/hr 추가. 윈도우 종료 시 destroy로 0. 상시 과금 아님(on-demand 모델 유지).

## 6. 범위 밖 (YAGNI)

- prod 전용 RDS — 별건(prod는 별도 윈도우/계정 전략).
- staging 전용 Redis/MSK 분리 — 이번 범위는 DB만(#156).
- RDS 멀티-AZ·읽기복제 — staging에 불필요.
- 서비스별 DB 자동 생성 terraform(provisioner) — 현 수동 psql 패턴 유지(dev 정합), 자동화는 별건.
