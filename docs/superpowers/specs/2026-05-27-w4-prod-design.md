# W4 prod 환경 설계 — prod overlay + 승인 게이트 + 롤백/백업

> **작성일**: 2026-05-27
> **W4 기간**: 2026-06-01 ~ 2026-06-05 (6/3 지방선거 제외, 4 영업일)
> **트랙**: gitops
> **담당**: @VelkaressiaBlutkrone
> **관련 문서**: [PRD_W4](../../project-management/prd/PRD_W4.md) | [WORKFLOW_W4](../../project-management/workflow/WORKFLOW_gitops_W4.md) | [TASK](../../project-management/task/TASK_gitops.md) | [W4 백로그](./2026-05-27-w4-backlog.md)

---

## 1. 목표와 범위

dev/staging과 동일한 GitOps 파이프라인 위에 **prod 거버넌스 레이어**(수동 승인 + 권한 분리 + 롤백/백업)를 얹는다. 물리적 인프라 복제가 아니라 **거버넌스를 증명**하는 것이 W4의 핵심.

**범위**: Step 9(prod 환경 + 승인 게이트, FR-GO-401~404) + Step 10(롤백/백업, FR-GO-405~408). 한 spec으로 설계하되 구현 플랜은 두 단위로 분리 가능(롤백/백업은 staging에서도 검증 → prod와 독립).

**비범위**: 별도 prod 클러스터/인프라, SSO/OIDC, prod 토픽 완전 분리(캡스톤 한계로 문서화).

---

## 2. 핵심 결정 사항

| 영역 | 결정 | 근거/함의 |
|---|---|---|
| **격리** | 논리 분리 — dev 클러스터 내 `synapse-prod` ns | 별도 EKS/RDS/MSK 없음. 비용 추가 ~0. 격리는 ns+RBAC+데이터 논리분리 수준. W4 핵심은 거버넌스 |
| **승인 게이트** | ArgoCD Manual Sync + RBAC | prod Application은 `automated` 없음 → main 머지 후 OutOfSync 대기. 변경 게이트는 기존 main PR 보호 |
| **권한** | ArgoCD 로컬 계정 + RBAC role | `argocd-cm` 로컬 계정 + `rbac-cm`에 `synapse-prod` sync만 허용하는 role. SSO 불필요 |
| **롤백/백업** | GitOps 우선 + Velero ns 최소 | 1차 롤백=ArgoCD History/git revert. Velero는 synapse-prod/staging ns+PV 일일. RTO 30m/RPO 1h. 데이터=RDS 자동백업 |
| **prod 이미지 승격** | 명시적 PR (image-updater 자동 bump 없음) | prod ApplicationSet에 image-updater 어노테이션 미부착. 태그 변경=PR(=D-037 B안 방향) |

---

## 3. prod overlay + 데이터 논리 분리

스캐폴드된 5개 prod overlay의 `REPLACE_ME_*`(별도 prod 인프라 가정)를 **공유 dev 데이터스토어 + 논리 분리 키**로 확정한다.

| 데이터 | 논리 분리 방식 | overlay 값 |
|---|---|---|
| PostgreSQL | 공유 dev RDS + **별도 DB명** `synapse_prod` | host=dev RDS 엔드포인트, `DATABASE_NAME=synapse_prod`, `DB_URL=jdbc:postgresql://<dev-rds>:5432/synapse_prod` |
| Redis | 공유 dev ElastiCache + **별도 논리 DB 인덱스** | `SPRING_DATA_REDIS_HOST`=dev redis, `SPRING_DATA_REDIS_PORT=6379`, `SPRING_DATA_REDIS_DATABASE=1`(dev=0) |
| Kafka | 공유 dev MSK | `KAFKA_BROKERS`=dev 브로커. **토픽 공유는 캡스톤 한계로 문서화**(완전 분리=prod 토픽 prefix, 앱설정 → W5/이월) |
| 시크릿 | **별도 AWS SM 경로** `synapse/prod/{app}/*` | ExternalSecret remoteRef 경로를 prod로 패치(Stripe prod price 등 앱 시크릿 포함) |

