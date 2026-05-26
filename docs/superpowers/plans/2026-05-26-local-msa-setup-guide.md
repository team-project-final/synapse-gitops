# 로컬 MSA 개발환경 온보딩 가이드 (HTML) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 신규 팀원이 자기 PC에서 Synapse MSA를 처음 띄워 동작 확인까지 따라 할 수 있는, 단일 자체완결 HTML 온보딩 가이드(`synapse-gitops/docs/local-msa-setup.html`)를 만든다.

**Architecture:** 외부 의존성 0의 단일 HTML 파일. 인라인 CSS(라이트 본문 + 다크 코드블록, 좌측 sticky TOC)와 최소 인라인 JS(스크롤 스파이, 복사 버튼, `<details>` 심화 콜아웃, `localStorage` 진행 체크박스, OS 탭 토글). 콘텐츠는 번호 단계의 선형 흐름(초보) + 펼침형 "심화" 박스(준시니어)로 두 수준을 동시 지원. 두 실행 경로(① 풀 컨테이너 = `synapse-gitops/docker-compose.yml`, ② 하이브리드 = `synapse-shared/docker-compose.yml`)를 있는 그대로 문서화한다.

**Tech Stack:** 순수 HTML5 + CSS + Vanilla JS (빌드/서버/프레임워크 없음). 검증은 브라우저 렌더 확인(playwright/browse 또는 `file://` 직접 열기).

**스펙:** `docs/superpowers/specs/2026-05-26-local-msa-setup-guide-design.md` (스펙 §8 미해결 항목은 아래 "검증된 사실"로 해소됨).

---

## 검증된 사실 (모든 태스크가 공유 — 이 값만 사용)

> 아래는 실제 compose/gradle 파일을 읽어 확정한 값이다. 가이드 내 모든 포트·명령은 반드시 이 값과 일치해야 한다. 추측 금지.

### 클론 대상 레포 (모두 `C:\workspace\team-project-final` 하위 형제 폴더)
`synapse-gitops`, `synapse-shared`, `synapse-gateway`, `synapse-platform-svc`, `synapse-engagement-svc`, `synapse-knowledge-svc`, `synapse-learning-svc`

### 사전 도구 (로컬 전용 — AWS CLI·kubectl 불필요)
| 도구 | 확인 명령 | 비고 |
|---|---|---|
| Docker Desktop | `docker --version` | Compose v2 포함 |
| JDK 21 (Temurin) | `java -version` | 모든 Spring 서비스 `JavaLanguageVersion.of(21)` |
| Git | `git --version` | |
| Python 3.11 | `python --version` | learning-ai (FastAPI) |
| (선택) Flutter | `flutter --version` | 프론트엔드 작업 시에만 |

> **확정 사실:** platform-svc·knowledge-svc·gateway의 `build.gradle.kts`는 `mavenCentral()`만 쓰고 `com.synapse:shared` Maven 의존성이 **없다**. 따라서 서비스 컴파일에 `synapse-shared`의 `publishToMavenLocal`은 **필요 없다.** (shared는 Avro 스키마 정의 + Schema Registry 등록 + 로컬 인프라 compose 제공 역할.) 가이드에 "shared 먼저 빌드해야 컴파일됨" 같은 문구를 넣지 말 것.

### 경로 ① 풀 컨테이너 — `synapse-gitops/docker-compose.yml`
- 앱 5개를 형제 레포에서 **빌드**(`build.context: ../synapse-*`) + ghcr 이미지 폴백. **Gateway 없음**(앱 직접 노출).
- 인프라 이미지: `pgvector/pgvector:pg16`, `redis:7-alpine`, `confluentinc/cp-zookeeper|cp-kafka|cp-schema-registry:7.6.1`, `docker.elastic.co/elasticsearch/elasticsearch:8.13.0`.
- 실행: `cd synapse-gitops && cp .env.example .env && docker compose up -d --build`
- 호스트 포트 / 헬스 체크:

| 대상 | 호스트 포트 | 헬스 URL |
|---|---|---|
| platform-svc | 8080 | `http://localhost:8080/actuator/health` |
| engagement-svc | 8082 | `http://localhost:8082/actuator/health` |
| knowledge-svc | 8083 | `http://localhost:8083/actuator/health` |
| learning-card | 8084 | `http://localhost:8084/actuator/health` |
| learning-ai | 8000 | `http://localhost:8000/health` |
| postgres / redis / kafka | 5432 / 6379 / 9092 | — |
| schema-registry | **8085** | `http://localhost:8085/subjects` |
| elasticsearch | 9200 | `http://localhost:9200/_cluster/health` |

- 종료: `docker compose down` (데이터 유지) / `docker compose down -v` (볼륨 삭제).

