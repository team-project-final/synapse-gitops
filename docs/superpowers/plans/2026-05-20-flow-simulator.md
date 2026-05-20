# Synapse Flow Simulator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 18개 시나리오를 인터랙티브 애니메이션으로 시각화하는 단일 페이지 시뮬레이터를 별도 레포에 구축하고 GitHub Pages로 배포한다.

**Architecture:** 새 레포 `synapse-flow-simulator`를 생성하고, `index.html` (엔진) + `data/scenarios.json` + `data/actors.json` (데이터)로 구성한다. 빌드 도구 없이 순수 HTML/CSS/JS로 구현하며, GitHub Pages로 정적 배포한다. Phase 1에서 엔진 + P0 시나리오 3개 MVP를 배포하고, Phase 2~3에서 나머지 시나리오를 JSON 추가로 확장한다.

**Tech Stack:** HTML5, CSS3 (Animation/Grid/Flexbox), Vanilla JavaScript (ES2022), SVG, GitHub Pages

**Spec:** `docs/superpowers/specs/2026-05-20-flow-simulator-design.md`
**Scenarios:** 사용자 제공 시나리오 명세 v1.0 (18개)

---

## 파일 구조

| 액션 | 파일 | 책임 |
|---|---|---|
| Create | `synapse-flow-simulator/` | 새 레포 (GitHub) |
| Create | `index.html` | 엔진: 레이아웃 + 렌더러 + 애니메이션 + 인터랙션 |
| Create | `data/actors.json` | 액터 정의 (위치, 색상, 아이콘) |
| Create | `data/scenarios.json` | 시나리오 메타데이터 + 흐름 단계 + 실패 분기 |
| Create | `.github/workflows/deploy-pages.yml` | GitHub Pages 정적 배포 |
| Create | `.gitignore` | 표준 gitignore |
| Create | `README.md` | 프로젝트 설명 |

---

### Task 1: GitHub 레포 생성 + 프로젝트 초기화

**Files:**
- Create: `synapse-flow-simulator/` (로컬 + GitHub)
- Create: `.gitignore`
- Create: `README.md`
- Create: `.github/workflows/deploy-pages.yml`

- [ ] **Step 1: GitHub 레포 생성**

```bash
cd C:/workspace/team-project-manager/team-project-final
gh repo create team-project-final/synapse-flow-simulator --public --clone
cd synapse-flow-simulator
```

- [ ] **Step 2: .gitignore 생성**

`.gitignore`:
```
.DS_Store
.idea/
.vscode/
*.swp
.superpowers/
```

- [ ] **Step 3: README.md 생성**

`README.md`:
```markdown
# Synapse Flow Simulator

Synapse 프로젝트의 전체 시스템 흐름을 인터랙티브 애니메이션으로 시각화하는 웹 시뮬레이터.

🔗 **Live**: https://team-project-final.github.io/synapse-flow-simulator/

## 기능

- 18개 시나리오 (인증, AI 흐름, 장애, 운영)
- 아키텍처 뷰 + 시퀀스 뷰 탭 전환
- 단계별 클릭 진행 + 자동 재생
- 정상/에러 흐름 전환
- 요청/응답 페이로드 실시간 표시

## 기술 스택

- 순수 HTML/CSS/JS (빌드 도구 없음)
- CSS Animation + SVG
- GitHub Pages 정적 배포

## 시나리오 추가

`data/scenarios.json`에 시나리오 객체를 추가하면 자동으로 UI에 반영됩니다.
```

- [ ] **Step 4: GitHub Pages 워크플로우 생성**

`.github/workflows/deploy-pages.yml`:
```yaml
name: Deploy to GitHub Pages

on:
  push:
    branches: [main]

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: 'pages'
  cancel-in-progress: true

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/configure-pages@v5
      - uses: actions/upload-pages-artifact@v4
        with:
          path: '.'
      - uses: actions/deploy-pages@v4
        id: deployment
```

- [ ] **Step 5: 커밋 + 푸시**

```bash
git add .gitignore README.md .github/workflows/deploy-pages.yml
git commit -m "chore: init repo with README and GitHub Pages workflow"
git push origin main
```

- [ ] **Step 6: GitHub Pages 활성화**

