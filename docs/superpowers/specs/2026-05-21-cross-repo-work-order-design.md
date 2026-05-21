# Cross-Repo Work Order: synapse-gitops + synapse-shared (W2→W3 전환)

> **작성일**: 2026-05-21
> **목적**: 두 레포의 의존관계를 반영한 통합 작업 순서 설계
> **전제**: AWS 인프라 destroy 상태 → terraform apply부터 시작

---

## 1. 배경

### 현재 상태

**synapse-gitops**:
- W2 7차 세션까지 완료
- 6개 서비스 ECR push 완료, 5개 앱 ArgoCD Synced
- knowledge-svc만 Healthy, 나머지 4개 CrashLoopBackOff
- terraform state drift (OIDC, SG 수동 수정분)
- staging overlay 미생성

**synapse-shared**:
- W1 3/3 + W2 5/5 Steps 완료
- W3 사전 준비 산출물 10개 완성 (가이드, 테스트 데이터, 스크립트)
- 팀원 Kafka Producer/Consumer 구현 미완성
- 브랜치 2개 미정리 (chore/w2w3-ops-prep, feat/w2-kafka-schemas)

### 레포 간 의존관계

```
gitops 서비스 안정화 (5/5 Healthy)
       │
       ├─→ shared E2E 검증 가능 (서비스가 살아야 이벤트 테스트 가능)
       │
       ▼
gitops staging overlay 생성
       │
       ├─→ shared ArgoCD staging 배포 가이드 정합
       │
       ▼
shared 핸드오프 + 가이드 업데이트 (현재 상태 반영)
```

---

## 2. 작업 Phase 설계

### Phase 0: 인프라 기동

| # | 작업 | 레포 | 비고 |
|---|------|------|------|
| 0-1 | `terraform apply` | gitops (infra/aws/dev) | EKS, RDS, MSK, Redis, OpenSearch |
| 0-2 | Bastion SSM 접속 확인 | — | Instance ID 변경 가능 |
| 0-3 | ArgoCD 상태 확인 | — | `kubectl get applications -n argocd` |

**완료 기준**: Bastion SSM 접속 + ArgoCD UI 접근 가능

**주의사항**:
- terraform apply 후 OIDC provider, SG 등 수동 수정분이 없으므로 state drift 발생 가능
- 이전 세션에서 수동 생성한 리소스가 destroy로 사라졌으므로, apply 후 재설정 필요 여부 확인

### Phase 1: 서비스 안정화

| # | 작업 | 대상 서비스 | 예상 원인 |
|---|------|------------|-----------|
| 1-1 | kubectl logs로 크래시 원인 확인 | 4개 전부 | — |
| 1-2 | platform-svc 수정 | platform-svc | `mfa_credentials` 테이블 미존재 → Flyway migration 또는 ddl-auto 변경 |
| 1-3 | engagement-svc 수정 | engagement-svc | Flyway 완료 후 앱 설정 문제 |
| 1-4 | learning-card 수정 | learning-card | Tomcat 기동 후 앱 설정 문제 |
| 1-5 | learning-ai 수정 | learning-ai | health check 또는 DB 연결 문제 |
| 1-6 | ECR re-push + ArgoCD Sync | 수정된 서비스 | 5/5 Healthy 목표 |

**완료 기준**: ArgoCD 대시보드에서 5개 서비스 모두 Synced / Healthy

**작업 방식**:
- Bastion SSM → kubectl logs 로 실제 에러 확인
- 서비스 레포(synapse-platform-svc 등)에서 코드 수정 필요 시 PR
- ConfigMap/ExternalSecret 수정 필요 시 gitops 레포에서 PR
- 수정 후 docker build → ECR push → ArgoCD Sync

### Phase 2: terraform state 정리