### 경로 ② 하이브리드 — `synapse-shared/docker-compose.yml` + 소스 실행
- compose는 인프라 + **gateway(빌드)** + 앱 **스텁**(sleep) 제공. 실제 앱은 직접 소스로 실행.
- 인프라 이미지: `postgres:16-alpine`, `redis:7-alpine`, `confluentinc/...:7.7.0`, **`opensearchproject/opensearch:2.11.0`**. `kafka-init`가 토픽 5개 자동 생성.
- 인프라만 실행(스텁/게이트웨이 포트 충돌 방지):
  `cd synapse-shared && docker compose up -d postgres redis zookeeper kafka schema-registry opensearch kafka-init`
- 호스트 포트: postgres 5432, redis 6379, kafka 9092, schema-registry **8086**, opensearch 9200, (전체 실행 시 gateway 8080).
- 본인 서비스 소스 실행:
  - Spring: `cd synapse-platform-svc && ./gradlew bootRun` (engagement/knowledge/learning-card 동일)
  - learning-ai: `cd synapse-learning-svc/learning-ai && pip install -r ../../synapse-learning-svc/learning-ai/requirements.txt && uvicorn app.main:app --reload --port 8000` (실제 경로/모듈은 작성 시 해당 레포 `pyproject.toml`/`app`으로 확인)
- 자동 생성 Kafka 토픽: `platform.auth.user-registered-v1`, `knowledge.note.note-created-v1`, `knowledge.note.note-updated-v1`, `learning.card.review-completed-v1`, `learning.ai.cards-generated-v1`

### ⚠️ 두 스택 동시 실행 금지
경로 ①과 ②는 **서로 다른 인프라 스택**(ES↔OpenSearch, kafka 7.6.1↔7.7.0, postgres pgvector↔alpine, SR 8085↔8086)이며 5432/6379/9092/9200 등 포트가 겹친다. **한 번에 하나만** 실행할 것. 전환 시 먼저 `docker compose down` 후 다른 쪽을 올린다. (이 스택 분기는 프로젝트의 알려진 기술부채이며 본 문서는 현황을 반영만 한다.)

---

## 파일 구조

| 파일 | 작업 | 책임 |
|---|---|---|
| `synapse-gitops/docs/local-msa-setup.html` | Create | 가이드 본체(단일 자체완결 HTML — CSS·JS 인라인) |
| `synapse-gitops/README.md` | Modify | "문서 > 시작하기"에 새 가이드 링크 1줄 |
| `synapse-gitops/docs/synapse-developer-guide.md` | Modify | §3 로컬 섹션 상단에 "초보용 단계별 HTML 가이드" 링크 1줄 |

> 단일 파일이므로 모든 콘텐츠 태스크는 같은 파일을 순차 편집한다. Task 1에서 정의한 **재사용 컴포넌트 스니펫**(step/callout/codeblock/tabs/table)을 이후 모든 섹션에서 그대로 사용한다.

---

## Task 1: HTML 스켈레톤 + 인라인 CSS + 컴포넌트 스니펫

**Files:**
- Create: `synapse-gitops/docs/local-msa-setup.html`

- [ ] **Step 1: 스켈레톤 + CSS 작성**

아래 내용으로 파일을 생성한다. `<main>` 안에는 빈 섹션 앵커만 둔다(콘텐츠는 이후 태스크에서 채움).