```bash
gh api repos/team-project-final/synapse-flow-simulator/pages -X POST -f source.branch=main -f source.path="/" -f build_type=workflow 2>&1 || echo "Pages already enabled or will be enabled on first deploy"
```

---

### Task 2: actors.json 작성

**Files:**
- Create: `data/actors.json`

- [ ] **Step 1: actors.json 생성**

전체 시스템의 모든 액터를 정의한다. 각 액터는 label, icon (이모지), color, category, 아키텍처 뷰에서의 grid position을 포함한다.

`data/actors.json`: (스펙 섹션 7.1의 전체 내용)
```json
{
  "actors": {
    "browser": { "label": "Browser", "icon": "🌐", "color": "#4a9eff", "category": "client", "position": { "row": 0, "col": 2 } },
    "mobileApp": { "label": "Mobile App", "icon": "📱", "color": "#4a9eff", "category": "client", "position": { "row": 0, "col": 3 } },
    "gateway": { "label": "Gateway", "icon": "🔀", "color": "#e94560", "category": "edge", "position": { "row": 1, "col": 2 } },
    "platform": { "label": "Platform", "icon": "👤", "color": "#1e3a5f", "category": "service", "position": { "row": 2, "col": 0 } },
    "engagement": { "label": "Engagement", "icon": "📊", "color": "#1e3a5f", "category": "service", "position": { "row": 2, "col": 1 } },
    "knowledge": { "label": "Knowledge", "icon": "📝", "color": "#1e3a5f", "category": "service", "position": { "row": 2, "col": 2 } },
    "learningCard": { "label": "Learning Card", "icon": "🃏", "color": "#1e3a5f", "category": "service", "position": { "row": 2, "col": 3 } },
    "learningAI": { "label": "Learning AI", "icon": "🤖", "color": "#1e3a5f", "category": "service", "position": { "row": 2, "col": 4 } },
    "postgresql": { "label": "PostgreSQL", "icon": "🐘", "color": "#336791", "category": "infra", "position": { "row": 3, "col": 0 } },
    "redis": { "label": "Redis", "icon": "⚡", "color": "#dc382d", "category": "infra", "position": { "row": 3, "col": 1 } },
    "kafka": { "label": "Kafka", "icon": "📨", "color": "#231f20", "category": "infra", "position": { "row": 3, "col": 2 } },
    "schemaRegistry": { "label": "Schema Registry", "icon": "📋", "color": "#5a5a5a", "category": "infra", "position": { "row": 3, "col": 3 } },
    "opensearch": { "label": "OpenSearch", "icon": "🔍", "color": "#005eb8", "category": "infra", "position": { "row": 3, "col": 4 } },
    "googleOAuth": { "label": "Google OAuth", "icon": "🔑", "color": "#4285f4", "category": "external", "position": { "row": 1, "col": 4 } },
    "githubOAuth": { "label": "GitHub OAuth", "icon": "🐙", "color": "#24292e", "category": "external", "position": { "row": 1, "col": 0 } },
    "claudeAPI": { "label": "Claude API", "icon": "🧠", "color": "#d97706", "category": "external", "position": { "row": 1, "col": 0 } },
    "openaiAPI": { "label": "OpenAI API", "icon": "💡", "color": "#10a37f", "category": "external", "position": { "row": 1, "col": 1 } },
    "argocd": { "label": "ArgoCD", "icon": "🔄", "color": "#ef7b4d", "category": "ops", "position": { "row": 0, "col": 0 } },
    "ecr": { "label": "ECR", "icon": "📦", "color": "#ff9900", "category": "ops", "position": { "row": 0, "col": 1 } },
    "secretsManager": { "label": "Secrets Manager", "icon": "🔐", "color": "#dd344c", "category": "ops", "position": { "row": 0, "col": 4 } },
    "tempo": { "label": "Tempo", "icon": "📈", "color": "#f46800", "category": "ops", "position": { "row": 0, "col": 4 } },
    "git": { "label": "Git (main)", "icon": "📂", "color": "#f05032", "category": "ops", "position": { "row": 0, "col": 1 } },
    "eks": { "label": "EKS", "icon": "☸️", "color": "#326ce5", "category": "ops", "position": { "row": 0, "col": 3 } }
  }
}
```

