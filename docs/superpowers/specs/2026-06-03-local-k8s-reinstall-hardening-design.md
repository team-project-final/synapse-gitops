# local-k8s 재설치 · 진단 · 하드닝 설계

> 작성일: 2026-06-03 KST
> 대상 레포: `synapse-gitops` (`local-k8s/` overlay + `apps/<svc>/base` + overlays)
> 선행 문서: [2026-05-26-local-k8s-minikube-design.md](2026-05-26-local-k8s-minikube-design.md), [2026-06-01-local-k8s-cleanup-design.md](2026-06-01-local-k8s-cleanup-design.md)
> 접근법: 🅱 체계적 하드닝 패스 (EKS 회귀 가드 흡수)

---

## 1. 목표 · 범위 · 성공 기준

### 1.1 목표
`synapse-gitops`의 로컬 k8s 스택(minikube)을 **깨끗이 재설치**하면서 전 구성을 진단하고, 검증된 개선(무중단 배포 포함)을 **base 공통 + local overlay**에 반영해 레포를 실질적으로 개선한다.

### 1.2 성공 기준 (측정 가능)
1. `kubectl delete ns synapse-local && bash scripts/minikube-up.sh` 단독으로 **인프라 + 앱 전 워크로드가 1/1 Ready** (learning-ai는 OpenAI 키 주입 시).
2. **Kafka Avro 왕복**: schema-registry 기동 + 한 이벤트(예: `platform.auth.user-registered-v1`) 발행·소비가 직렬화 에러 없이 성공.
3. **무중단 스모크**: `kubectl rollout restart` 도중 gateway 경유 연속 curl에서 **5xx / 연결끊김 0건**.
4. **EKS 회귀 없음**: `kustomize build overlays/{dev,staging,prod}`가 변경 전/후로 의도한 diff만 — 비의도 변경 0건.
5. 모든 매니페스트 변경이 진단 리포트 항목과 1:1로 추적된다.

### 1.3 범위
- **포함**: `local-k8s/` 18개 매니페스트, `apps/<svc>/base` 5종 + gateway deployment, 무중단 신규 리소스(PDB 등), schema-registry infra, 진단 리포트, 재검증.
- **포함(플래그만)**: 앱 측 graceful shutdown(`server.shutdown: graceful`)은 서비스 5개 레포 변경이라 **별도 후속 작업으로 분리**. 이번엔 k8s `preStop`으로 부분 보완하고 리포트에 명시.
- **제외**: EKS 실배포, Terraform, ArgoCD ApplicationSet 변경(렌더 검증만).