```html
<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Synapse 로컬 MSA 개발환경 세팅 가이드</title>
<style>
  :root{
    --bg:#f7f8fa; --panel:#fff; --ink:#1e293b; --muted:#64748b; --line:#e2e8f0;
    --accent:#2563eb; --accent-soft:#eff6ff; --warn-bg:#fff7ed; --warn-line:#fb923c;
    --code-bg:#0f172a; --code-ink:#e2e8f0; --code-key:#7dd3fc; --code-cmt:#94a3b8;
    --ok:#16a34a; --maxw:860px; --tocw:260px;
  }
  *{box-sizing:border-box}
  body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","Malgun Gothic",sans-serif;
    background:var(--bg);color:var(--ink);line-height:1.7;font-size:16px}
  a{color:var(--accent);text-decoration:none} a:hover{text-decoration:underline}
  .layout{display:grid;grid-template-columns:var(--tocw) 1fr;align-items:start;max-width:1180px;margin:0 auto}
  /* TOC */
  nav.toc{position:sticky;top:0;height:100vh;overflow-y:auto;padding:24px 16px;border-right:1px solid var(--line);background:var(--panel)}
  nav.toc h2{font-size:13px;text-transform:uppercase;letter-spacing:.05em;color:var(--muted);margin:0 0 12px}
  nav.toc a{display:block;padding:6px 10px;border-radius:6px;color:var(--muted);font-size:14px}
  nav.toc a.active{background:var(--accent-soft);color:var(--accent);font-weight:600}
  nav.toc .progress{margin-top:18px;font-size:13px;color:var(--muted)}
  /* Main */
  main{padding:40px 48px;max-width:calc(var(--maxw) + 96px)}
  header.hero{margin-bottom:32px}
  header.hero h1{font-size:30px;margin:0 0 8px}
  header.hero p{color:var(--muted);margin:0}
  section{padding:28px 0;border-top:1px solid var(--line);scroll-margin-top:20px}
  section:first-of-type{border-top:none}
  h2.sec{font-size:23px;margin:0 0 16px;display:flex;align-items:center;gap:10px}
  h2.sec .num{background:var(--accent);color:#fff;width:30px;height:30px;border-radius:50%;
    display:inline-flex;align-items:center;justify-content:center;font-size:15px;flex:none}
  h3{font-size:17px;margin:22px 0 8px}
  /* Step (체크박스 진행) */
  .step{display:flex;gap:10px;align-items:flex-start;margin:10px 0}
  .step input{margin-top:5px;width:16px;height:16px;flex:none}
  .step.done label{color:var(--muted);text-decoration:line-through}
  /* Code block + copy */
  .code{position:relative;background:var(--code-bg);color:var(--code-ink);border-radius:8px;
    padding:14px 16px;margin:12px 0;font-family:"SFMono-Regular",Consolas,monospace;font-size:13.5px;
    overflow-x:auto;white-space:pre}
  .code .copy{position:absolute;top:8px;right:8px;background:#1e293b;color:#cbd5e1;border:1px solid #334155;
    border-radius:6px;padding:3px 9px;font-size:12px;cursor:pointer}
  .code .copy:hover{background:#334155} .code .copy.copied{color:var(--ok);border-color:var(--ok)}
  /* Callout (심화) */
  details.deep{border:1px solid var(--line);border-radius:8px;padding:0 14px;margin:12px 0;background:var(--panel)}
  details.deep>summary{cursor:pointer;padding:12px 0;font-weight:600;color:#b45309;list-style:none}
  details.deep>summary::before{content:"▸ ";color:#f59e0b} details.deep[open]>summary::before{content:"▾ "}
  details.deep .body{padding:0 0 14px;color:#334155}
  /* Warn box */
  .warn{background:var(--warn-bg);border-left:4px solid var(--warn-line);border-radius:6px;padding:12px 16px;margin:14px 0}
  /* Tables */
  table{border-collapse:collapse;width:100%;margin:14px 0;font-size:14px}
  th,td{border:1px solid var(--line);padding:8px 10px;text-align:left} th{background:#f1f5f9}
  /* OS tabs */
  .tabs{display:flex;gap:6px;margin:12px 0 0}
  .tabs button{border:1px solid var(--line);background:var(--panel);border-radius:6px 6px 0 0;
    padding:6px 14px;cursor:pointer;font-size:13px;color:var(--muted)}
  .tabs button.active{background:var(--accent-soft);color:var(--accent);font-weight:600;border-bottom-color:var(--accent-soft)}
  .tab-panel{display:none} .tab-panel.active{display:block}
  /* Badges */
  .badge{font-size:11px;padding:2px 8px;border-radius:10px;font-weight:600}
  .badge.path1{background:#dcfce7;color:#166534} .badge.path2{background:#dbeafe;color:#1e40af}
  pre.ascii{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:14px;
    overflow-x:auto;font-family:"SFMono-Regular",Consolas,monospace;font-size:12.5px;line-height:1.45}
  @media(max-width:880px){
    .layout{grid-template-columns:1fr} nav.toc{position:static;height:auto;border-right:none;border-bottom:1px solid var(--line)}
    main{padding:24px 18px}
  }
</style>
</head>
<body>
<div class="layout">
  <nav class="toc" id="toc">
    <h2>목차</h2>
    <!-- TOC 링크는 Task 2에서 자동 생성하거나 수기 작성 -->
    <div class="progress" id="progress"></div>
  </nav>
  <main>
    <header class="hero">
      <h1>Synapse 로컬 MSA 개발환경 세팅 가이드</h1>
      <p>처음부터 따라 하면 내 PC에서 Synapse가 돌아갑니다 · 초보 ~ 준시니어용</p>
    </header>

    <section id="overview"><h2 class="sec"><span class="num">0</span>개요</h2></section>
    <section id="prereq"><h2 class="sec"><span class="num">1</span>사전 준비</h2></section>
    <section id="clone"><h2 class="sec"><span class="num">2</span>레포 클론</h2></section>
    <section id="path1"><h2 class="sec"><span class="num">3</span>경로 ① 풀 컨테이너 (빠른 체험)</h2></section>
    <section id="path2"><h2 class="sec"><span class="num">4</span>경로 ② 하이브리드 (실제 개발)</h2></section>
    <section id="data"><h2 class="sec"><span class="num">5</span>목업 · 시드 데이터 (선택)</h2></section>
    <section id="trouble"><h2 class="sec"><span class="num">6</span>트러블슈팅</h2></section>
    <section id="next"><h2 class="sec"><span class="num">7</span>다음 단계 · 더 깊이 보기</h2></section>
  </main>
</div>
<script>/* Task 2에서 채움 */</script>
</body>
</html>
```