- [ ] **Step 2: 커밋**

```bash
mkdir -p data
git add data/actors.json
git commit -m "feat: add actors.json with all system component definitions"
```

---

### Task 3: scenarios.json 작성 (Phase 1 — P0 시나리오 3개)

**Files:**
- Create: `data/scenarios.json`

MVP로 가장 핵심인 3개 시나리오를 먼저 구현한다: #1 로그인, #6 노트→AI 카드, #8 LLM Fallback.

- [ ] **Step 1: scenarios.json 생성 — 시나리오 #1 (로그인)**

`data/scenarios.json`:
```json
{
  "categories": [
    { "id": "auth", "label": "🔐 인증 및 보안", "order": 0 },
    { "id": "flow", "label": "🌊 AI 및 이벤트", "order": 1 },
    { "id": "failure", "label": "💥 장애 및 복구", "order": 2 },
    { "id": "ops", "label": "☁️ 운영 및 GitOps", "order": 3 }
  ],
  "scenarios": [
    {
      "id": "auth-login-basic",
      "title": "로그인 (웹·모바일)",
      "category": "auth",
      "priority": "P0",
      "status": "implemented",
      "description": "사용자가 이메일+비밀번호로 로그인하고 JWT를 발급받는 전체 흐름",
      "actors": ["browser", "gateway", "platform", "postgresql", "redis"],
      "steps": [
        {
          "id": 1,
          "from": "browser",
          "to": "gateway",
          "label": "POST /api/v1/auth/login",
          "type": "request",
          "description": "클라이언트가 이메일+비밀번호로 로그인 요청을 Gateway로 전송",
          "payload": {
            "request": "{ \"email\": \"alice@synapse.io\", \"password\": \"***\" }",
            "response": null
          },
          "duration": "5ms"
        },
        {
          "id": 2,
          "from": "gateway",
          "to": "platform",
          "label": "라우팅 (whitelist 경로)",
          "type": "internal",
          "description": "Gateway가 /auth/** 경로를 whitelist로 인식, JWT 검증 없이 Platform으로 전달",
          "payload": null,
          "duration": "2ms"
        },
        {
          "id": 3,
          "from": "platform",
          "to": "postgresql",
          "label": "SELECT users WHERE email=?",
          "type": "query",
          "description": "Platform이 PostgreSQL에서 사용자 조회 후 bcrypt 비밀번호 검증",
          "payload": {
            "request": "SELECT * FROM users WHERE email = 'alice@synapse.io'",
            "response": "{ userId: 'uuid-a1b2', passwordHash: '$2a$12$...' }"
          },
          "duration": "15ms"
        },
        {
          "id": 4,
          "from": "platform",
          "to": "redis",
          "label": "SET refresh:{userId}",
          "type": "query",
          "description": "Platform이 Redis에 Refresh Token 저장 (TTL 7일)",
          "payload": {
            "request": "SET refresh:uuid-a1b2 {refreshToken} EX 604800",
            "response": "OK"
          },
          "duration": "3ms"
        },
        {
          "id": 5,
          "from": "platform",
          "to": "gateway",
          "label": "JWT (AT 15min, RT 7day)",
          "type": "response",
          "description": "Platform이 RS256 JWT 생성 — Access Token(15분) + Refresh Token(7일)",
          "payload": {
            "request": null,
            "response": "{ \"accessToken\": \"eyJhbGc...\", \"refreshToken\": \"...\", \"expiresIn\": 900 }"
          },
          "duration": "5ms"
        },
        {
          "id": 6,
          "from": "gateway",
          "to": "browser",
          "label": "200 OK + JWT",
          "type": "response",
          "description": "Gateway가 응답을 클라이언트로 전달. 웹은 HttpOnly Cookie + body, 모바일은 body만",
          "payload": {
            "request": null,
            "response": "{ \"success\": true, \"data\": { \"accessToken\": \"eyJ...\", \"userId\": \"uuid-a1b2\", \"expiresIn\": 900 } }"
          },
          "duration": "2ms"
        }
      ],
      "failureBranches": [
        {
          "id": "wrong-password",
          "trigger": "비밀번호 불일치",
          "atStep": 3,
          "errorCode": "P_A001",
          "httpStatus": 401,
          "description": "bcrypt 검증 실패 → 401 Invalid credentials",
          "steps": [
            { "from": "postgresql", "to": "platform", "label": "user found", "type": "response" },
            { "from": "platform", "to": "gateway", "label": "401 P_A001", "type": "error" },
            { "from": "gateway", "to": "browser", "label": "401 Invalid credentials", "type": "error" }
          ]
        },
        {
          "id": "account-locked",
          "trigger": "계정 잠김 (5회 실패)",
          "atStep": 3,
          "errorCode": "P_A005",
          "httpStatus": 423,
          "description": "로그인 5회 실패 → 계정 잠김 423",
          "steps": [
            { "from": "platform", "to": "gateway", "label": "423 P_A005", "type": "error" },
            { "from": "gateway", "to": "browser", "label": "423 Account locked", "type": "error" }
          ]
        }
      ]
    },
    {
      "id": "flow-note-to-card",
      "title": "노트 → AI 카드 → fan-in",
      "category": "flow",
      "priority": "P0",
      "status": "partial",
      "description": "노트 생성 시 Kafka를 통해 AI 카드 생성 + 청킹 + 게이미피케이션이 동시에 트리거되는 이벤트 기반 흐름",
      "actors": ["browser", "gateway", "knowledge", "postgresql", "kafka", "learningAI", "claudeAPI", "learningCard", "engagement"],
      "steps": [
        {
          "id": 1,
          "from": "browser",
          "to": "gateway",
          "label": "POST /api/v1/notes",
          "type": "request",
          "description": "사용자가 노트 생성 요청",
          "payload": { "request": "{ \"title\": \"Kafka 기초\", \"content\": \"Apache Kafka는 분산 메시징 시스템으로...\" }", "response": null },
          "duration": "5ms"
        },
        {
          "id": 2,
          "from": "gateway",
          "to": "knowledge",
          "label": "JWT 검증 → 라우팅",
          "type": "internal",
          "description": "Gateway가 JWT 유효성 확인 후 Knowledge 서비스로 라우팅",
          "payload": null,
          "duration": "3ms"
        },
        {
          "id": 3,
          "from": "knowledge",
          "to": "postgresql",
          "label": "INSERT notes",
          "type": "query",
          "description": "Knowledge 서비스가 PostgreSQL에 노트 저장",
          "payload": { "request": "INSERT INTO notes (id, tenant_id, title, content) VALUES (...)", "response": "INSERT 1" },
          "duration": "10ms"
        },
        {
          "id": 4,
          "from": "knowledge",
          "to": "kafka",
          "label": "NoteCreated (CloudEvents)",
          "type": "event",
          "description": "Knowledge가 Kafka에 NoteCreated 이벤트 발행 — CloudEvents 래핑, traceparent 전파",
          "payload": { "request": "Topic: knowledge.note.note-created-v1\n{ specversion: '1.0', type: 'NoteCreated', data: { noteId, title, content } }", "response": null },
          "duration": "5ms"
        },
        {
          "id": 5,
          "from": "kafka",
          "to": "learningAI",
          "label": "NoteCreated → AI 처리",
          "type": "event",
          "description": "[fan-in 1/3] Learning AI가 NoteCreated 이벤트 수신 → Claude API로 학습 카드 생성",
          "payload": null,
          "duration": "100ms"
        },
        {
          "id": 6,
          "from": "learningAI",
          "to": "claudeAPI",
          "label": "카드 생성 프롬프트",
          "type": "request",
          "description": "Learning AI가 Claude API에 노트 본문을 전송하여 학습 카드 생성 요청",
          "payload": { "request": "model: claude-sonnet-4-20250514\nprompt: '다음 노트에서 학습 카드를 생성해주세요...'", "response": null },
          "duration": "2500ms"
        },
        {
          "id": 7,
          "from": "claudeAPI",
          "to": "learningAI",
          "label": "카드 JSON 응답",
          "type": "response",
          "description": "Claude가 생성한 학습 카드 JSON 반환",
          "payload": { "request": null, "response": "{ cards: [{ front: 'Kafka란?', back: '분산 메시징 시스템...' }, ...] }" },
          "duration": "0ms"
        },
        {
          "id": 8,
          "from": "learningAI",
          "to": "kafka",
          "label": "CardsGenerated",
          "type": "event",
          "description": "Learning AI가 생성된 카드를 Kafka에 발행",
          "payload": { "request": "Topic: learning.ai.cards-generated-v1", "response": null },
          "duration": "3ms"
        },
        {
          "id": 9,
          "from": "kafka",
          "to": "learningCard",
          "label": "CardsGenerated → 저장",
          "type": "event",
          "description": "Learning Card 서비스가 생성된 카드를 PostgreSQL에 저장",
          "payload": null,
          "duration": "15ms"
        },
        {
          "id": 10,
          "from": "kafka",
          "to": "engagement",
          "label": "NoteCreated → +5점",
          "type": "event",
          "description": "[fan-in 2/3] Engagement가 NoteCreated 수신 → 작성 포인트 +5점 부여",
          "payload": { "request": null, "response": "policy: NOTE_CREATED → +5 points" },
          "duration": "10ms"
        }
      ],
      "failureBranches": [
        {
          "id": "llm-timeout",
          "trigger": "Claude API 타임아웃",
          "atStep": 6,
          "errorCode": "LRNG_AI001",
          "httpStatus": 504,
          "description": "Claude API 3회 재시도 실패 → OpenAI fallback (시나리오 #8 참조)",
          "steps": [
            { "from": "claudeAPI", "to": "learningAI", "label": "Timeout (3회)", "type": "error" },
            { "from": "learningAI", "to": "openaiAPI", "label": "Fallback → GPT-4o-mini", "type": "request" },
            { "from": "openaiAPI", "to": "learningAI", "label": "카드 JSON", "type": "response" }
          ]
        }
      ]
    },
    {
      "id": "flow-llm-fallback",
      "title": "LLM Fallback (Claude → OpenAI)",
      "category": "flow",
      "priority": "P0",
      "status": "implemented",
      "description": "Claude API 실패 시 OpenAI로 자동 전환되는 이중화 흐름. tenacity 지수 백오프 + 일일 토큰 제한",
      "actors": ["learningAI", "claudeAPI", "openaiAPI", "redis"],
      "steps": [
        {
          "id": 1,
          "from": "learningAI",
          "to": "claudeAPI",
          "label": "카드 생성 요청 (1차)",
          "type": "request",
          "description": "Learning AI가 Claude API에 카드 생성 요청 — tenacity 데코레이터 적용",
          "payload": { "request": "model: claude-sonnet-4-20250514\nmax_tokens: 2000", "response": null },
          "duration": "1000ms"
        },
        {
          "id": 2,
          "from": "claudeAPI",
          "to": "learningAI",
          "label": "500 Internal Error",
          "type": "error",
          "description": "Claude API 서버 에러 → tenacity가 1초 대기 후 재시도",
          "payload": { "request": null, "response": "500 Internal Server Error" },
          "duration": "1000ms"
        },
        {
          "id": 3,
          "from": "learningAI",
          "to": "claudeAPI",
          "label": "재시도 2/3 (2초 대기)",
          "type": "request",
          "description": "지수 백오프: 2초 대기 후 2차 재시도",
          "payload": null,
          "duration": "2000ms"
        },
        {
          "id": 4,
          "from": "claudeAPI",
          "to": "learningAI",
          "label": "429 Rate Limited",
          "type": "error",
          "description": "Claude API 속도 제한 → 3차 재시도 대기",
          "payload": { "request": null, "response": "429 Too Many Requests" },
          "duration": "4000ms"
        },
        {
          "id": 5,
          "from": "learningAI",
          "to": "claudeAPI",
          "label": "재시도 3/3 (4초 대기)",
          "type": "request",
          "description": "마지막 재시도",
          "payload": null,
          "duration": "500ms"
        },
        {
          "id": 6,
          "from": "claudeAPI",
          "to": "learningAI",
          "label": "503 Service Unavailable",
          "type": "error",
          "description": "Claude 3회 모두 실패 → except 블록 진입, OpenAI fallback 시작",
          "payload": { "request": null, "response": "logger.warning('Claude failed, falling back to OpenAI')" },
          "duration": "0ms"
        },
        {
          "id": 7,
          "from": "learningAI",
          "to": "openaiAPI",
          "label": "Fallback → GPT-4o-mini",
          "type": "request",
          "description": "OpenAI gpt-4o-mini로 같은 요청 전송",
          "payload": { "request": "model: gpt-4o-mini\nmax_tokens: 2000", "response": null },
          "duration": "1500ms"
        },
        {
          "id": 8,
          "from": "openaiAPI",
          "to": "learningAI",
          "label": "200 OK + 카드 JSON",
          "type": "response",
          "description": "OpenAI 성공 → 응답 메타에 model: 'gpt-4o-mini' 표시",
          "payload": { "request": null, "response": "{ cards: [...], meta: { model: 'gpt-4o-mini', fallback: true } }" },
          "duration": "0ms"
        },
        {
          "id": 9,
          "from": "learningAI",
          "to": "redis",
          "label": "토큰 사용량 기록",
          "type": "query",
          "description": "@track_tokens 데코레이터가 일일 토큰 누적 기록 (500K/day 한도)",
          "payload": { "request": "INCRBY tokens:daily:2026-05-20 1500", "response": "OK (total: 45000/500000)" },
          "duration": "2ms"
        }
      ],
      "failureBranches": [
        {
          "id": "both-fail",
          "trigger": "Claude + OpenAI 모두 실패",
          "atStep": 7,
          "errorCode": "LRNG_AI001",
          "httpStatus": 503,
          "description": "두 LLM 모두 실패 → 503 + DLQ 보관",
          "steps": [
            { "from": "openaiAPI", "to": "learningAI", "label": "503 Unavailable", "type": "error" },
            { "from": "learningAI", "to": "kafka", "label": "→ DLQ", "type": "error" }
          ]
        },
        {
          "id": "token-limit",
          "trigger": "일일 토큰 한도 초과",
          "atStep": 1,
          "errorCode": "LRNG_AI002",
          "httpStatus": 429,
          "description": "500K tokens/day 한도 초과 → 즉시 차단",
          "steps": [
            { "from": "learningAI", "to": "redis", "label": "CHECK tokens:daily", "type": "query" },
            { "from": "redis", "to": "learningAI", "label": "500000 (LIMIT)", "type": "error" }
          ]
        }
      ]
    }
  ]
}
```

