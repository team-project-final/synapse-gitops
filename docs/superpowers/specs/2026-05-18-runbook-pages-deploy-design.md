# 설계: docs/runbooks GitHub Pages 배포 (Flutter Web)

> **날짜**: 2026-05-18
> **상태**: 승인됨
> **배경**: 팀 Flutter 스택 통일, 런북을 읽기 전용 문서 + 온보딩 워크스루로 배포

---

## 1. 개요

`docs/runbooks/` 의 19개 Markdown 런북을 Flutter Web 앱으로 빌드하여 GitHub Pages에 배포한다.

- **목적**: 읽기 전용 문서 뷰어 + 온보딩 가이드
- **기술 선택 이유**: 팀 주력 스택(Flutter) 통일
- **콘텐츠 관리**: 빌드 타임에 Markdown → JSON 파싱, Flutter assets로 포함
- **배포 URL**: `https://team-project-final.github.io/synapse-gitops/`

---

## 2. 프로젝트 구조

```
synapse-gitops/
├── docs/runbooks/              # 기존 Markdown 소스 (수정 없음)
├── site/                       # Flutter Web 프로젝트 (신규)
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app.dart
│   │   ├── models/
│   │   │   └── runbook.dart          # 런북 데이터 모델
│   │   ├── pages/
│   │   │   ├── home_page.dart        # 런북 목록 (카테고리별)
│   │   │   ├── runbook_page.dart     # 개별 런북 뷰어
│   │   │   └── onboarding_page.dart  # 온보딩 워크스루
│   │   └── widgets/
│   │       ├── sidebar.dart          # 네비게이션 사이드바
│   │       ├── markdown_viewer.dart  # Markdown 렌더링 위젯
│   │       └── code_block.dart       # 코드블록 + 복사 버튼
│   ├── assets/runbooks/        # 빌드 스크립트가 생성한 JSON
│   └── web/
│       └── index.html
├── scripts/
│   └── parse-runbooks.dart     # Markdown → JSON 변환 스크립트
└── .github/workflows/
    └── deploy-pages.yml        # GitHub Pages 배포 워크플로우
```

**핵심 결정**: Flutter 프로젝트는 `site/` 디렉토리에 격리하여 기존 GitOps 구조에 영향 없음.

---

## 3. Markdown 파싱 파이프라인

### 파싱 스크립트 (`scripts/parse-runbooks.dart`)

`docs/runbooks/*.md`를 읽어서 구조화된 JSON으로 변환한다.

**입력 (기존 런북 Markdown):**
```markdown
# Runbook: Kind 로컬 부트스트랩

> **대상**: 전체 팀원
> **소요 시간**: 30–45 분
> **결과**: 로컬 kind 클러스터 + ArgoCD 동작
> **사전 조건**: dev-machine-setup 완료
```

**출력 (JSON):**
```json
{
  "slug": "kind-local-bootstrap",
  "title": "Kind 로컬 부트스트랩",
  "metadata": {
    "target": "전체 팀원",
    "duration": "30–45 분",
    "result": "로컬 kind 클러스터 + ArgoCD 동작",
    "prerequisites": "dev-machine-setup 완료"
  },
  "category": "onboarding",
  "order": 0,
  "body": "... (마크다운 본문)"
}
```

### 카테고리 자동 분류 규칙

| 파일명 패턴 | 카테고리 | 정렬 |
|------------|---------|------|
| `step{N}-*.md` | `steps` | N 순서 |
| `w{N}-*.md` | `weekly` | N 순서 |
| `dev-machine-setup.md`, `kind-local-bootstrap.md` | `onboarding` | 파일명 순 |

### 파싱 방식

- `> **Key**: Value` 블록쿼트 메타데이터를 정규식으로 추출
- 본문(마크다운)은 원본 그대로 보존 → Flutter에서 `flutter_markdown`으로 렌더링
- 빌드 시 `site/assets/runbooks/index.json`에 전체 목록, 각 런북은 개별 JSON 파일로 출력

---