- [ ] **Step 2: 브라우저로 렌더 확인**

`file:///C:/workspace/team-project-final/synapse-gitops/docs/local-msa-setup.html`을 브라우저로 연다(playwright `browser_navigate` 또는 직접).
Expected: 좌측 TOC 패널 + 우측 본문, 8개 섹션 제목(번호 배지 0~7)이 보인다. 콘솔 에러 없음.

- [ ] **Step 3: 커밋**

```bash
cd /c/workspace/team-project-final/synapse-gitops
git add docs/local-msa-setup.html
git commit -m "feat(docs): 로컬 MSA 세팅 가이드 HTML 스켈레톤 + CSS"
```

---

## Task 2: 인라인 JS — 스크롤 스파이 · 복사 버튼 · 진행 체크박스 · OS 탭

**Files:**
- Modify: `synapse-gitops/docs/local-msa-setup.html` (`<script>` 블록)

- [ ] **Step 1: JS 작성** — `<script>/* Task 2에서 채움 */</script>`를 아래로 교체

```html
<script>
(function(){
  // 1) TOC 자동 생성 (섹션 제목에서)
  var toc = document.getElementById('toc');
  var progressEl = document.getElementById('progress');
  var secs = Array.prototype.slice.call(document.querySelectorAll('main section[id]'));
  secs.forEach(function(s){
    var h = s.querySelector('h2.sec'); if(!h) return;
    var a = document.createElement('a');
    a.href = '#' + s.id; a.textContent = h.textContent.replace(/^\s*\d+/, '').trim() || h.textContent;
    a.dataset.target = s.id;
    toc.insertBefore(a, progressEl);
  });
  var tocLinks = Array.prototype.slice.call(toc.querySelectorAll('a'));

  // 2) 스크롤 스파이 (IntersectionObserver)
  var obs = new IntersectionObserver(function(entries){
    entries.forEach(function(e){
      if(e.isIntersecting){
        tocLinks.forEach(function(l){ l.classList.toggle('active', l.dataset.target === e.target.id); });
      }
    });
  }, {rootMargin:'-40% 0px -55% 0px'});
  secs.forEach(function(s){ obs.observe(s); });

  // 3) 코드블록 복사 버튼 (.code 마다 추가)
  document.querySelectorAll('.code').forEach(function(block){
    var btn = document.createElement('button');
    btn.className = 'copy'; btn.type = 'button'; btn.textContent = '복사';
    btn.addEventListener('click', function(){
      var text = block.getAttribute('data-cmd') || block.textContent.replace(/복사$/, '');
      navigator.clipboard.writeText(text.trim()).then(function(){
        btn.textContent = '복사됨'; btn.classList.add('copied');
        setTimeout(function(){ btn.textContent='복사'; btn.classList.remove('copied'); }, 1500);
      });
    });
    block.appendChild(btn);
  });

  // 4) 진행 체크박스 (localStorage)
  var KEY = 'synapse-local-setup-progress';
  var saved = JSON.parse(localStorage.getItem(KEY) || '{}');
  var boxes = Array.prototype.slice.call(document.querySelectorAll('.step input[type=checkbox]'));
  function refresh(){
    var done = boxes.filter(function(b){ return b.checked; }).length;
    progressEl.textContent = boxes.length ? ('진행 ' + done + ' / ' + boxes.length) : '';
  }
  boxes.forEach(function(b){
    if(saved[b.id]) { b.checked = true; b.closest('.step').classList.add('done'); }
    b.addEventListener('change', function(){
      b.closest('.step').classList.toggle('done', b.checked);
      saved[b.id] = b.checked; localStorage.setItem(KEY, JSON.stringify(saved)); refresh();
    });
  });
  refresh();

  // 5) OS 탭 토글 (.tabs[data-group] 내 button[data-os], 같은 그룹 .tab-panel[data-os])
  document.querySelectorAll('.tabs').forEach(function(tabs){
    var group = tabs.dataset.group;
    tabs.querySelectorAll('button[data-os]').forEach(function(btn){
      btn.addEventListener('click', function(){
        var os = btn.dataset.os;
        tabs.querySelectorAll('button').forEach(function(b){ b.classList.toggle('active', b===btn); });
        document.querySelectorAll('.tab-panel[data-group="'+group+'"]').forEach(function(p){
          p.classList.toggle('active', p.dataset.os === os);
        });
      });
    });
  });
})();
</script>
```