- [ ] **Step 2: 커밋**

```bash
git add data/scenarios.json
git commit -m "feat: add scenarios.json with 3 P0 scenarios (login, note-to-card, llm-fallback)"
```

---

### Task 4: index.html 엔진 구현

**Files:**
- Create: `index.html`

이것이 시뮬레이터의 핵심이다. 전체 레이아웃 + CSS 애니메이션 + 렌더러 + 인터랙션을 단일 파일에 담는다. 코드가 길므로 구조별로 설명한다.

- [ ] **Step 1: index.html 작성**

`index.html` 파일을 생성한다. 이 파일은 3개 영역으로 구성된다:
1. `<style>` — 레이아웃, 다크 테마, 애니메이션
2. `<body>` — HTML 구조 (시나리오 패널, 메인 뷰, 상세 패널, 로그)
3. `<script>` — 데이터 로드, 렌더러, 인터랙션 로직

전체 코드는 구현 시 작성한다. 핵심 요구사항:

**HTML 구조:**
```html
<div id="app">
  <header id="topbar">
    <span class="logo">⚡ Synapse Flow Simulator</span>
    <div class="view-tabs">
      <button class="tab active" data-view="architecture">아키텍처 뷰</button>
      <button class="tab" data-view="sequence">시퀀스 뷰</button>
    </div>
  </header>
  <main>
    <aside id="sidebar"><!-- 시나리오 목록 --></aside>
    <section id="main-view">
      <div id="architecture-view"><!-- SVG 기반 아키텍처 다이어그램 --></div>
      <div id="sequence-view" hidden><!-- 시퀀스 다이어그램 --></div>
      <div id="controls"><!-- Prev/Next/Play 버튼 + 프로그레스 바 --></div>
    </section>
    <aside id="detail-panel"><!-- 단계 상세 + 에러 분기 --></aside>
  </main>
  <footer id="log-panel"><!-- 요청/응답 로그 --></footer>
</div>
```

