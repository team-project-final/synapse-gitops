# 통합 핸드오프 허브-스포크 설계

> **작성일**: 2026-05-22
> **목적**: gitops + shared + 서비스 레포 간 핸드오프 정합성 확보 및 프로세스 체계화
> **접근법**: Hub & Spoke — shared에 허브, 각 레포에 스포크
> **적용 시점**: W3 전환 (2026-05-26)

---

## 1. 문제 정의

### 1.1 정합성

gitops HANDOFF_W2.md는 9차 세션(5/21)까지 반영되어 5/5 Healthy를 기록하지만, shared HANDOFF_2026-05-19.md는 8차 세션에 멈춰 platform-svc와 learning-ai를 CrashLoopBackOff로 기록. MSK 토픽 생성 완료, staging 4/5 Healthy 등의 결과도 shared에 미반영.

### 1.2 분산

핸드오프 정보가 3곳 이상에 흩어져 있어 전체 그림을 보려면 gitops HANDOFF_W2.md, shared HANDOFF_2026-05-19.md, cross-repo-work-order-design.md, 각 서비스 레포 커밋 히스토리를 모두 확인해야 함.

### 1.3 구조 부재

세션 종료 시 무엇을 갱신하고, 어디에 쓰고, 누가 검증하는지 정해진 프로세스가 없음. 결과적으로 한쪽 레포만 갱신하고 다른 쪽은 방치되는 패턴이 반복됨.

### 1.4 W3 전환 공백

W2 완료 상태가 레포 간 정리되지 않아 W3 시작 기준(staging 5/5, Kafka 구현 상태, Observability 미시작)이 불명확.

---

## 2. 설계: 허브-스포크 구조

### 2.1 구조 개요

```
synapse-shared (허브)
  └── docs/project-management/HANDOFF_HUB.md    ← 전체 상태 대시보드
  └── docs/project-management/HANDOFF_SHARED.md ← shared 스포크
  └── docs/project-management/SESSION_CLOSE_CHECKLIST.md ← 세션 종료 프로세스

synapse-gitops (스포크)
  └── docs/superpowers/HANDOFF_W3.md            ← 인프라/배포 상세

서비스 레포 (platform-svc, engagement-svc, ...)
  └── 별도 핸드오프 없음 — 허브 대시보드에서 추적
```

### 2.2 설계 원칙

- **허브 200줄 이내**: 상태값과 링크만, 상세는 스포크에 위임
- **복사 금지**: 스포크 내용을 허브에 복사하지 않음, 참조 링크로 대체
- **상태값 enum**: `✅ Healthy` / `⚠️ Degraded` / `🔴 Down` / `⏳ Not Started`
- **갱신 주체 명시**: 매 갱신 시 날짜 + 세션 번호 + 갱신자

---

## 3. 허브 문서 구조 (HANDOFF_HUB.md)

위치: `synapse-shared/docs/project-management/HANDOFF_HUB.md`

### 섹션 구성

```markdown
# Synapse 통합 핸드오프 허브

> 최종 갱신: YYYY-MM-DD (N차 세션)
> 현재 주차: WN
> 갱신자: @담당자

## 1. 프로젝트 상태 대시보드

### 환경별 서비스 상태
| 서비스 | dev | staging | prod |
|---|---|---|---|
| (5행) | enum | enum | enum |

### 인프라 상태
| 컴포넌트 | 상태 | 비고 |
|---|---|---|
| (EKS/RDS/MSK/Redis/OpenSearch/ArgoCD) | enum | 한줄 |

### Kafka/스키마 상태
| 항목 | 상태 |
|---|---|
| (스키마/토픽/서비스 구현) | enum |

## 2. 교차 의존관계 맵
블로커/선행 조건을 화살표 형태로 기록.
"[블로커] A → B 가능" 형식.

## 3. 스포크 참조
| 레포 | 스포크 문서 | 최종 갱신 | 정합성 |
|---|---|---|---|
| (2행: gitops, shared) | 경로 | 날짜 | ✅/⚠️ |

## 4. 다음 세션 작업 순서
번호 매긴 작업 리스트. 각 항목에 [레포] 태그 + 완료 기준.

## 5. 주간 마일스톤 추적
| 주차 | 목표 | 상태 | 실제 완료일 |
|---|---|---|---|
| (W1~W5) | 한줄 | enum | 날짜 |
```

---

## 4. 스포크 문서 구조

### 4.1 gitops 스포크 (HANDOFF_W3.md)

위치: `synapse-gitops/docs/superpowers/HANDOFF_W3.md`

```markdown
# W3 핸드오프: synapse-gitops

> 최종 갱신: YYYY-MM-DD (N차 세션)
> 허브 참조: synapse-shared/docs/project-management/HANDOFF_HUB.md

## 1. 세션별 완료 사항
세션 N: 작업 | 산출물 테이블. W2 이전은 "HANDOFF_W2.md 참조" 한 줄로 축약.

## 2. 인프라 상세 상태
terraform 리소스, ArgoCD Application 상태, ExternalSecret 동기화, SG/OIDC 수정 이력.

## 3. 세션 기동 절차
runbook 링크만: → docs/runbooks/w2-session-bootstrap-runbook.md

## 4. 발견 사항 (D-0XX)
gitops 특화 발견만 기록. 서비스 레벨 이슈는 허브 교차 의존관계로 이동.

## 5. 비용 관리
시간당 비용 + destroy 명령어.
```

### 4.2 shared 스포크 (HANDOFF_SHARED.md)

위치: `synapse-shared/docs/project-management/HANDOFF_SHARED.md`