- [ ] **Step 2: 동작 검증을 위한 임시 콘텐츠 삽입**

`#overview` 섹션에 임시로 step·code·tabs 샘플을 넣어 동작을 확인한다(검증 후 Task 3에서 실제 콘텐츠로 대체):

```html
<div class="step"><input type="checkbox" id="t-demo"><label for="t-demo">데모 단계</label></div>
<div class="code">docker --version</div>
<div class="tabs" data-group="demo">
  <button data-os="win" class="active">Windows</button><button data-os="nix">macOS/Linux</button>
</div>
<div class="tab-panel active" data-group="demo" data-os="win">windows 내용</div>
<div class="tab-panel" data-group="demo" data-os="nix">nix 내용</div>
```

- [ ] **Step 3: 브라우저로 동작 확인**

파일을 브라우저로 다시 연다.
Expected: ① TOC에 8개 링크 자동 생성, 스크롤 시 현재 섹션 링크 `active` 하이라이트. ② 코드블록 우상단 "복사" 클릭 → "복사됨" 전환, 클립보드에 `docker --version`. ③ 데모 체크박스 체크 → 취소선 + 좌측 "진행 1 / 1", 새로고침 후에도 유지. ④ OS 탭 클릭 시 패널 전환.

- [ ] **Step 4: 임시 콘텐츠 제거 후 커밋**

Step 2의 데모 마크업을 삭제한다.

```bash
git add docs/local-msa-setup.html
git commit -m "feat(docs): 가이드 인라인 JS — TOC 스파이/복사/진행/탭"
```

---

## Task 3: §0 개요 — 아키텍처 + 두 경로 비교 + 동시실행 경고

**Files:**
- Modify: `synapse-gitops/docs/local-msa-setup.html` (`#overview` 섹션 본문)

- [ ] **Step 1: 콘텐츠 작성** — `#overview` 섹션 `<h2>` 뒤에 아래 요소를 채운다.

포함 항목(Task 1 컴포넌트 스니펫 사용):
1. 한 문단: "이 가이드를 끝내면 내 PC에서 Synapse MSA 전체(또는 내가 맡은 서비스)가 돌아갑니다. AWS 배포는 다루지 않습니다(→ §7 링크)."
2. 아키텍처 ASCII 다이어그램(`<pre class="ascii">`): 인프라(postgres·redis·kafka+zookeeper·schema-registry·검색엔진) → 앱(platform 8080 / engagement 8082 / knowledge 8083 / learning-card 8084 / learning-ai 8000) + (하이브리드 시 gateway 8080). 근거: `docs/synapse-developer-guide.md` §1 + `docs/docker-compose-workflow-guide.md` §2.
3. 두 경로 비교표(`<table>`) — "검증된 사실"의 경로①/② 표를 요약(앱 실행 방식, Gateway, 검색엔진, SR 포트, 용도, 대상). 각 행 머리에 `<span class="badge path1">①</span>` / `path2`.
4. 경고 박스(`<div class="warn">`): "두 경로는 서로 다른 인프라 스택이라 **동시 실행 금지**. 한 번에 하나만, 전환 시 `docker compose down` 먼저." ("검증된 사실 > ⚠️" 문구 사용)
5. 심화 콜아웃(`<details class="deep">`): "왜 스택이 둘로 갈렸나? (심화)" — ES↔OpenSearch, kafka 7.6.1↔7.7.0, SR 8085↔8086 차이는 레포 진화 과정의 기술부채이며 현황 반영임을 1~2문장.

- [ ] **Step 2: 브라우저 확인**

Expected: 다이어그램·비교표·주황 경고박스가 보이고, "심화" 박스 클릭 시 펼쳐짐. 비교표 포트가 "검증된 사실"과 일치.

- [ ] **Step 3: 커밋**

```bash
git add docs/local-msa-setup.html
git commit -m "docs(guide): §0 개요 — 아키텍처/두 경로 비교/경고"
```

---

## Task 4: §1 사전 준비

**Files:**
- Modify: `synapse-gitops/docs/local-msa-setup.html` (`#prereq` 섹션)

- [ ] **Step 1: 콘텐츠 작성**

1. 도입 문장 + "검증된 사실 > 사전 도구" 표를 그대로 렌더(도구/확인 명령/비고 열).
2. 확인 명령 묶음을 코드블록으로:

```
docker --version
java -version
git --version
python --version
```