**CSS 핵심:**
- 다크 테마 (`background: #0d1117`, `color: #e6edf3`)
- CSS Grid: `grid-template-columns: 200px 1fr 280px`
- 화살표 애니메이션: `@keyframes dot-travel` (이동하는 점)
- 활성 컴포넌트: `transform: scale(1.08)`, `box-shadow: 0 0 20px {color}40`
- 에러 흔들림: `@keyframes shake`
- 반응형: `@media (max-width: 1200px)`, `@media (max-width: 800px)`

**JS 핵심 함수:**
- `loadData()` — actors.json + scenarios.json fetch
- `renderSidebar(scenarios)` — 카테고리별 시나리오 목록 생성
- `selectScenario(id)` — 시나리오 선택 시 뷰 초기화
- `renderArchitectureView(scenario, step)` — 아키텍처 뷰 렌더링
- `renderSequenceView(scenario, step)` — 시퀀스 뷰 렌더링
- `renderDetailPanel(step, failureBranches)` — 우측 상세 패널
- `appendLog(step)` — 하단 로그 추가
- `nextStep()` / `prevStep()` — 단계 진행
- `toggleAutoPlay()` — 자동 재생 토글
- `selectFailureBranch(branchId)` — 에러 분기 전환
- 키보드: `←` `→` 단계, `Space` 재생/멈춤