| # | 작업 | 내용 |
|---|------|------|
| 2-1 | OIDC provider | 이전 세션에서 수동 재생성 → terraform 코드에 반영 또는 import |
| 2-2 | SG 규칙 | RDS/Redis/MSK/OpenSearch SG에 수동 추가한 EKS 노드 SG → terraform 코드 반영 |
| 2-3 | terraform plan 검증 | `terraform plan` → no changes (또는 expected changes only) |

**완료 기준**: `terraform plan`이 예상 외 drift 없이 clean

**참고**: destroy 후 re-apply이므로 수동 수정분이 이미 사라짐. 코드에 반영해두면 다음 apply 시 자동 생성됨.

### Phase 3: staging overlay 생성

| # | 작업 | 내용 |
|---|------|------|
| 3-1 | 디렉토리 구조 | 5개 서비스 × `overlays/staging/` 생성 |
| 3-2 | staging ConfigMap | dev 기반으로 staging 값 분리 |
| 3-3 | staging 리소스 설정 | replicas, resource limits 등 staging 스펙 |
| 3-4 | ApplicationSet 수정 | staging 환경 추가 (autoSync: false) |
| 3-5 | ArgoCD staging sync | 수동 Sync → Healthy 확인 |

**완료 기준**: ArgoCD에서 staging 환경 5개 앱이 Synced / Healthy

**설계 원칙**:
- dev overlay를 기반으로 staging 생성 (kustomize patch)
- staging은 autoSync: false (수동 승인 배포)
- ConfigMap 값은 dev와 동일 RDS/MSK/Redis 사용 (dev 클러스터 내 논리 분리)

### Phase 4: shared 레포 정비

| # | 작업 | 내용 |
|---|------|------|
| 4-1 | 브랜치 정리 | `chore/w2w3-ops-prep`, `feat/w2-kafka-schemas` 확인 후 삭제 또는 머지 |
| 4-2 | 핸드오프 문서 현행화 | HANDOFF_2026-05-19.md → 현재 상태 반영 (서비스 안정화 결과, staging 추가) |
| 4-3 | 가이드 문서 업데이트 | ARGOCD_DEPLOY_VERIFICATION.md에 staging 절차 추가 |
| 4-4 | 팀원 체크리스트 갱신 | TEAM_CHECKLIST_W3.md에 현재 인프라 상태, 접속 정보 업데이트 |

**완료 기준**: shared 핸드오프가 gitops 현재 상태와 일치

### Phase 5: 통합 검증 + 계획서

| # | 작업 | 내용 |
|---|------|------|
| 5-1 | 교차 검증 | 두 레포 핸드오프 문서의 서비스 상태, PR 현황, 다음 작업 일치 확인 |
| 5-2 | W3 통합 계획서 | 팀원 Kafka 구현 완료 시 E2E 검증 → staging 프로모션 → Rollback 테스트 순서 |
| 5-3 | 비용 관리 | 작업 완료 후 `terraform destroy` 실행 |

**완료 기준**: 두 레포 핸드오프가 정합하고, W3 작업 계획이 명확

---

## 3. 리스크 및 대응

| 리스크 | 영향 | 대응 |
|--------|------|------|
| terraform apply 후 OIDC/SG 재설정 필요 | Phase 1 지연 | Phase 2를 Phase 1 앞으로 이동 가능 |
| 서비스 크래시 원인이 서비스 레포 코드 문제 | 다른 레포 작업 필요 | 서비스 레포 PR 생성 후 ECR re-push |
| dev 환경에서 staging 논리 분리 한계 | 완전한 staging 검증 불가 | dev 클러스터 내 namespace 분리로 대응 |
| 비용 누적 ($0.41/hr) | 세션 길어지면 비용 증가 | 각 Phase 완료 후 중단점 명시, destroy 잊지 않기 |

---

## 4. 성공 기준

- [ ] 5개 서비스 ArgoCD Synced / Healthy
- [ ] terraform plan clean
- [ ] staging overlay 생성 + ArgoCD staging 앱 등록
- [ ] 두 레포 핸드오프 문서 정합
- [ ] W3 통합 작업 계획서 작성
- [ ] terraform destroy 완료