3. OS 탭(`data-group="install"`)으로 설치 안내:
   - Windows 패널: `choco install docker-desktop temurin21 git python` (또는 각 공식 다운로드 링크)
   - macOS/Linux 패널: `brew install --cask docker temurin@21` / `brew install git python@3.11`
4. 경고/심화: `<details class="deep">` "AWS CLI·kubectl이 왜 없어도 되나? (심화)" — 로컬은 컨테이너/소스 실행만 쓰며 EKS 접근은 별도 가이드(§7) 담당.

- [ ] **Step 2: 브라우저 확인** — 표 렌더, OS 탭 전환, 복사 버튼 동작.

- [ ] **Step 3: 커밋**

```bash
git add docs/local-msa-setup.html
git commit -m "docs(guide): §1 사전 준비 (로컬 전용 도구)"
```

---

## Task 5: §2 레포 클론

**Files:**
- Modify: `synapse-gitops/docs/local-msa-setup.html` (`#clone` 섹션)

- [ ] **Step 1: 콘텐츠 작성**

1. "모든 레포를 같은 부모 폴더 아래 형제로 클론해야 합니다(compose가 `../synapse-*` 상대경로로 빌드)." 강조.
2. 클론 코드블록(`data-cmd` 속성에 줄바꿈 포함 명령 저장):

```
cd /c/workspace/team-project-final
git clone https://github.com/team-project-final/synapse-gitops.git
git clone https://github.com/team-project-final/synapse-shared.git
git clone https://github.com/team-project-final/synapse-gateway.git
git clone https://github.com/team-project-final/synapse-platform-svc.git
git clone https://github.com/team-project-final/synapse-engagement-svc.git
git clone https://github.com/team-project-final/synapse-knowledge-svc.git
git clone https://github.com/team-project-final/synapse-learning-svc.git
```

3. 결과 폴더 트리(`<pre class="ascii">`): 7개 형제 폴더 레이아웃.
4. 심화 콜아웃: "어떤 경로에 어떤 레포가 필요한가? (심화)" — 경로①은 gitops+서비스 레포들, 경로②는 shared+gateway+작업 서비스. (근거: 검증된 사실 build.context 목록)

> 클론 URL의 조직/레포명이 실제와 다르면 작성 시 `git remote -v`로 확인해 교체할 것.

- [ ] **Step 2: 브라우저 확인** — 코드블록 복사 시 7줄 전체 복사되는지(`data-cmd` 동작) 확인.

- [ ] **Step 3: 커밋**

```bash
git add docs/local-msa-setup.html
git commit -m "docs(guide): §2 레포 클론"
```

---

## Task 6: §3 경로 ① 풀 컨테이너 (gitops compose)

**Files:**
- Modify: `synapse-gitops/docs/local-msa-setup.html` (`#path1` 섹션)

- [ ] **Step 1: 콘텐츠 작성** — "검증된 사실 > 경로 ①" 값만 사용.

번호 단계(각 단계는 `.step` 체크박스 + 코드블록):
1. `.env` 생성: `cd synapse-gitops` → `cp .env.example .env` (로컬 기본값으로 동작; 외부 API는 mock 기본).
2. 전체 빌드+기동: `docker compose up -d --build` (최초 빌드는 수 분 소요 안내).
3. 상태 확인: `docker compose ps`.
4. 헬스 체크 코드블록(경로① 포트 표 그대로):

```
curl http://localhost:8080/actuator/health   # platform-svc
curl http://localhost:8082/actuator/health   # engagement-svc
curl http://localhost:8083/actuator/health   # knowledge-svc
curl http://localhost:8084/actuator/health   # learning-card
curl http://localhost:8000/health            # learning-ai
curl http://localhost:8085/subjects          # schema-registry
```

5. 종료: `docker compose down` / `docker compose down -v`.

심화 콜아웃 후보:
- "`--build`는 무슨 일을 하나? ghcr 이미지와의 관계 (심화)" — `build.context: ../synapse-*` 로컬 빌드, 미지정 시 ghcr 폴백.
- "메모리가 부족하면 (심화)" — 8GB 기준 메모리 설계(근거: `docker-compose-workflow-guide.md` §6), Docker Desktop 리소스 상향.
- "Gateway가 없는데 어떻게 호출하나? (심화)" — 경로①은 앱 포트를 직접 노출; Gateway 경유 라우팅은 경로②(또는 §7).

- [ ] **Step 2: 정확성 교차검증**

`synapse-gitops/docker-compose.yml`을 다시 열어 본문의 모든 포트/이미지/명령이 일치하는지 1:1 대조. 불일치 시 compose 값으로 수정.

- [ ] **Step 3: 브라우저 확인** — 단계 체크박스 진행 카운트 증가, 헬스 코드블록 복사 동작.

