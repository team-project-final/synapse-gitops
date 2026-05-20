# Synapse Interactive Flow Simulator 설계 스펙

> **작성일**: 2026-05-20
> **범위**: 프로젝트 전체 흐름을 인터랙티브로 시뮬레이션하는 웹 페이지
> **레포**: `synapse-flow-simulator` (GitHub Pages 배포)
> **URL**: `https://team-project-final.github.io/synapse-flow-simulator/`

---

## 1. 목적

Synapse 프로젝트에 처음 접하는 개발자가 하나의 페이지에서 전체 시스템 흐름을 인터랙티브하게 탐색할 수 있도록 한다. 사용자 로그인부터 AI 카드 생성, 장애 상황, GitOps 배포까지 18개 시나리오를 애니메이션으로 시각화한다.

---

## 2. 기술 스택

| 기술 | 용도 |
|---|---|
| Vanilla HTML/CSS/JS | 엔진 (렌더러 + 인터랙션), 빌드 도구 없음 |
| JSON 데이터 파일 | 시나리오 정의 + 액터 정의 분리 |
| CSS Animation/Transition | 화살표 이동, glow 효과, 단계 전환 |
| SVG | 액터 박스, 화살표, 아이콘 |
| GitHub Pages | 정적 배포, main push 시 자동 |

---

## 3. 파일 구조

```
synapse-flow-simulator/
├── index.html                 # 엔진 (렌더러 + 스타일 + 인터랙션 올인원)
├── data/
│   ├── scenarios.json         # 18개 시나리오 메타데이터 + 흐름 정의
│   └── actors.json            # 액터 정의 (위치, 색상, 아이콘, 카테고리)
├── .github/
│   └── workflows/
│       └── deploy-pages.yml   # GitHub Pages 정적 배포
├── .gitignore
└── README.md
```

---

## 4. 화면 레이아웃

```
┌──────────────────────────────────────────────────────────────┐
│ [Synapse 로고] Flow Simulator       [아키텍처 뷰] [시퀀스 뷰] │
├──────────┬───────────────────────────────────┬───────────────┤
│ SCENARIOS│          메인 뷰 영역              │ STEP DETAIL   │
│          │                                   │               │
│ 🔐 인증  │  아키텍처 뷰: 컴포넌트 간           │ Step 2 of 5   │
│  ● 로그인│  화살표 애니메이션                  │ Gateway →     │
│  ○ OAuth │                                   │ Platform      │
│  ○ MFA   │  시퀀스 뷰: 시간순                 │               │
│  ○ RBAC  │  시퀀스 다이어그램                  │ POST /auth    │
│  ○ JWT   │                                   │ 200 OK (80ms) │
│          │                                   │               │
│ 🌊 흐름  │                                   │ ┌─ Request ──┐│
│  ○ 노트AI│                                   │ │ {json...}  ││
│  ○ 검색  │                                   │ └────────────┘│
│  ○ LLM   │                                   │ ┌─ Response ─┐│
│  ○ 복습  │                                   │ │ {json...}  ││
│  ○ 멱등성│                                   │ └────────────┘│
│          │  [◀ Prev]  Step 2/5  [Next ▶]    │               │
│ 💥 장애  │  [▶ Auto Play]                    │ [에러 분기]    │
│  ○ 500   │                                   │  ● 비밀번호X  │
│  ○ Crash │                                   │  ○ 계정 잠김  │
│  ○ DLQ   │                                   │  ○ bcrypt 실패│
│  ○ Schema│                                   │               │
│          │                                   │               │
│ ☁️ 운영  │                                   │               │
│  ○ Argo  │                                   │               │
│  ○ Image │                                   │               │
│  ○ ESO   │                                   │               │
│  ○ Trace │                                   │               │
├──────────┴───────────────────────────────────┴───────────────┤
│ 📋 요청/응답 로그 (하단, 모노스페이스, 시간순)                    │
│ → POST /api/v1/auth/login {email, password}                  │
│ ← 200 OK {accessToken, refreshToken} (80ms)                 │
└──────────────────────────────────────────────────────────────┘
```

### 레이아웃 비율