## 4. Flutter Web 앱 설계

### 패키지

| 패키지 | 용도 |
|--------|------|
| `flutter_markdown` | Markdown 본문 렌더링 |
| `go_router` | URL 기반 라우팅 |
| `google_fonts` | 한국어 폰트 (Noto Sans KR) |

### 라우팅

| 경로 | 페이지 | 설명 |
|------|--------|------|
| `/` | `HomePage` | 카테고리별 런북 목록 카드 |
| `/runbook/:slug` | `RunbookPage` | 개별 런북 뷰어 |
| `/onboarding` | `OnboardingPage` | 순서형 워크스루 |

### 페이지 설계

**HomePage** — 3개 카테고리 섹션:
- **온보딩**: dev-machine-setup → kind-local-bootstrap (카드 2개)
- **Step 가이드**: Step 1~12 (번호순 카드 리스트)
- **주간 런북**: W1~W5 (번호순 카드 리스트)
- 각 카드에 제목, 대상, 소요 시간 표시

**RunbookPage** — 개별 런북 뷰어:
- 상단: 메타데이터 칩 (대상, 소요 시간, 사전 조건)
- 본문: Markdown 렌더링 (코드블록에 복사 버튼)
- 하단: 이전/다음 런북 네비게이션

**OnboardingPage** — 순서형 워크스루:
- Stepper 형태 UI: 온보딩 2개 → Step 1~12 순서로 진행
- 현재 위치 하이라이트, 각 단계 클릭 시 해당 런북으로 이동

### 레이아웃

```
┌─────────────────────────────────────────┐
│  Synapse GitOps Runbooks      [검색]    │
├──────────┬──────────────────────────────┤
│ 사이드바  │  콘텐츠 영역                  │
│          │                              │
│ 온보딩    │  # Runbook: ...              │
│  ├ Dev   │  > 대상: ...                  │
│  └ Kind  │  > 소요 시간: ...             │
│          │                              │
│ Steps    │  ## 1. 첫 번째 단계           │
│  ├ 1     │  ```bash                     │
│  ├ 2     │  kubectl apply ...     [복사] │
│  ...     │  ```                         │
│          │                              │
│ Weekly   │  ◀ 이전  |  다음 ▶            │
│  ├ W1    │                              │
│  ...     │                              │
└──────────┴──────────────────────────────┘
```

- 반응형: 모바일에서 사이드바 → 햄버거 메뉴
- 라이트 모드 단일

---

## 5. GitHub Actions 배포 파이프라인

### 워크플로우 (`deploy-pages.yml`)

**트리거:**
```yaml
on:
  push:
    branches: [main]
    paths:
      - 'docs/runbooks/**'
      - 'site/**'
      - 'scripts/parse-runbooks.dart'
```

**빌드 단계:**
1. Checkout 코드
2. Dart SDK 설치 → `scripts/parse-runbooks.dart` 실행 → `site/assets/runbooks/*.json` 생성
3. Flutter SDK 설치 → `flutter build web --release --base-href /synapse-gitops/`
4. `build/web/` 산출물을 GitHub Pages에 배포 (`actions/deploy-pages@v4`)

### GitHub 설정 요구사항

| 설정 | 값 |
|------|-----|
| Pages Source | GitHub Actions |
| 배포 URL | `https://team-project-final.github.io/synapse-gitops/` |
| 필요 권한 | `pages: write`, `id-token: write` |

### 배포 흐름

```
런북 수정 PR 머지 → deploy-pages.yml 트리거 → parse-runbooks.dart (MD → JSON)
→ flutter build web → GitHub Pages 자동 배포
```

기존 `validate-manifests.yml`과 독립적으로 동작하며, 런북 Markdown만 수정해도 사이트가 자동 재배포된다.

---

## 6. 범위 외 (YAGNI)

- 다크 모드
- 검색 기능 (향후 필요 시 추가)
- 댓글/피드백
- 인증/권한
- 모바일 앱 빌드
- 체크리스트 상태 저장/진행률 추적