- [ ] **Step 4: 커밋**

```bash
git add docs/local-msa-setup.html
git commit -m "docs(guide): §3 경로① 풀 컨테이너 (gitops compose up --build)"
```

---

## Task 7: §4 경로 ② 하이브리드 (shared compose + 소스 실행)

**Files:**
- Modify: `synapse-gitops/docs/local-msa-setup.html` (`#path2` 섹션)

- [ ] **Step 1: 콘텐츠 작성** — "검증된 사실 > 경로 ②" 값만 사용.

번호 단계:
1. 인프라만 기동(스텁/게이트웨이 포트 충돌 방지):
   `cd synapse-shared && docker compose up -d postgres redis zookeeper kafka schema-registry opensearch kafka-init`
2. 인프라 검증 코드블록:

```
docker compose ps
docker exec -it synapse-kafka kafka-topics --list --bootstrap-server localhost:9092
curl http://localhost:8086/subjects
curl http://localhost:9200/_cluster/health
```

3. 본인 서비스 소스 실행(OS 탭 불필요, gradlew 래퍼 사용):
   - Spring 예: `cd synapse-platform-svc && ./gradlew bootRun` (engagement/knowledge/learning-card 동일 패턴 — 한 줄로 안내)
   - learning-ai: `cd synapse-learning-svc/learning-ai` 후 가상환경 + `uvicorn app.main:app --reload --port 8000` (정확한 모듈 경로는 해당 레포 `pyproject.toml`/`app/`로 확인 — 작성 시 확정)
4. 동작 확인: 실행한 서비스의 `/actuator/health`(Spring) 또는 `/health`(learning-ai).

심화 콜아웃:
- "왜 앱이 compose에서 stub인가? (심화)" — shared compose의 앱 서비스는 `sleep infinity` 스텁이며, 실제 앱은 IDE/gradlew로 직접 실행해 코드 수정→재기동 루프를 빠르게 돌리기 위함.
- "포트가 충돌해요 (심화)" — gateway(8080)와 platform 기본 8080 충돌 가능 → 인프라만 올리고 필요한 서비스만 소스로 실행하거나 `--args='--server.port=...'`로 조정.
- "shared를 mavenLocal에 publish해야 하나? (심화)" — **아니오.** 서비스는 `mavenCentral`만 의존하며 `com.synapse:shared` Maven 의존성이 없음. shared는 Avro 스키마/스키마 등록/인프라 compose 용도. (검증된 사실)
- "Kafka 토픽은 누가 만드나? (심화)" — `kafka-init` 컨테이너가 5개 토픽 자동 생성(토픽명 나열).

- [ ] **Step 2: 정확성 교차검증**

`synapse-shared/docker-compose.yml` + 해당 서비스 `build.gradle.kts`(bootRun 사용 가능)와 본문 명령/포트 대조.

- [ ] **Step 3: 브라우저 확인** — 심화 4개 펼침 동작, 코드블록 복사.

- [ ] **Step 4: 커밋**

```bash
git add docs/local-msa-setup.html
git commit -m "docs(guide): §4 경로② 하이브리드 (shared 인프라 + 소스 실행)"
```

---

## Task 8: §5 목업·시드 데이터 · §6 트러블슈팅 · §7 다음 단계

**Files:**
- Modify: `synapse-gitops/docs/local-msa-setup.html` (`#data`, `#trouble`, `#next` 섹션)

- [ ] **Step 1: §5 목업·시드 데이터(선택) 작성**

- "초기 데이터 없이도 서비스는 뜹니다. 화면/통합 테스트용 목업·시드는 별도 가이드 참조." 1문단.
- 링크: `moking-data-guide/index.html`(저장소 내 별도 HTML 가이드)와 `synapse-shared/scripts/seed-test-data.sh`. 상대경로는 가이드 파일 위치 기준으로 작성(`../../moking-data-guide/index.html` 형태 — 작성 시 실제 깊이 확인).

- [ ] **Step 2: §6 트러블슈팅 작성** (`<table>` 또는 `<details>` 묶음). 최소 항목:

| 증상 | 원인 | 해결 |
|---|---|---|
| 포트 충돌(5432/9092 등) | 두 스택 동시 실행 또는 기존 프로세스 | `docker compose down` 후 단일 스택만; `netstat`로 점유 확인 |
| 검색엔진 컨테이너 OOM | ES/OpenSearch 메모리 | Docker Desktop 메모리 상향; `vm.max_map_count=262144`(Linux/WSL) |
| Apple Silicon에서 kafka 느림 | Confluent amd64 에뮬레이션 | 정상; 초기 기동만 느림 |
| `up --build` 실패: 컨텍스트 없음 | 형제 레포 미클론 | §2의 7개 레포 형제 클론 확인 |
| `.env` 누락 경고 | `cp .env.example .env` 안 함 | §3 1단계 수행 |