- 좌측 시나리오 패널: 200px 고정
- 중앙 메인 뷰: flex-grow (나머지)
- 우측 상세 패널: 280px 고정
- 하단 로그 패널: 120px 고정

### 반응형

- 1200px 이상: 3단 레이아웃 (시나리오 + 메인 + 상세)
- 800~1200px: 시나리오 드로어로 변환, 2단
- 800px 이하: 단일 컬럼, 시나리오/상세 토글

---

## 5. 뷰 모드

### 5.1 아키텍처 뷰

중앙에 전체 시스템 컴포넌트를 배치하고, 현재 단계의 데이터 흐름을 화살표 애니메이션으로 표시.

```
         ┌──────────┐
         │ Browser  │
         └────┬─────┘
              │ ← 활성 화살표 (glow)
         ┌────▼─────┐
         │ Gateway  │ ← 활성 컴포넌트 (확대 + glow)
         └────┬─────┘
    ┌─────┬───┴───┬──────┬──────┐
    │     │       │      │      │
 Platform Engage Know  Card    AI
    │                          │
 ┌──┴──┐  ┌─────┐  ┌───────┐
 │ PG  │  │Redis│  │ Kafka │
 └─────┘  └─────┘  └───────┘
```

- 활성 컴포넌트: 1.1x 확대, box-shadow glow
- 활성 화살표: 실선, 이동하는 점 애니메이션 (CSS `@keyframes`)
- 비활성 컴포넌트: opacity 0.4
- Kafka 이벤트: 번개 아이콘 + 토픽명 라벨

### 5.2 시퀀스 뷰

참여 액터를 상단에 배치하고, 시간순으로 메시지를 위→아래로 표시. 현재 단계 강조.

```
Browser    Gateway    Platform    Redis    PostgreSQL
  │           │          │         │          │
  ├──POST───→│          │         │          │  ← 현재 단계
  │           ├──route──→│         │          │
  │           │          ├──SELECT─────────→│
  │           │          │←─user data──────│
  │           │          ├──SET────→│         │
  │           │←─JWT─────│         │          │
  │←─200 OK──│          │         │          │
```

- 현재 단계: 화살표 빨간/파란 glow + 배경 하이라이트
- 이전 단계: opacity 0.6
- 미래 단계: opacity 0.2, 점선

---

## 6. 인터랙션

### 6.1 시나리오 선택

좌측 패널에서 시나리오 클릭 → 메인 뷰에 해당 시나리오의 첫 단계 로드. 카테고리별 접기/펼치기.

### 6.2 단계 진행

- **Next/Prev 버튼**: 한 단계씩 진행/되돌리기
- **Auto Play 버튼**: 2초 간격으로 자동 진행 (토글)
- **키보드**: ← → 화살표, Space(재생/멈춤)
- **단계 인디케이터**: `Step 2 of 5` + 프로그레스 바

### 6.3 에러 분기

우측 상세 패널에 "실패 분기" 라디오 버튼 표시. 선택하면 해당 에러 흐름으로 전환.

### 6.4 뷰 전환

상단 탭으로 아키텍처 ↔ 시퀀스 전환. 현재 단계 유지.

---

## 7. 데이터 구조

### 7.1 actors.json