- [ ] **Step 2: 로컬 테스트**

```bash
# Python 간이 서버로 로컬 테스트
python -m http.server 8000
# → http://localhost:8000 에서 확인
```

Expected:
- 좌측에 3개 시나리오 (로그인, 노트→AI, LLM Fallback)
- 시나리오 클릭 → 아키텍처 뷰에 컴포넌트 표시
- Next/Prev 클릭 → 단계별 애니메이션
- 탭 전환 → 시퀀스 뷰
- 에러 분기 라디오 → 에러 흐름 전환

- [ ] **Step 3: 커밋**

```bash
git add index.html
git commit -m "feat: add simulator engine with architecture/sequence views and animations"
```

---

### Task 5: 배포 + 검증

**Files:**
- 변경 없음 (push만)

- [ ] **Step 1: Push + Pages 배포**

```bash
git push origin main
```

GitHub Actions `deploy-pages` 워크플로우가 자동 실행된다.

- [ ] **Step 2: 배포 확인**

```bash
gh run list --workflow=deploy-pages.yml --limit 1
```

Expected: `completed`, `success`

- [ ] **Step 3: 라이브 URL 확인**

https://team-project-final.github.io/synapse-flow-simulator/ 에서:
- 시나리오 목록 표시
- 아키텍처 뷰 + 시퀀스 뷰 전환
- 단계별 애니메이션 동작
- 에러 분기 전환