### 1.4 현재 상태 요약 (탐색 결과)
- 이전 7건 갭 수정(PR #94/#95/#96)은 **모두 main 병합 완료** — 매니페스트에 반영됨.
- 인프라 6종(postgres[pgvector]/redis/zookeeper/kafka/opensearch + kafka-brokers configmap + postgres-initdb + kafka-topics-job), 앱 6개.
- base deployment에 리소스 requests/limits·프로브는 **이미 존재**. 단 `strategy`/`lifecycle`/PDB는 없음.
- 환경: minikube v1.38.1, kubectl v1.36.1, docker 29.5.2 — 가용. 클러스터는 현재 Stopped.

### 1.5 감사 7차원 체크리스트 (사용자 지정)
- **서비스**: 셀렉터/포트 정합, gateway 라우트 대상 일치
- **파드**: 프로브(인프라 포함)·리소스·재시작 레이스·startup 순서
- **게이트웨이**: 라우트 테이블 ↔ 서비스명 일치, Redis 의존, 진입점 health
- **시크릿**: 더미값 정합, learning-ai 키 주입 마찰, optional secretRef
- **디플로이먼트**: replicas/strategy/lifecycle, 이미지/tag/pullPolicy, env 주입(서비스링크 충돌)
- **설정**: DB 격리·Flyway/DDL 일관성, schema-registry 배선, prefix 정합
- **무중단 배포**: RollingUpdate 전략·preStop·gracePeriod·minReadySeconds·PDB·anti-affinity

---

## 2. 작업 구조 (5 페이즈)

| 페이즈 | 내용 | 산출물 |
|---|---|---|
| **P0 진단·베이스라인** | minikube start → 클린 재설치 → `get pods/events`, `describe`, 로그, `kustomize build` 전 overlay 캡처 | 현 상태 스냅샷 |
| **P1 감사** | 지정 7차원 전수 점검 | 우선순위 매겨진 진단 리포트 |
| **P2 개선 적용** | base+local에 큐레이션된 변경 적용(§3 카탈로그) | 매니페스트 diff |
| **P3 재검증** | 재설치 + Avro 왕복 + 무중단 스모크 + EKS 렌더 diff | 검증 증거 |
| **P4 문서·정리** | README/주석/메모리 갱신, 의미 단위 커밋 | 최종 PR |

---

## 3. 개선 카탈로그

표기: 신뢰도 ✅확정 갭 / 🔍감사 후 조건부 · 영향 범위 🟢local-only / 🔴base→EKS

### A. 무중단 배포 🔴 base→EKS
| # | 항목 | 현재 | 변경 | 신뢰도 |
|---|---|---|---|---|
| A1 | RollingUpdate 전략 | `strategy` 미지정(기본값) | base 6개 deploy에 `strategy: RollingUpdate {maxUnavailable: 0, maxSurge: 1}` | ✅ |
| A2 | preStop + grace | 없음 | `lifecycle.preStop: exec [sleep, "5"]` + `terminationGracePeriodSeconds: 40` | ✅ |
| A3 | minReadySeconds | 없음 | `minReadySeconds: 5` | ✅ |
| A4 | PodDisruptionBudget | 없음 | **prod overlay에만** svc별 PDB `minAvailable: 1` (replicas=1인 base/dev/local엔 미적용 → node drain 데드락 회피) | ✅ |
| A5 | pod anti-affinity | 없음 | **prod overlay**에 `podAntiAffinity`(preferredDuringScheduling) | ✅ |
| A6 | 앱 graceful shutdown | `server.shutdown` 미설정 | **이번 범위 제외**(서비스 레포) — 후속 권고로 리포트 기록, preStop이 부분 보완 | 🔍 |

> 로컬 검증 한계: replica=1이라 무중단 효과는 약함 → **prod overlay 렌더로 전략/PDB 확인 + 로컬 `rollout restart` 무손실 스모크**로 보완.

### B. 인프라 견고성 🟢 local-only
| # | 항목 | 현재 | 변경 | 신뢰도 |
|---|---|---|---|---|
| B1 | infra 프로브 | postgres/redis/kafka/opensearch/zookeeper 프로브 없음 | readiness/liveness 추가(postgres `pg_isready`, redis `redis-cli ping`, kafka tcpSocket:9092, opensearch httpGet:9200, zookeeper tcpSocket:2181) | ✅ |
| B2 | infra 리소스 | requests/limits 없음 | 각 infra에 적정 requests/limits(opensearch -Xmx256m → limit 512Mi 등) | ✅ |
| B3 | **schema-registry** | **부재**(전 Java svc·learning-ai가 참조) | `infra/schema-registry.yaml` 추가(cp-schema-registry:7.7.0, KAFKASTORE_BOOTSTRAP=kafka:9092, port 8081) + infra kustomization 등록 | ✅ |

### C. 설정/배선 위생 🟢 local-only
| # | 항목 | 현재 | 변경 | 신뢰도 |
|---|---|---|---|---|
| C1 | Java svc schema-registry 배선 | overlay에 `SCHEMA_REGISTRY_URL` 미설정 → `localhost:8086` 폴백 → **Avro 실패** | platform/engagement/knowledge/learning-card configmap에 `SCHEMA_REGISTRY_URL: http://schema-registry:8081` 추가 | ✅ |
| C2 | learning-ai schema-registry | 이미 `schema-registry:8081` 참조(실체 없음) | B3로 실체 생성 → 정합 | ✅ |
| C3 | learning-ai 키 주입 마찰 | 매 재설치마다 수동 주입 | `minikube-up.sh`에 키(env/파일) 존재 시 **자동 주입 옵션 단계** 추가(없으면 기존처럼 스킵·경고). 키 미커밋 유지 | ✅ |
| C4 | DDL/Flyway 일관성 | platform local overlay만 `DDL_AUTO=update`, 나머지 Flyway | 감사 후 일관 정책(로컬 Flyway 우선, DDL=validate/none) 적용 | 🔍 |

### D. 서비스/시크릿/게이트웨이 점검 🟢 local-only (감사 → 조건부)
| # | 항목 | 상태 | 조치 |
|---|---|---|---|
| D1 | gateway 라우트 ↔ 서비스명 | `platform-svc:80`/`engagement-svc:80`/`knowledge-svc:80`/`learning-card:80` 정합 확인됨 | 변경 없음(리포트 기록) |
| D2 | service 포트/셀렉터 | learning-ai 80→8090 등 정합 | 변경 없음 |
| D3 | 시크릿 더미값/unused | redis_local 등 일치 | unused 키(learning-card `API_KEY` 등) 정리 검토 🔍 |
| D4 | imagePullPolicy | `:local` 태그라 기본 IfNotPresent | 명시적 `imagePullPolicy: IfNotPresent`를 로컬 overlay에 고정 검토(재적재 후 stale 방지) 🔍 |

**확정 갭(✅) 핵심 4가지**: schema-registry 부재(B3+C1), 무중단 전략·preStop 부재(A1~A3), infra 프로브 부재(B1), 키 주입 마찰(C3).

---

## 4. 검증 · EKS 회귀 가드 · 리스크

### 4.1 검증 전략 (P3)
| 검증 | 방법 | 통과 기준 |
|---|---|---|
| 전 워크로드 Ready | `delete ns` → `minikube-up.sh` → `get pods` | 인프라+앱 전부 1/1 (learning-ai는 키 주입 시) |
| Avro 왕복 | schema-registry 기동 후 한 이벤트 발행→소비 로그 추적 | 직렬화 에러 0, consumer 정상 수신 |
| 무중단 스모크 | `while curl gateway/.../health` 루프 중 `rollout restart deploy/platform-svc` | 5xx·연결끊김 0건 |
| infra 프로브 | 재설치 시 앱이 인프라 Ready 전 기동 시도 → CrashLoop 횟수 | 이전 대비 재시작 감소(0 지향) |
| EKS 회귀 가드 | 변경 전/후 `kustomize build overlays/{dev,staging,prod}` diff | 의도한 diff만, 비의도 0 |

### 4.2 EKS 회귀 가드
base 변경(A1~A3)은 dev/staging/prod에 전파되므로:
- 변경 **전** 3개 overlay 렌더 캡처(베이스라인).
- 변경 **후** 재렌더 → diff가 무중단 필드(strategy/preStop/minReadySeconds)만 추가됐는지 확인.
- PDB/anti-affinity(A4/A5)는 **prod overlay에만** → dev/staging 렌더는 무중단 base 필드 외 무변경이어야 함.

### 4.3 리스크 & 롤백
| 리스크 | 완화 |
|---|---|
| base 변경이 EKS 동작에 영향 | 렌더 diff 가드(4.2), 실배포 안 함. ArgoCD sync 전까지 무영향 |
| schema-registry가 8GB 노드 압박 | 리소스 limit(B2) + `kubectl top` 모니터 |
| PDB `minAvailable:1`이 prod에서 과도 | replicas=3 기준 1 보장은 안전(2개까지 동시 축출 허용) |
| preStop sleep이 롤아웃 지연 | 5초로 짧게, gracePeriod 40s 내 |
| 변경이 커서 리뷰 부담 | 의미 단위 커밋 분리(§4.4) |

**롤백**: 모두 매니페스트 변경 → `git revert` + `delete ns && apply -k`로 즉시 원복. 로컬은 PVC 없어 상태 잔존 없음.

### 4.4 커밋/PR 구조 (의미 단위)
1. `feat(local-k8s): schema-registry 추가 + 전 Java svc 배선` (B3+C1+C2)
2. `feat(infra): base 무중단 배포 전략 + preStop/minReadySeconds` (A1~A3)
3. `feat(prod): PDB + pod anti-affinity` (A4+A5)
4. `feat(local-k8s): infra 프로브 + 리소스 + 키 자동주입` (B1+B2+C3)
5. `fix(local-k8s): 설정 일관성(DDL/Flyway) + 위생` (C4+D3+D4, 감사 결과 반영)
6. `docs: 진단 리포트 + README/메모리 갱신`

---

## 5. 미해결 결정 / 후속
- **A6 graceful shutdown**: 서비스 5개 레포에 `server.shutdown: graceful` + `spring.lifecycle.timeout-per-shutdown-phase` 추가 — 별도 후속 작업(cross-repo).
- **C4/D3/D4**: P1 감사 결과에 따라 조건부 확정.
- learning-ai 실제 OpenAI 키는 git 미커밋 유지 — 클러스터 직접 주입(C3가 자동화).
