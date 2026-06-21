# Project Management — synapse-gitops

이 폴더는 `workflow-dashboard`로 자동 sync되는 일정/진척 문서를 보관합니다.

> **Phase D Sync**: 중앙 기준은 [2026-06-21 GitOps 및 릴리즈 하드닝 실행 리포트](../../../documents/docs/project-management/reports/phase-d-gitops-release-hardening-2026-06-21.md)다. PR #211은 머지됐고 로컬 Phase D 계약 검증은 통과했지만, live AWS/EKS/ArgoCD 증거와 dashboard track drift 해소 전까지 추가 완료 처리는 보류한다.
> **Phase E Sync**: 중앙 기준은 [2026-06-21 통합 QA 및 문서 마감 실행 리포트](../../../documents/docs/project-management/reports/phase-e-qa-docs-closeout-2026-06-21.md)다. gitops는 dashboard 204/211 상태이므로 cost/stability, metrics gap, 24h signoff, destroy decision 증거가 붙은 항목만 완료 처리한다.
> **Phase F Sync**: 중앙 기준은 [2026-06-21 PM Dashboard / 문서 동기화 실행 리포트](../../../documents/docs/project-management/reports/phase-f-pm-dashboard-doc-sync-2026-06-21.md)다. gitops dry-run은 205/211, 현재 dashboard JSON은 204/211이라 live sync 전 1개 추가 완료 check의 증거 확인이 필요하다.

## 구조

```
project-management/
├── KICKOFF.md                  # gitops 트랙 시작 문서
├── README.md                   # 이 파일
├── prd/
│   ├── PRD_W1.md ~ PRD_W5.md   # 주차별 요구사항 (FR-GO-*)
├── task/
│   └── TASK_gitops.md          # gitops 트랙 전체 Step 정의
├── workflow/
│   └── WORKFLOW_gitops_W1.md ~ W5.md   # 주차별 세부 체크리스트
├── scope/
│   └── SCOPE_gitops.md         # gitops 트랙 In/Out of Scope
└── history/
    └── HISTORY_gitops.md       # 진행 이력 (자동 갱신 + 수동 메모)
```

## 동작 방식

1. `docs/project-management/{workflow,task,prd}/**` 경로의 마크다운을 수정해 푸시
2. `.github/workflows/parse-workflow.yml`이 `WORKFLOW_*` 체크박스 + `PRD_W*` 테이블을 파싱
3. 결과 JSON이 `workflow-dashboard` 레포의 `data/synapse-gitops.json`으로 자동 커밋
4. GitHub Pages에 배포되어 대시보드에서 진척률로 표시됨

## 문법 규칙

WORKFLOW 파서가 인식하는 패턴 (정확히 지켜야 카운트됨):

- Step 헤더: `## Step <숫자>: <이름>`
- Phase 헤더: `### <숫자>.<숫자> <이름>` (예: `### 1.1 사전 분석`)
- 체크 항목: `- [ ] 항목` (미완료) / `- [x] 항목` (완료)

PRD 파서가 인식하는 패턴:

- 표 행: `| FR-GO-NNN | 제목 | ... |`

## 관련 문서

- 트랙 단위 정의: [TASK_gitops.md](./task/TASK_gitops.md)
- 트랙 범위: [SCOPE_gitops.md](./scope/SCOPE_gitops.md)
- 진행 이력: [HISTORY_gitops.md](./history/HISTORY_gitops.md)