**작업 — overlay 비대칭 주의**: 5개 prod overlay는 현재 상태가 다르다.
- `platform-svc/overlays/prod`: 풀 ConfigMap 패치 스캐폴드됨(`REPLACE_ME_*` 호스트·Stripe price 포함). → **치환** + 논리분리 키 반영.
- 나머지 4개(`engagement`·`knowledge`·`learning-card`·`learning-ai`): `replicas=3` + image tag **뿐**. ConfigMap·ExternalSecret 패치 부재. → 각 서비스 **staging overlay를 미러링해 ConfigMap/ExternalSecret 패치 블록을 신규 작성**.

공통 반영분: `SPRING_PROFILES_ACTIVE=prod`, 논리분리 키(`DATABASE_NAME=synapse_prod`·`DB_URL .../synapse_prod`·`SPRING_DATA_REDIS_DATABASE=1`), ExternalSecret remoteRef `synapse/prod/{app}/*`. **현재 platform-svc prod도 `DATABASE_NAME=synapse`(dev와 동일)·Redis index 키 없음** → 논리분리 미반영 상태이므로 반드시 수정.

> ⚠️ **앱별 환경변수 키 불일치(라이브 함정)**: 서비스마다 실제로 읽는 키가 다르다. staging `engagement-svc`는 `REDIS_HOST`/`SPRING_DATASOURCE_URL`을 쓰고, scaffolded `platform-svc` prod는 `SPRING_DATA_REDIS_*`/`DB_URL`을 쓴다(REDIS_HOST 버그 회피 의도). prod overlay 작성 시 **각 앱이 실제 읽는 키를 base/staging에서 확인 후** 작성한다(staging 키를 맹목 복사 금지). cf. local-k8s SPRING_DATASOURCE_* 이슈.

**전제(라이브)**: AWS SM에 `synapse/prod/{app}/*` 시크릿 생성 + 공유 RDS에 `synapse_prod` DB 생성.

---

## 4. AppProject + ApplicationSet(manual) + RBAC

### 4.1 `synapse-prod` AppProject (신규)
```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata: { name: synapse-prod, namespace: argocd }
spec:
  description: Synapse prod (manual sync, restricted)
  sourceRepos: ["https://github.com/team-project-final/synapse-gitops.git"]
  destinations: [{ namespace: synapse-prod, server: https://kubernetes.default.svc }]
  clusterResourceWhitelist: [{ group: "", kind: Namespace }]
  namespaceResourceWhitelist: [{ group: "*", kind: "*" }]
```

### 4.2 `applicationset-prod.yaml` (신규)
staging 패턴(list generator 5개) 미러링하되:
- `name: synapse-{{service}}-prod`, `project: synapse-prod`, `path: apps/{{service}}/overlays/prod`, `namespace: synapse-prod`
- **`syncPolicy.automated` 제거**(수동) — `syncOptions: [CreateNamespace=true]`만 유지 → main 머지 후 OutOfSync 대기
- **image-updater 어노테이션 없음** — prod 이미지 승격은 명시적 PR

### 4.3 RBAC 권한 분리 (`rbac-cm.yaml` 확장 + `argocd-cm` 로컬 계정)
```
# rbac-cm policy.csv 에 추가
p, role:prod-deployer, applications, sync, synapse-prod/*, allow
p, role:prod-deployer, applications, get,  */*, allow
p, role:prod-deployer, projects, get, *, allow
g, gitops-admin, role:prod-deployer
# argocd-cm: accounts.gitops-admin: apiKey, login
```
- `policy.default: role:readonly` 유지 → 일반 계정 prod sync **거부**(FR-GO-403 검수)
- `gitops-admin` → prod-deployer → `synapse-prod/*` sync **허용** (RBAC 리소스 포맷 `<project>/<app>` → glob이 `synapse-prod` 프로젝트 기준으로 동작, §4.1 별도 프로젝트가 전제)
- 기존 `role:admin` full 유지(운영자)
- **`argocd-cm` 신규**: 현재 `argocd/bootstrap/`에는 `rbac-cm`/`notifications-cm`만 있고 `argocd-cm`이 없다. 로컬 계정 `accounts.gitops-admin: apiKey, login`을 정의할 `bootstrap/argocd-cm.yaml`을 신규 생성하고 기존 bootstrap CM과 동일 경로로 적용한다(적용 방식 확인 필요).