```json
{
  "actors": {
    "browser": {
      "label": "Browser",
      "icon": "🌐",
      "color": "#4a9eff",
      "category": "client",
      "position": { "row": 0, "col": 2 }
    },
    "gateway": {
      "label": "Gateway",
      "icon": "🔀",
      "color": "#e94560",
      "category": "edge",
      "position": { "row": 1, "col": 2 }
    },
    "platform": {
      "label": "Platform",
      "icon": "👤",
      "color": "#1e3a5f",
      "category": "service",
      "position": { "row": 2, "col": 0 }
    },
    "engagement": {
      "label": "Engagement",
      "icon": "📊",
      "color": "#1e3a5f",
      "category": "service",
      "position": { "row": 2, "col": 1 }
    },
    "knowledge": {
      "label": "Knowledge",
      "icon": "📝",
      "color": "#1e3a5f",
      "category": "service",
      "position": { "row": 2, "col": 2 }
    },
    "learningCard": {
      "label": "Learning Card",
      "icon": "🃏",
      "color": "#1e3a5f",
      "category": "service",
      "position": { "row": 2, "col": 3 }
    },
    "learningAI": {
      "label": "Learning AI",
      "icon": "🤖",
      "color": "#1e3a5f",
      "category": "service",
      "position": { "row": 2, "col": 4 }
    },
    "postgresql": {
      "label": "PostgreSQL",
      "icon": "🐘",
      "color": "#336791",
      "category": "infra",
      "position": { "row": 3, "col": 1 }
    },
    "redis": {
      "label": "Redis",
      "icon": "⚡",
      "color": "#dc382d",
      "category": "infra",
      "position": { "row": 3, "col": 2 }
    },
    "kafka": {
      "label": "Kafka",
      "icon": "📨",
      "color": "#231f20",
      "category": "infra",
      "position": { "row": 3, "col": 3 }
    },
    "schemaRegistry": {
      "label": "Schema Registry",
      "icon": "📋",
      "color": "#5a5a5a",
      "category": "infra",
      "position": { "row": 3, "col": 4 }
    },
    "opensearch": {
      "label": "OpenSearch",
      "icon": "🔍",
      "color": "#005eb8",
      "category": "infra",
      "position": { "row": 3, "col": 0 }
    },
    "googleOAuth": {
      "label": "Google OAuth",
      "icon": "🔑",
      "color": "#4285f4",
      "category": "external",
      "position": { "row": 1, "col": 4 }
    },
    "claudeAPI": {
      "label": "Claude API",
      "icon": "🧠",
      "color": "#d97706",
      "category": "external",
      "position": { "row": 1, "col": 0 }
    },
    "openaiAPI": {
      "label": "OpenAI API",
      "icon": "💡",
      "color": "#10a37f",
      "category": "external",
      "position": { "row": 1, "col": 1 }
    },
    "argocd": {
      "label": "ArgoCD",
      "icon": "🔄",
      "color": "#ef7b4d",
      "category": "ops",
      "position": { "row": 0, "col": 0 }
    },
    "ecr": {
      "label": "ECR",
      "icon": "📦",
      "color": "#ff9900",
      "category": "ops",
      "position": { "row": 0, "col": 1 }
    },
    "secretsManager": {
      "label": "AWS Secrets Manager",
      "icon": "🔐",
      "color": "#dd344c",
      "category": "ops",
      "position": { "row": 0, "col": 3 }
    },
    "mobileApp": {
      "label": "Mobile App",
      "icon": "📱",
      "color": "#4a9eff",
      "category": "client",
      "position": { "row": 0, "col": 4 }
    }
  }
}
```

### 7.2 scenarios.json 단일 시나리오 구조

```json
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
      "method": "POST",
      "description": "클라이언트가 이메일+비밀번호로 로그인 요청을 Gateway로 전송",
      "payload": {
        "request": { "email": "alice@synapse.io", "password": "***" },
        "response": null
      },
      "duration": "5ms"
    },
    {
      "id": 2,
      "from": "gateway",
      "to": "platform",
      "label": "라우팅 (whitelist)",
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
        "response": "{ userId: 'uuid-...', passwordHash: '$2a$12$...' }"
      },
      "duration": "15ms"
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
        {
          "from": "platform",
          "to": "gateway",
          "label": "401 P_A001",
          "type": "error"
        },
        {
          "from": "gateway",
          "to": "browser",
          "label": "401 Invalid credentials",
          "type": "error"
        }
      ]
    }
  ]
}
```

---

## 8. 시각화 규칙

| 타입 | 화살표 스타일 | 색상 | 애니메이션 |
|---|---|---|---|
| `request` | 실선, 이동하는 점 | `#4a9eff` (blue) | dot-travel 300ms |
| `response` | 점선, 이동하는 점 | `#3fb950` (green) | dot-travel 300ms |
| `internal` | 실선 | `#8b949e` (gray) | fade-in 200ms |
| `query` | 가는 실선 | `#6e7681` (light gray) | dot-travel 200ms |
| `event` | 굵은 실선 + 토픽명 | `#d2a8ff` (purple) | pulse + dot-travel |
| `error` | 점선, 흔들림 | `#e94560` (red) | shake 300ms |