---

### Task 6: 나머지 시나리오 추가 (Phase 2+3)

**Files:**
- Modify: `data/scenarios.json`

이 태스크는 Phase 1 배포 확인 후 진행한다. scenarios.json에 시나리오 객체를 추가하면 엔진이 자동으로 렌더링한다.

- [ ] **Step 1: Phase 2 시나리오 추가 (P1 9개)**

scenarios.json의 `scenarios` 배열에 다음 시나리오 추가:
- #2 auth-oauth2
- #3 auth-mfa-totp
- #4 security-rbac-idor
- #5 auth-jwt-refresh
- #7 flow-semantic-search
- #9 flow-review-gamification
- #10 flow-idempotency
- #11 failure-500-classified
- #12 failure-crashloop
- #13 failure-dlq
- #14 failure-schema-broken
- #15 ops-argocd-sync

각 시나리오의 상세 흐름은 사용자 제공 시나리오 명세 v1.0의 해당 섹션을 참조하여 steps와 failureBranches를 작성한다.

- [ ] **Step 2: Phase 3 시나리오 추가 (P2 2개)**

- #16 ops-image-updater
- #17 ops-eso-rotation
- #18 ops-distributed-tracing

- [ ] **Step 3: 커밋 + Push**

```bash
git add data/scenarios.json
git commit -m "feat: add remaining 15 scenarios (Phase 2+3)"
git push origin main
```