---

## 5. 롤백 + 백업 (Step 10)

### 5.1 롤백 (FR-GO-405/406)
| 메커니즘 | 절차 | 검증(staging) |
|---|---|---|
| ArgoCD History (405) | `argocd app rollback <app> <id>` — 이전 synced revision (prod는 gitops-admin 수동) | 1-step rollback 성공 |
| git revert (406) | 문제 커밋 revert PR → main 머지 → sync(staging auto / prod manual) | revert PR → sync → 복원 |
| 이미지 롤백 | overlay `newTag` revert PR (승격이 PR이므로 동일 경로) | — |
| DB 스키마 | **forward-only**(Flyway) — 위 메커니즘으로 스키마 롤백 안 함, 문서화 | — |

### 5.2 백업 (FR-GO-407/408) — Velero, ns 최소
- **설치**: Velero + S3 `BackupStorageLocation`(전용 버킷) + **IRSA**(S3 접근). 버킷·IRSA=terraform(비용 0 준비), 설치=라이브
- **일일 스케줄**(407): `Schedule` CR — `synapse-prod`+`synapse-staging` ns + PV, cron 매일. 24h 내 1회 + S3 저장 확인
- **복구 시뮬레이션**(408): staging ns 삭제 → `velero restore` → 복구 성공
- **etcd**: 관리형 EKS=AWS 책임, 직접 snapshot 불가 → 문서 명시
- **백업 실패 알람**: Velero 실패 메트릭 → PrometheusRule → Alertmanager Slack (W3 observability 재사용)
- **목표**: RTO 30분 / RPO 1시간 (team-lead 합의)

---

## 6. 완료 정의 (PRD W4 매핑)

| 요구사항 | 우선순위 | Done 검증 | 비용 |
|---|---|---|---|
| FR-GO-401 prod overlay ×5 | P0 | platform-svc 치환 + 4개 신규 작성(앱별 키 확인), 논리분리 키 반영, 5개 `kustomize build` 통과 | 0 |
| FR-GO-402 Manual Sync 정책 | P0 | prod ApplicationSet automated 없음, OutOfSync 대기 | 0 |
| FR-GO-403 권한 분리 | P0 | readonly 계정 prod sync 거부 / gitops-admin 허용 | 라이브 |
| FR-GO-404 첫 prod 배포 + 검증 | P0 | gitops-admin sync → synapse-prod 5/5, 도메인 200(없으면 port-forward) | 라이브 |
| FR-GO-405 ArgoCD History 롤백 | P0 | staging 1-step rollback 성공 | 라이브 |
| FR-GO-406 git revert 롤백 | P0 | revert PR → sync → 복원 | 라이브 |
| FR-GO-407 Velero 일일 백업 | P1 | 24h 내 1회 + S3 저장 | 라이브 |
| FR-GO-408 백업 복구 시뮬 | P1 | staging ns 삭제 → 복구 | 라이브 |

**비용 batching**: overlay 치환·AppProject·ApplicationSet·RBAC·Velero 버킷/IRSA terraform = **비용 0 준비**. prod 시크릿/DB 생성·sync·롤백 드릴·Velero 설치/스케줄/복구 = prod 라이브 사이클 1회(과금, 종료 시 destroy).

---

## 7. 전제 · OPEN

- **prod 도메인** — 실 Route53 zone 없으면 FR-GO-404는 port-forward로 대체 검증(도메인은 W4 백로그 A4와 동일 의존)
- **prod 시크릿** — `synapse/prod/{app}/*` AWS SM 생성 필요(라이브 전). ESO 정책 `synapse/*`가 이미 커버(W3 A2)
- **`synapse_prod` DB** — 공유 RDS에 생성 필요(라이브)
- **Velero 버킷** — 신규 S3 버킷 + IRSA terraform
- **`argocd-cm` 적용 경로** — bootstrap CM(`rbac-cm`/`notifications-cm`)이 어떻게 apply되는지 확인 후 신규 `argocd-cm.yaml` 동일 경로 편입
- **team-lead 합의** — RTO/RPO 목표, 권한 모델 사인오프