### 컴포넌트 상태

- **활성**: scale(1.08), box-shadow glow (컴포넌트 색상)
- **참여**: opacity 1.0
- **비참여**: opacity 0.3
- **에러**: border red, shake animation

---

## 9. 시나리오 목록 (18개)

### 카테고리 A: 인증 및 보안 (5개)

| # | ID | 제목 | 우선순위 |
|---|---|---|---|
| 1 | auth-login-basic | 로그인 (웹·모바일) | P0 |
| 2 | auth-oauth2 | OAuth2 (Google/GitHub) | P0 |
| 3 | auth-mfa-totp | MFA TOTP 2차 인증 | P0 |
| 4 | security-rbac-idor | 어드민 RBAC + IDOR 차단 | P1 |
| 5 | auth-jwt-refresh | JWT 만료 → 리프레시 | P0 |

### 카테고리 B: AI 및 이벤트 흐름 (5개)

| # | ID | 제목 | 우선순위 |
|---|---|---|---|
| 6 | flow-note-to-card | 노트 → AI 카드 → fan-in | P0 |
| 7 | flow-semantic-search | 시맨틱 검색 (pgvector) | P1 |
| 8 | flow-llm-fallback | LLM Fallback (Claude → OpenAI) | P0 |
| 9 | flow-review-gamification | 복습 → 점수 → 뱃지 | P1 |
| 10 | flow-idempotency | CloudEvents 멱등성 | P0 |

### 카테고리 C: 장애 및 복구 (4개)

| # | ID | 제목 | 우선순위 |
|---|---|---|---|
| 11 | failure-500-classified | 서비스 장애 분류 (500) | P1 |
| 12 | failure-crashloop | DB 연결 실패 → CrashLoopBackOff | P1 |
| 13 | failure-dlq | Kafka 실패 → DLQ → 재처리 | P1 |
| 14 | failure-schema-broken | Schema 호환성 깨짐 (CI) | P1 |

### 카테고리 D: 운영 및 GitOps (4개)

| # | ID | 제목 | 우선순위 |
|---|---|---|---|
| 15 | ops-argocd-sync | ArgoCD 자동 동기화 | P1 |
| 16 | ops-image-updater | Image Updater (semver) | P2 |
| 17 | ops-eso-rotation | External Secrets 5분 회전 | P2 |
| 18 | ops-distributed-tracing | 분산 추적 (traceId) | P0 |

---

## 10. 구현 우선순위

### Phase 1: 엔진 + P0 시나리오 7개

1. 엔진 (index.html): 레이아웃, 뷰 전환, 단계 진행, 애니메이션
2. actors.json: 전체 액터 정의
3. P0 시나리오 7개: #1, #2, #3, #5, #6, #8, #10, #18

### Phase 2: P1 시나리오 9개

4. #4, #7, #9, #11, #12, #13, #14, #15

### Phase 3: P2 시나리오 2개

5. #16, #17

---

## 11. 배포

- GitHub Pages: main push 시 루트 디렉토리 정적 배포
- 빌드 불필요 (순수 HTML/JS/JSON)
- `.github/workflows/deploy-pages.yml`:
  ```yaml
  on:
    push:
      branches: [main]
  jobs:
    deploy:
      runs-on: ubuntu-latest
      permissions:
        pages: write
        id-token: write
      steps:
        - uses: actions/checkout@v4
        - uses: actions/configure-pages@v5
        - uses: actions/upload-pages-artifact@v4
          with:
            path: '.'
        - uses: actions/deploy-pages@v4
  ```

---

## 12. 시나리오 상세 참조

각 시나리오의 상세 흐름, 페이로드, 실패 분기, 시뮬레이터 UI 요구사항은 사용자 제공 문서 참조:

> **`synapse-prototype/docs/SCENARIOS.md` v1.0** — 18개 시나리오 전체 명세
> - 액터, 흐름, 페이로드 예시, 실패 분기, 시뮬레이터 UI 힌트
> - 부록 B: JSON 메타데이터
> - 부록 C: 구현 우선순위 (Phase 1~3)
> - 부록 E: 컨벤션 정합성 체크
