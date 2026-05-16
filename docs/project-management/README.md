# Project Management — synapse-gitops

이 폴더는 `workflow-dashboard`로 자동 sync되는 일정/진척 문서를 보관합니다.

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