근거: `docker-compose-workflow-guide.md` §9 + 검증된 사실.

- [ ] **Step 3: §7 다음 단계·더 깊이 보기 작성** — 링크 목록:

- `docs/synapse-developer-guide.md` — 올인원 개발자 가이드(레포별 구조, GitOps, AWS)
- `docs/docker-compose-workflow-guide.md` — compose 상세
- `docs/runbooks/bastion-ssm-access.md` — (AWS) EKS 접근
- `README.md` — gitops 레포 개요
> "AWS/EKS 배포는 이 가이드 범위 밖 — 위 문서들 참조" 명시.

- [ ] **Step 4: 브라우저 확인** — 세 섹션 렌더, 내부 링크 클릭 시 대상 파일로 이동(상대경로 정확).

- [ ] **Step 5: 커밋**

```bash
git add docs/local-msa-setup.html
git commit -m "docs(guide): §5 데이터 · §6 트러블슈팅 · §7 다음 단계"
```

---

## Task 9: 최종 QA + 교차 링크 + 마무리

**Files:**
- Modify: `synapse-gitops/README.md`, `synapse-gitops/docs/synapse-developer-guide.md`

- [ ] **Step 1: 전체 브라우저 QA**

파일을 브라우저로 열고 확인:
- 8개 섹션 모두 콘텐츠 있음(빈 섹션 없음), 콘솔 에러 0.
- TOC 8개 링크 + 스크롤 스파이 하이라이트 정상.
- 모든 코드블록 복사 버튼 동작(특히 §2 멀티라인 `data-cmd`).
- 모든 `.step` 체크박스 진행 카운트 반영 + 새로고침 후 유지.
- 모든 `<details class="deep">` 펼침/접힘.
- OS 탭(§1 등) 전환.
- 880px 이하로 리사이즈 시 TOC가 상단으로 접힘(반응형).

- [ ] **Step 2: 정확성 최종 점검**

`synapse-gitops/docker-compose.yml`·`synapse-shared/docker-compose.yml`을 마지막으로 대조해 가이드의 모든 포트(8080/8082/8083/8084/8000/8085/8086/9200/9092/5432/6379)·이미지·명령이 일치하는지 확인.

- [ ] **Step 3: README 링크 추가**

`synapse-gitops/README.md` "문서 > 시작하기" 목록 최상단에 추가:

```markdown
- **[로컬 MSA 세팅 가이드 (HTML)](docs/local-msa-setup.html)** — 신규 팀원용 단계별 로컬 개발환경 세팅 (초보~준시니어, AWS 제외)
```

- [ ] **Step 4: developer-guide 링크 추가**

`docs/synapse-developer-guide.md` "## 3. 로컬 개발 환경 세팅" 바로 아래 줄에 추가:

```markdown
> 🚀 처음이라면 단계별 HTML 가이드부터: **[로컬 MSA 세팅 가이드](local-msa-setup.html)**
```

- [ ] **Step 5: 최종 커밋**

```bash
git add docs/local-msa-setup.html README.md docs/synapse-developer-guide.md
git commit -m "docs(guide): 최종 QA + README/developer-guide 교차 링크"
```

---

## Self-Review (작성자 체크리스트 결과)

**1. 스펙 커버리지:** 스펙 §5 콘텐츠 구조 → Task 3~8에 매핑(§3 mavenLocal 단계는 검증 결과 불필요로 확정되어 제거, Task 7 심화로 "왜 불필요한지" 설명). §4 레벨링(펼침형 심화) → 모든 콘텐츠 태스크에 `<details class="deep">`. §6 시각/JS 기능 5종 → Task 1~2. §8 미해결(compose 경로) → "검증된 사실"에서 확정. §9 검증 → Task 6/7 교차검증 + Task 9 QA. §10 범위 밖(AWS/kind) → 본문 미포함, §7 링크만.

**2. 플레이스홀더 스캔:** 모든 명령/포트/이미지는 실제 파일 검증값. learning-ai 모듈 경로·moking-data-guide 상대경로·클론 URL 3곳은 "작성 시 확인" 지시 + 확인 방법 명시(파일 위치/`git remote`/`pyproject.toml`)로 처리.

**3. 타입/이름 일관성:** CSS 클래스(`.code/.step/.deep/.warn/.tabs/.tab-panel/.badge`)와 JS 셀렉터(`.code`, `.step input`, `.tabs[data-group]`, `.tab-panel[data-group][data-os]`, `data-cmd`)가 Task 1↔2↔콘텐츠 태스크 전반에서 일치. 포트 표 값이 Task 3/6/7/9에서 동일.