```markdown
# 핸드오프: synapse-shared

> 최종 갱신: YYYY-MM-DD (N차 세션)
> 허브 참조: → HANDOFF_HUB.md

## 1. Avro 스키마 현황
스키마 8개 목록 + 호환성 상태.

## 2. Kafka 토픽 / MSK 상태
토픽 5개 × 생성 여부 + 브로커 주소.

## 3. Docker Compose 현황
13개 서비스 상태.

## 4. CI/CD 파이프라인 상태
ci-java, schema-check, mirror 상태.

## 5. 팀원 체크리스트 링크
→ TEAM_CHECKLIST_W3.md 참조.
```

### 4.3 서비스 레포

별도 핸드오프 문서를 두지 않음. 서비스 상태는 허브 대시보드에서 추적하고, 서비스별 이슈는 shared의 `docs/fix-requests/` 또는 GitHub Issues로 관리.

---

## 5. 세션 종료 체크리스트

위치: `synapse-shared/docs/project-management/SESSION_CLOSE_CHECKLIST.md`

### 5단계 프로세스

```
Step 1: 스포크 갱신 (작업한 레포만)
  └── 해당 레포 HANDOFF 문서에 세션 결과 기록

Step 2: 허브 동기화
  ├── 대시보드 테이블 상태값 갱신
  ├── 교차 의존관계 변경 반영
  ├── 스포크 참조의 "최종 갱신일" 업데이트
  └── 다음 세션 작업 순서 갱신

Step 3: 정합성 점검 (30초, 3개 질문)
  □ 허브 서비스 상태가 실제(ArgoCD/kubectl)와 같은가?
  □ 허브의 "스포크 최종 갱신일"이 오늘 날짜인가? (작업한 레포에 한해)
  □ 허브의 "다음 세션 작업"에 오늘 완료한 항목이 남아있지 않은가?

Step 4: 커밋 + 푸시
  ├── 스포크: 해당 레포에 커밋
  └── 허브: shared 레포에 커밋
      └── 커밋 메시지: "docs: session N handoff — [한줄 요약]"

Step 5: 비용 정리
  └── terraform destroy (해당 시)
```

### 세션 유형별 범위

| 세션 유형 | 스포크 갱신 | 허브 갱신 | 정합성 점검 |
|---|---|---|---|
| gitops만 작업 | gitops만 | 대시보드 + 다음 작업 | 서비스 상태만 |
| shared만 작업 | shared만 | 스키마/토픽 + 다음 작업 | 의존관계만 |
| 교차 작업 | 양쪽 모두 | 전체 | 전체 |
| 서비스 레포만 | 없음 | 대시보드 서비스 상태만 | 서비스 상태만 |

---

## 6. 기존 문서 전환 계획

| 기존 문서 | 처리 |
|---|---|
| `gitops/docs/superpowers/HANDOFF_W2.md` | 아카이브 유지 (읽기 전용), W3부터 HANDOFF_W3.md 새 형식 |
| `shared/docs/project-management/HANDOFF_2026-05-19.md` | 아카이브 유지, HANDOFF_SHARED.md로 전환 |
| `gitops/docs/superpowers/specs/2026-05-21-cross-repo-work-order-design.md` | 아카이브 — 허브 교차 의존관계가 대체 |
| `gitops/docs/superpowers/specs/2026-05-18-shared-gitops-unified-plan-design.md` | 아카이브 — 역할 완료 |

---

## 7. W3 전환 초기값

### 환경별 서비스 상태

| 서비스 | dev | staging | prod |
|---|---|---|---|
| platform-svc | ✅ Healthy | ⚠️ staging 프로필 미존재 | ⏳ W4 |
| engagement-svc | ✅ Healthy | ✅ Healthy | ⏳ W4 |
| knowledge-svc | ✅ Healthy | ✅ Healthy | ⏳ W4 |
| learning-card | ✅ Healthy | ✅ Healthy | ⏳ W4 |
| learning-ai | ✅ Healthy | ✅ Healthy | ⏳ W4 |

### 교차 의존관계

```
[블로커] platform-svc application-staging.yml 추가
    └─→ staging 5/5 Healthy 달성

[블로커] 5개 서비스 Kafka Producer/Consumer 구현 (서비스 레포)
    └─→ shared E2E 검증 가능
        └─→ staging 프로모션 테스트

[독립] Observability 스택 설치 (gitops)
    └─→ W3 PRD FR-GO-303~307

[독립] terraform state 정리 — SG/OIDC 코드 반영 (gitops)
```

### W3 첫 세션 작업 순서

```
1. [gitops] terraform apply + 세션 기동 (runbook 12단계)
2. [gitops] platform-svc staging 프로필 해결 → staging 5/5
3. [gitops] Observability 스택 설치 (kube-prometheus-stack)
4. [gitops] ServiceMonitor 5개 + Grafana 대시보드
5. [shared] 서비스별 Kafka 구현 상태 확인 + E2E 준비
6. [gitops] terraform state 정리 (SG/OIDC 코드 반영)
```

---

## 8. 성공 기준

- [ ] HANDOFF_HUB.md가 synapse-shared에 존재하고 200줄 이내
- [ ] HANDOFF_W3.md가 synapse-gitops에 존재
- [ ] HANDOFF_SHARED.md가 synapse-shared에 존재
- [ ] SESSION_CLOSE_CHECKLIST.md가 synapse-shared에 존재
- [ ] 허브 대시보드와 실제 서비스 상태가 일치
- [ ] 기존 문서 4개가 아카이브 처리 (내용 변경 없이 읽기 전용 표시)
- [ ] W3 첫 세션 종료 시 체크리스트가 1회 이상 실행됨
