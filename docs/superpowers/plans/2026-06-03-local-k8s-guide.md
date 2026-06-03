# local-k8s 온보딩 가이드 (단일 HTML) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** synapse local-k8s 스택의 서비스간 연결·Kafka 구독/소비·연결 주소·요청/응답 API를 보여주는 애니메이션+탐색형 자체완결 단일 HTML 온보딩 가이드를 만든다.

**Architecture:** 외부 의존성 0의 바닐라 HTML/CSS/JS+SVG 단일 파일. 시스템 전체를 기술하는 단일 `SYSTEM` 데이터 객체에서 인터랙티브 아키텍처 맵·드릴다운 패널·이벤트 흐름 애니메이션·종합 레퍼런스가 모두 렌더링된다. 빌드/번들 없음.

**Tech Stack:** HTML5, CSS(인라인), 바닐라 JS(ES2020), 인라인 SVG, SVG `<animateMotion>`/`requestAnimationFrame`.

**검증 방식(단일 파일 제약 적응):** 테스트 러너가 없으므로 ⓐ 파일 내 `SELFTEST` 함수(콘솔 `console.assert` 기반 데이터 참조 무결성 검증 — 파일을 열면 자동 실행, DevTools 콘솔로 PASS/FAIL 확인) + ⓑ 브라우저 수동 동작 검증을 병행한다. 각 태스크는 둘 중 적합한 것으로 검증한다.

**산출물:** `synapse-gitops/docs/local-k8s-guide.html`
**브랜치:** `docs/local-k8s-guide` (spec `5af80f2` 위에서 작업)
**참조 spec:** `docs/superpowers/specs/2026-06-03-local-k8s-guide-design.md`

---

## File Structure

단일 파일 `docs/local-k8s-guide.html`. 파일 내부를 명확한 섹션 주석으로 구획한다:

```
<!DOCTYPE html> … <head> (메타, 인라인 <style>) … </head>
<body>
  <header id="topbar"> … </header>
  <main>
    <section id="map-region">   ← 6.1 아키텍처 맵 (SVG)
    <aside  id="panel-region">  ← 6.2 드릴다운 패널
    <section id="flow-region">  ← 6.3 이벤트 흐름 플레이어
    <section id="ref-region">   ← 6.4 종합 레퍼런스
  </main>
  <footer id="footer"> … </footer>
  <script>
    /* ===== SYSTEM DATA ===== */   const SYSTEM = { … }
    /* ===== SELFTEST ===== */      function runSelfTests(){ … }
    /* ===== RENDER: MAP ===== */   function renderMap(){…} …
    /* ===== RENDER: PANEL ===== */ function openPanel(id){…}
    /* ===== RENDER: FLOW ===== */  function playScenario(name){…}
    /* ===== RENDER: REFERENCE ===== */ function renderReference(){…}
    /* ===== INIT ===== */          window.addEventListener('DOMContentLoaded', init)
  </script>
</body>
```

데이터(`SYSTEM`)와 렌더 로직을 파일 내에서 명확히 분리한다. 아키텍처 변경 시 `SYSTEM`만 수정.

---

## Phase 1 — 스캐폴드 & 데이터 모델

### Task 1: HTML 스켈레톤 + 테마 CSS + 레이아웃 영역

**Files:**
- Create: `synapse-gitops/docs/local-k8s-guide.html`

- [ ] **Step 1: 스켈레톤 작성** — 아래 내용으로 파일 생성. 다크 테마 CSS 변수 + 5개 레이아웃 영역(헤더/맵/패널/플로우/레퍼런스/푸터)의 빈 골격.

```html
<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Synapse local-k8s 가이드</title>
<style>
  :root{
    --bg:#0e1116; --panel:#161b22; --line:#30363d; --fg:#e6edf3; --muted:#8b949e;
    --rest:#58a6ff; --kafka:#d29922; --store:#3fb950; --accent:#bc8cff;
    --mono:"SFMono-Regular",Consolas,"Liberation Mono",monospace;
  }
  *{box-sizing:border-box} html,body{margin:0;background:var(--bg);color:var(--fg);
    font-family:system-ui,"Segoe UI","Malgun Gothic",sans-serif;font-size:14px}
  #topbar{display:flex;gap:16px;align-items:center;padding:10px 16px;border-bottom:1px solid var(--line);position:sticky;top:0;background:var(--bg);z-index:10}
  #topbar h1{font-size:16px;margin:0}
  main{display:grid;grid-template-columns:1fr 340px;grid-template-areas:"map panel" "flow panel" "ref ref";gap:12px;padding:12px}
  #map-region{grid-area:map;min-height:420px;background:var(--panel);border:1px solid var(--line);border-radius:8px}
  #panel-region{grid-area:panel;background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:12px;overflow:auto;max-height:80vh}
  #flow-region{grid-area:flow;background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:12px}
  #ref-region{grid-area:ref;background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:12px}
  code,.mono{font-family:var(--mono)}
  .muted{color:var(--muted)}
  footer{padding:10px 16px;border-top:1px solid var(--line);color:var(--muted);font-size:12px}
  button{background:#21262d;color:var(--fg);border:1px solid var(--line);border-radius:6px;padding:5px 10px;cursor:pointer}
  button.active{border-color:var(--accent);color:var(--accent)}
</style>
</head>
<body>
  <header id="topbar">
    <h1>Synapse <span class="muted">local-k8s</span> 가이드</h1>
    <span id="layer-toggles"></span>
    <span id="scenario-picker" style="margin-left:auto"></span>
  </header>
  <main>
    <section id="map-region"></section>
    <aside id="panel-region"><p class="muted">노드나 연결을 클릭하면 상세가 표시됩니다.</p></aside>
    <section id="flow-region"></section>
    <section id="ref-region"></section>
  </main>
  <footer id="footer"></footer>
  <script>
    // 다음 태스크에서 SYSTEM/렌더 함수 추가
    window.addEventListener('DOMContentLoaded', ()=>{ /* init */ });
  </script>
</body>
</html>
```

- [ ] **Step 2: 브라우저 검증** — 파일을 더블클릭(또는 `start docs/local-k8s-guide.html`)해 연다.
  Expected: 다크 배경, 상단에 "Synapse local-k8s 가이드", 맵/패널/플로우/레퍼런스 4개 빈 카드 영역, 패널에 "노드나 연결을 클릭하면…" 안내. 콘솔 에러 없음.

- [ ] **Step 3: 커밋**

```bash
git add docs/local-k8s-guide.html
git commit -m "feat(guide): HTML 스켈레톤 + 다크 테마 레이아웃"
```

### Task 2: SYSTEM 데이터 객체 스켈레톤 + SELFTEST 무결성 검증

**Files:**
- Modify: `synapse-gitops/docs/local-k8s-guide.html` (`<script>` 내)

- [ ] **Step 1: SELFTEST 작성(실패 우선)** — 아직 `SYSTEM`이 없는 상태에서 검증 함수를 먼저 추가. `<script>` 상단에 삽입:

```js
function runSelfTests(){
  const errs=[];
  const svc=Object.keys(SYSTEM.services), inf=Object.keys(SYSTEM.infra);
  const nodes=new Set([...svc,...inf]);
  // 모든 REST 엣지의 from/to가 실재 노드
  SYSTEM.rest.forEach(r=>{ if(!nodes.has(r.from)||!nodes.has(r.to)) errs.push("rest 노드 미존재: "+r.from+"→"+r.to); });
  // 모든 토픽의 producer/consumer가 실재 서비스
  SYSTEM.events.forEach(e=>{ if(!SYSTEM.services[e.producer]) errs.push("토픽 producer 미존재: "+e.topic);
    e.consumers.forEach(c=>{ if(!SYSTEM.services[c]) errs.push("토픽 consumer 미존재: "+e.topic+"/"+c); }); });
  // 모든 시나리오 step의 참조 노드/엣지 유효
  SYSTEM.scenarios.forEach(s=>s.steps.forEach((st,i)=>{ if(st.node && !nodes.has(st.node)) errs.push("시나리오 노드 미존재: "+s.name+"#"+i); }));
  console.assert(errs.length===0, "[SELFTEST FAIL]\n"+errs.join("\n"));
  console.log(errs.length===0 ? "[SELFTEST PASS] services="+svc.length+" infra="+inf.length+" topics="+SYSTEM.events.length+" rest="+SYSTEM.rest.length : "[SELFTEST FAIL] "+errs.length+"건");
  return errs;
}
```

- [ ] **Step 2: SYSTEM 스켈레톤 추가** — SELFTEST 위에 골격 데이터(서비스 6 + gateway, 인프라 6, 5.2~5.5 정본 골격). 정확한 값은 spec 5절 기준:

```js
const SYSTEM = {
  services: {
    gateway:      {label:"gateway", addr:"gateway", port:8080, tier:"edge", color:"#bc8cff", role:"API 게이트웨이(Spring Cloud Gateway)", rest:[], produces:[], consumes:[], stores:["redis"], calls:["platform","engagement","knowledge","learning-card","learning-ai"]},
    platform:     {label:"platform-svc", addr:"platform-svc", port:8080, tier:"svc", color:"#58a6ff", role:"auth/user/billing/notification", rest:[], produces:["platform.auth.user-registered-v1"], consumes:[], stores:["postgres:synapse_platform","redis"], calls:[]},
    engagement:   {label:"engagement-svc", addr:"engagement-svc", port:8080, tier:"svc", color:"#3fb950", role:"인게이지먼트(이벤트 소비)", rest:[], produces:[], consumes:["platform.auth.user-registered-v1","learning.card.review-completed-v1"], stores:["postgres:synapse_engagement","redis"], calls:[]},
    knowledge:    {label:"knowledge-svc", addr:"knowledge-svc", port:8080, tier:"svc", color:"#f778ba", role:"노트/지식", rest:[], produces:["knowledge.note.note-created-v1","knowledge.note.note-updated-v1"], consumes:[], stores:["postgres:synapse_knowledge","redis","opensearch"], calls:[]},
    "learning-ai":{label:"learning-ai", addr:"learning-ai", port:8080, tier:"svc", color:"#e3b341", role:"AI 카드 생성(Python)", rest:[], produces:["learning.ai.cards-generated-v1"], consumes:["knowledge.note.note-created-v1","knowledge.note.note-updated-v1"], stores:["postgres:synapse_learning_ai","redis","opensearch"], calls:["knowledge","learning-card"]},
    "learning-card":{label:"learning-card", addr:"learning-card", port:8080, tier:"svc", color:"#ff7b72", role:"학습 카드/복습", rest:[], produces:["learning.card.review-completed-v1"], consumes:["learning.ai.cards-generated-v1"], stores:["postgres:synapse_learning","redis"], calls:[]},
  },
  infra: {
    kafka:{label:"kafka", addr:"kafka", port:9092, kind:"broker"},
    "schema-registry":{label:"schema-registry", addr:"schema-registry", port:8081, kind:"registry"},
    zookeeper:{label:"zookeeper", addr:"zookeeper", port:2181, kind:"coord"},
    postgres:{label:"postgres", addr:"postgres", port:5432, kind:"db"},
    redis:{label:"redis", addr:"redis", port:6379, kind:"cache"},
    opensearch:{label:"opensearch", addr:"opensearch", port:9200, kind:"search"},
  },
  rest: [
    {from:"gateway", to:"platform",      basePath:"/api/platform/**",  endpoints:[]},
    {from:"gateway", to:"engagement",    basePath:"/api/engagement/**",endpoints:[]},
    {from:"gateway", to:"knowledge",     basePath:"/api/knowledge/**", endpoints:[]},
    {from:"gateway", to:"learning-card", basePath:"/api/learning/**",  endpoints:[]},
    {from:"gateway", to:"learning-ai",   basePath:"/api/learning/**",  endpoints:[]},
    {from:"learning-ai", to:"knowledge",     basePath:"http://knowledge-svc",  endpoints:[]},
    {from:"learning-ai", to:"learning-card", basePath:"http://learning-card",  endpoints:[]},
  ],
  events: [
    {topic:"platform.auth.user-registered-v1",  producer:"platform",      consumers:["engagement"],      schemaFields:[], partitions:3},
    {topic:"knowledge.note.note-created-v1",     producer:"knowledge",     consumers:["learning-ai"],     schemaFields:[], partitions:3},
    {topic:"knowledge.note.note-updated-v1",     producer:"knowledge",     consumers:["learning-ai"],     schemaFields:[], partitions:3},
    {topic:"learning.card.review-completed-v1",  producer:"learning-card", consumers:["engagement"],      schemaFields:[], partitions:3},
    {topic:"learning.ai.cards-generated-v1",     producer:"learning-ai",   consumers:["learning-card"],   schemaFields:[], partitions:3},
  ],
  connections: [
    {name:"Kafka", addr:"kafka:9092", envVars:["KAFKA_BOOTSTRAP_SERVERS","KAFKA_BROKERS"], protocol:"PLAINTEXT", consumers:["platform","engagement","knowledge","learning-ai","learning-card"]},
    {name:"Schema Registry", addr:"schema-registry:8081", envVars:["SCHEMA_REGISTRY_URL"], protocol:"HTTP", consumers:["platform","engagement","knowledge","learning-ai","learning-card"]},
    {name:"PostgreSQL", addr:"postgres:5432", envVars:["SPRING_DATASOURCE_URL","DATABASE_HOST"], protocol:"JDBC", consumers:["platform","engagement","knowledge","learning-ai","learning-card"]},
    {name:"Redis", addr:"redis:6379", envVars:["SPRING_DATA_REDIS_HOST"], protocol:"RESP", consumers:["gateway","platform","engagement","knowledge","learning-card"]},
    {name:"OpenSearch", addr:"opensearch:9200", envVars:["OPENSEARCH_URL"], protocol:"HTTP", consumers:["knowledge","learning-ai"]},
  ],
  dtos: {},
  scenarios: [
    {name:"사용자 가입", steps:[
      {node:"gateway", kind:"rest", narration:"클라이언트가 gateway로 POST /api/platform/auth/... 요청"},
      {node:"platform", kind:"rest", narration:"gateway가 platform-svc로 라우팅, 사용자 등록 처리"},
      {node:"kafka", kind:"event", narration:"platform-svc가 platform.auth.user-registered-v1 발행 (Avro→schema-registry)"},
      {node:"engagement", kind:"event", narration:"engagement-svc가 토픽 소비"}]},
    {name:"노트→카드 생성", steps:[
      {node:"knowledge", kind:"rest", narration:"knowledge-svc가 노트 생성"},
      {node:"kafka", kind:"event", narration:"knowledge.note.note-created-v1 발행"},
      {node:"learning-ai", kind:"event", narration:"learning-ai가 소비"},
      {node:"knowledge", kind:"rest", narration:"learning-ai가 REST로 노트 내용 조회"},
      {node:"kafka", kind:"event", narration:"learning-ai가 learning.ai.cards-generated-v1 발행"},
      {node:"learning-card", kind:"event", narration:"learning-card가 소비, 카드 저장"}]},
    {name:"복습 완료", steps:[
      {node:"gateway", kind:"rest", narration:"클라이언트가 gateway로 복습 완료 요청"},
      {node:"learning-card", kind:"rest", narration:"learning-card가 복습 결과 처리"},
      {node:"kafka", kind:"event", narration:"learning.card.review-completed-v1 발행"},
      {node:"engagement", kind:"event", narration:"engagement-svc가 소비"}]},
  ],
};
```

- [ ] **Step 2b: init에서 SELFTEST 호출** — `DOMContentLoaded` 핸들러를 `()=>{ runSelfTests(); }`로 교체.

- [ ] **Step 3: 브라우저 검증** — 파일을 새로고침하고 DevTools 콘솔 확인.
  Expected: `[SELFTEST PASS] services=6 infra=6 topics=5 rest=7`. assert 실패 없음.

- [ ] **Step 4: 커밋**

```bash
git add docs/local-k8s-guide.html
git commit -m "feat(guide): SYSTEM 데이터 골격 + SELFTEST 참조 무결성 검증"
```

---

## Phase 2 — 콘텐츠 전수 수집 (SYSTEM 채우기)

> 정확성이 온보딩 가치의 핵심. 각 태스크는 소스에서 추출 → `SYSTEM` 보강 → SELFTEST PASS 유지 + 소스 대조 spot-check.

### Task 3: Kafka 토픽 Avro 스키마 필드 수집

**Files:**
- Modify: `docs/local-k8s-guide.html` (`SYSTEM.events[].schemaFields`)
- 소스 참조: `synapse-shared/`(Avro `.avsc` 또는 계약), 각 서비스 `src/main/avro/` 또는 schema 디렉터리

- [ ] **Step 1: 스키마 소스 위치 확인**

Run:
```bash
find synapse-shared synapse-*/src -iname '*.avsc' -o -path '*avro*' -name '*.json' 2>/dev/null | head
grep -rl 'user-registered\|cards-generated\|review-completed\|note-created' synapse-shared synapse-*/src 2>/dev/null | head
```
Expected: Avro 스키마 파일 경로 목록.

- [ ] **Step 2: 5개 토픽 각각의 필드 추출 후 `schemaFields` 채우기** — 예(실제 필드명/타입은 소스 기준):

```js
// 예시 형식 (각 토픽에 적용)
{topic:"platform.auth.user-registered-v1", producer:"platform", consumers:["engagement"],
 schemaFields:[{name:"userId",type:"string"},{name:"email",type:"string"},{name:"registeredAt",type:"long(timestamp-millis)"}],
 partitions:3},
```

5개 토픽 전부에 대해 `.avsc`의 `fields[]`(name,type)를 옮긴다. 스키마가 없으면 producer 코드의 발행 payload에서 추론하고 `// 추정` 주석을 단다.

- [ ] **Step 3: 브라우저 검증** — 새로고침, 콘솔 `[SELFTEST PASS]` 유지. 임의 토픽의 `SYSTEM.events.find(e=>e.topic==='platform.auth.user-registered-v1').schemaFields`를 콘솔에서 출력해 소스와 대조.

- [ ] **Step 4: 커밋**

```bash
git add docs/local-k8s-guide.html
git commit -m "feat(guide): Kafka 토픽 Avro 스키마 필드 수집"
```

### Task 4: REST 엔드포인트 + DTO 전수 수집 (서비스별)

**Files:**
- Modify: `docs/local-k8s-guide.html` (`SYSTEM.services[id].rest`, `SYSTEM.dtos`, `SYSTEM.rest[].endpoints`)
- 소스: 각 서비스 컨트롤러 + DTO
  - platform: `synapse-platform-svc/src/main/java/**/*Controller.java`
  - engagement: `synapse-engagement-svc/src/main/java/**/*Controller.java`
  - knowledge: `synapse-knowledge-svc/src/main/java/**/*Controller.java`
  - learning-card: `synapse-learning-svc/src/main/java/**/*Controller.java`
  - learning-ai: `synapse-*learning-ai*/**`(Python — FastAPI/Flask 라우트 `@app.*`/`@router.*`)
  - gateway: `synapse-gateway/src/main/java/com/synapse/gateway/config/RoutesConfig.java`

- [ ] **Step 1: 컨트롤러/라우트 수집**

Run(서비스별 반복):
```bash
grep -rnE '@(Get|Post|Put|Delete|Patch|Request)Mapping' synapse-platform-svc/src/main/java 2>/dev/null | head -40
grep -rnE '@(app|router)\.(get|post|put|delete|patch)' synapse-*learning-ai* 2>/dev/null | head -40
```
Expected: method+path 목록.

- [ ] **Step 2: 각 서비스 `rest` 배열 채우기** — 형식(실제 값은 소스 기준):

```js
// SYSTEM.services.platform.rest 예시 항목
{method:"POST", path:"/api/platform/auth/register", reqDto:"RegisterRequest", resDto:"TokenResponse", desc:"회원가입"},
{method:"GET",  path:"/api/platform/users/me",      reqDto:null,            resDto:"UserResponse",  desc:"내 정보 조회"},
```

각 DTO는 `SYSTEM.dtos`에 1회 정의(필드+샘플):

```js
SYSTEM.dtos["RegisterRequest"] = {fields:[{name:"email",type:"string"},{name:"password",type:"string"}], sample:{email:"a@b.io",password:"***"}};
```

`SYSTEM.rest[]`의 gateway→서비스 항목 `endpoints`에는 해당 서비스 path 요약을 연결(맵 엣지 클릭 시 표시용). 6개 서비스(gateway 라우트 포함) 전부 처리.

- [ ] **Step 3: 브라우저 검증** — 새로고침, `[SELFTEST PASS]` 유지. 콘솔에서 `SYSTEM.services.platform.rest.length`가 0보다 큰지, 임의 DTO가 `SYSTEM.dtos`에 있는지 확인. 소스 컨트롤러 1개와 대조.

- [ ] **Step 4: 커밋**

```bash
git add docs/local-k8s-guide.html
git commit -m "feat(guide): 6개 서비스 REST 엔드포인트/DTO 전수 수집"
```

---

## Phase 3 — 렌더링 & 인터랙션

### Task 5: renderMap() — SVG 노드/엣지 (3단 티어)

**Files:**
- Modify: `docs/local-k8s-guide.html` (RENDER: MAP 섹션, `#map-region`)

- [ ] **Step 1: 좌표 테이블 + renderMap 작성** — 고정 배치(티어별 x 균등, y 고정). `#map-region`에 SVG 생성:

```js
const POS = { // [x,y] (viewBox 1000x440)
  gateway:[500,40],
  platform:[120,180], engagement:[300,180], knowledge:[500,180], "learning-ai":[700,180], "learning-card":[880,180],
  kafka:[300,330], "schema-registry":[500,330], zookeeper:[660,330],
  postgres:[120,400], redis:[300,400], opensearch:[700,400],
};
let activeLayers = {rest:true, kafka:true, store:true};
function edgeList(){
  const e=[];
  SYSTEM.rest.forEach(r=>e.push({a:r.from,b:r.to,type:"rest"}));
  SYSTEM.events.forEach(ev=>{ e.push({a:ev.producer,b:"kafka",type:"kafka",topic:ev.topic});
    ev.consumers.forEach(c=>e.push({a:"kafka",b:c,type:"kafka",topic:ev.topic})); });
  Object.entries(SYSTEM.services).forEach(([id,s])=>(s.stores||[]).forEach(st=>e.push({a:id,b:st.split(":")[0],type:"store"})));
  return e;
}
function renderMap(){
  const W=1000,H=440, ns="http://www.w3.org/2000/svg";
  const svg=document.createElementNS(ns,"svg");
  svg.setAttribute("viewBox",`0 0 ${W} ${H}`); svg.setAttribute("width","100%"); svg.id="map-svg";
  // 엣지
  edgeList().forEach(ed=>{ if(!activeLayers[ed.type]) return;
    const [x1,y1]=POS[ed.a]||[0,0], [x2,y2]=POS[ed.b]||[0,0];
    const p=document.createElementNS(ns,"line");
    p.setAttribute("x1",x1);p.setAttribute("y1",y1);p.setAttribute("x2",x2);p.setAttribute("y2",y2);
    p.setAttribute("stroke",ed.type==="rest"?"var(--rest)":ed.type==="kafka"?"var(--kafka)":"var(--store)");
    p.setAttribute("stroke-width",ed.type==="store"?1:2);
    if(ed.type==="kafka")p.setAttribute("stroke-dasharray","5 4");
    p.setAttribute("opacity","0.55"); p.dataset.a=ed.a; p.dataset.b=ed.b; p.dataset.type=ed.type;
    if(ed.topic)p.dataset.topic=ed.topic;
    p.style.cursor="pointer"; p.addEventListener("click",()=>openEdge(ed));
    svg.appendChild(p);
  });
  // 노드
  const all={...SYSTEM.services,...SYSTEM.infra};
  Object.entries(all).forEach(([id,n])=>{ const [x,y]=POS[id]||[0,0];
    const g=document.createElementNS(ns,"g"); g.style.cursor="pointer"; g.dataset.id=id;
    const isSvc=!!SYSTEM.services[id];
    const r=document.createElementNS(ns,"rect");
    r.setAttribute("x",x-58);r.setAttribute("y",y-16);r.setAttribute("width",116);r.setAttribute("height",32);
    r.setAttribute("rx",6); r.setAttribute("fill","#0d1117");
    r.setAttribute("stroke",isSvc?(n.color||"var(--rest)"):"var(--line)"); r.setAttribute("stroke-width",isSvc?2:1);
    const t=document.createElementNS(ns,"text"); t.setAttribute("x",x);t.setAttribute("y",y+4);
    t.setAttribute("text-anchor","middle");t.setAttribute("fill","var(--fg)");t.setAttribute("font-size","12");
    t.textContent=n.label;
    g.appendChild(r);g.appendChild(t);
    g.addEventListener("click",()=>openPanel(id));
    g.addEventListener("mouseenter",()=>highlight(id));
    g.addEventListener("mouseleave",()=>highlight(null));
    svg.appendChild(g);
  });
  const reg=document.getElementById("map-region"); reg.innerHTML=""; reg.appendChild(svg);
}
function openEdge(ed){ /* Task 7에서 구현 */ }
function highlight(id){ /* Task 6에서 구현 */ }
function openPanel(id){ /* Task 7에서 구현 */ }
```

init에 `renderMap()` 추가.

- [ ] **Step 2: 브라우저 검증** — 새로고침.
  Expected: 맵 영역에 13개 노드(상단 gateway, 중단 서비스 6, 하단 인프라 6)와 색상별 엣지(파랑 REST·주황 점선 Kafka·초록 store)가 보인다. 콘솔 에러 없음, `[SELFTEST PASS]` 유지.

- [ ] **Step 3: 커밋**

```bash
git add docs/local-k8s-guide.html
git commit -m "feat(guide): renderMap SVG 노드/엣지 3단 티어"
```

### Task 6: 레이어 토글 + hover 하이라이트

**Files:**
- Modify: `docs/local-k8s-guide.html` (RENDER: MAP, `#layer-toggles`)

- [ ] **Step 1: 토글 버튼 + highlight 구현**

```js
function renderLayerToggles(){
  const host=document.getElementById("layer-toggles"); host.innerHTML="";
  [["rest","REST"],["kafka","Kafka"],["store","Store"]].forEach(([k,label])=>{
    const b=document.createElement("button"); b.textContent=label; b.className=activeLayers[k]?"active":"";
    b.onclick=()=>{ activeLayers[k]=!activeLayers[k]; renderMap(); renderLayerToggles(); };
    host.appendChild(b);
  });
}
function highlight(id){
  const svg=document.getElementById("map-svg"); if(!svg)return;
  const related=new Set(); if(id){ related.add(id);
    edgeList().forEach(ed=>{ if(ed.a===id)related.add(ed.b); if(ed.b===id)related.add(ed.a); }); }
  svg.querySelectorAll("g[data-id]").forEach(g=>g.style.opacity=(!id||related.has(g.dataset.id))?"1":"0.25");
  svg.querySelectorAll("line").forEach(l=>l.setAttribute("opacity",(!id||l.dataset.a===id||l.dataset.b===id)?"0.9":"0.08"));
}
```

init에 `renderLayerToggles()` 추가.

- [ ] **Step 2: 브라우저 검증** — 새로고침.
  Expected: 헤더에 [REST][Kafka][Store] 버튼. 클릭 시 해당 엣지 종류가 사라졌다 나타남(active 테두리 토글). 노드에 마우스 올리면 그 노드+직접 연결만 강조되고 나머지는 흐려짐.

- [ ] **Step 3: 커밋**

```bash
git add docs/local-k8s-guide.html
git commit -m "feat(guide): 레이어 토글 + hover 하이라이트"
```

### Task 7: openPanel()/openEdge() — 드릴다운 패널

**Files:**
- Modify: `docs/local-k8s-guide.html` (RENDER: PANEL)

- [ ] **Step 1: 패널 렌더 구현**

```js
function row(k,v){ return `<div style="margin:4px 0"><span class="muted">${k}</span> ${v}</div>`; }
function openPanel(id){
  const n=SYSTEM.services[id]||SYSTEM.infra[id]; if(!n)return;
  let h=`<h3 style="margin-top:0">${n.label}</h3>`;
  h+=row("주소", `<code>${n.addr}:${n.port}</code>`);
  if(n.role)h+=row("역할", n.role);
  if(SYSTEM.services[id]){
    const s=SYSTEM.services[id];
    if(s.stores?.length)h+=row("데이터스토어", s.stores.map(x=>`<code>${x}</code>`).join(", "));
    if(s.produces?.length)h+=row("발행 토픽", s.produces.map(t=>`<code>${t}</code>`).join("<br>"));
    if(s.consumes?.length)h+=row("구독 토픽", s.consumes.map(t=>`<code>${t}</code>`).join("<br>"));
    if(s.rest?.length){ h+=`<div class="muted" style="margin-top:8px">REST 엔드포인트</div>`;
      h+=`<table style="width:100%;font-size:12px">`+s.rest.map(e=>`<tr><td><code>${e.method}</code></td><td><code>${e.path}</code></td><td>${e.desc||""}</td></tr>`).join("")+`</table>`; }
  }
  h+=`<p><button onclick="filterReference('${id}')">레퍼런스에서 보기 →</button></p>`;
  document.getElementById("panel-region").innerHTML=h;
}
function openEdge(ed){
  let h=`<h3 style="margin-top:0">연결: ${ed.a} → ${ed.b}</h3>`;
  h+=row("종류", ed.type.toUpperCase());
  if(ed.type==="kafka"&&ed.topic){ const ev=SYSTEM.events.find(e=>e.topic===ed.topic);
    h+=row("토픽", `<code>${ed.topic}</code>`);
    if(ev){ h+=row("producer", ev.producer); h+=row("consumers", ev.consumers.join(", "));
      if(ev.schemaFields?.length)h+=`<div class="muted">Avro 필드</div>`+ev.schemaFields.map(f=>`<div><code>${f.name}</code>: ${f.type}</div>`).join(""); } }
  if(ed.type==="rest"){ const r=SYSTEM.rest.find(x=>x.from===ed.a&&x.to===ed.b);
    if(r)h+=row("base", `<code>${r.basePath}</code>`); }
  document.getElementById("panel-region").innerHTML=h;
}
function filterReference(id){ /* Task 9에서 구현 */ document.getElementById("ref-region").scrollIntoView({behavior:"smooth"}); }
```

- [ ] **Step 2: 브라우저 검증** — 노드 클릭 시 우측 패널에 주소/역할/토픽/엔드포인트 표시, Kafka 엣지 클릭 시 토픽·Avro 필드 표시.

- [ ] **Step 3: 커밋**

```bash
git add docs/local-k8s-guide.html
git commit -m "feat(guide): 드릴다운 패널(노드/엣지 상세)"
```

### Task 8: playScenario() — 이벤트 흐름 애니메이션

**Files:**
- Modify: `docs/local-k8s-guide.html` (RENDER: FLOW, `#flow-region`, `#scenario-picker`)

- [ ] **Step 1: 시나리오 피커 + 애니메이션 구현** — 입자를 step 노드 좌표로 순차 이동(`requestAnimationFrame` 보간) + 단계 설명 표시.

```js
let flowTimer=null;
function renderScenarioPicker(){
  const host=document.getElementById("scenario-picker"); host.innerHTML="";
  SYSTEM.scenarios.forEach(s=>{ const b=document.createElement("button"); b.textContent="▶ "+s.name;
    b.onclick=()=>playScenario(s.name); host.appendChild(b); });
}
function renderFlowRegion(){ document.getElementById("flow-region").innerHTML=
  `<div id="flow-steps" class="muted">상단의 시나리오를 선택하면 흐름이 재생됩니다.</div>`; }
function playScenario(name){
  const sc=SYSTEM.scenarios.find(s=>s.name===name); if(!sc)return;
  const svg=document.getElementById("map-svg"); if(flowTimer)cancelAnimationFrame(flowTimer);
  // 입자 생성
  let dot=document.getElementById("flow-dot");
  const ns="http://www.w3.org/2000/svg";
  if(!dot){ dot=document.createElementNS(ns,"circle"); dot.id="flow-dot"; dot.setAttribute("r",7);
    dot.setAttribute("fill","#fff"); svg.appendChild(dot); }
  const steps=sc.steps, stepsHost=document.getElementById("flow-steps");
  let i=0;
  function showStep(k){ stepsHost.innerHTML=steps.map((st,idx)=>
    `<div style="padding:3px 0;${idx===k?'color:var(--accent);font-weight:600':'opacity:.6'}">${idx+1}. ${st.narration}</div>`).join(""); }
  function animateTo(from,to,done){
    const [x1,y1]=POS[from], [x2,y2]=POS[to]; const t0=performance.now(), dur=900;
    (function frame(t){ const p=Math.min(1,(t-t0)/dur);
      dot.setAttribute("cx",x1+(x2-x1)*p); dot.setAttribute("cy",y1+(y2-y1)*p);
      if(p<1)flowTimer=requestAnimationFrame(frame); else done(); })(t0);
  }
  function next(){ if(i>=steps.length){ return; } showStep(i);
    const from=steps[Math.max(0,i-1)].node, to=steps[i].node;
    animateTo(from,to,()=>{ i++; setTimeout(next, 350); }); }
  i=0; showStep(0); dot.setAttribute("cx",POS[steps[0].node][0]); dot.setAttribute("cy",POS[steps[0].node][1]);
  i=1; if(steps.length>1) next(); 
}
```

init에 `renderScenarioPicker()`, `renderFlowRegion()` 추가.

- [ ] **Step 2: 브라우저 검증** — 헤더 우측 "▶ 사용자 가입" 등 버튼 클릭 시 흰 입자가 gateway→platform→kafka→engagement 경로로 이동하고, 하단에 단계 설명이 현재 단계 강조와 함께 표시.

- [ ] **Step 3: 커밋**

```bash
git add docs/local-k8s-guide.html
git commit -m "feat(guide): 이벤트 흐름 애니메이션 플레이어"
```

### Task 9: renderReference() — 검색 가능한 종합 레퍼런스 + 맵 연동

**Files:**
- Modify: `docs/local-k8s-guide.html` (RENDER: REFERENCE, `#ref-region`)

- [ ] **Step 1: 레퍼런스 렌더 + 검색 필터 구현**

```js
let refFilter="";
function renderReference(){
  const q=refFilter.toLowerCase();
  const ep=[]; Object.entries(SYSTEM.services).forEach(([id,s])=>(s.rest||[]).forEach(e=>ep.push({svc:id,...e})));
  const epRows=ep.filter(e=>!q||(e.svc+e.method+e.path+(e.desc||"")).toLowerCase().includes(q))
    .map(e=>`<tr><td>${e.svc}</td><td><code>${e.method}</code></td><td><code>${e.path}</code></td><td>${e.reqDto||"-"}</td><td>${e.resDto||"-"}</td><td>${e.desc||""}</td></tr>`).join("");
  const tpRows=SYSTEM.events.filter(e=>!q||e.topic.toLowerCase().includes(q))
    .map(e=>`<tr><td><code>${e.topic}</code></td><td>${e.producer}</td><td>${e.consumers.join(", ")}</td><td>${(e.schemaFields||[]).map(f=>f.name).join(", ")}</td><td>${e.partitions}</td></tr>`).join("");
  const coRows=SYSTEM.connections.filter(c=>!q||(c.name+c.addr).toLowerCase().includes(q))
    .map(c=>`<tr><td>${c.name}</td><td><code>${c.addr}</code></td><td>${c.envVars.map(v=>`<code>${v}</code>`).join(" ")}</td><td>${c.protocol}</td></tr>`).join("");
  document.getElementById("ref-region").innerHTML=`
    <div style="display:flex;gap:8px;align-items:center"><h3 style="margin:0">📖 종합 레퍼런스</h3>
      <input id="ref-search" placeholder="검색…" value="${refFilter}" style="margin-left:auto;background:#0d1117;border:1px solid var(--line);color:var(--fg);padding:5px 8px;border-radius:6px">
    </div>
    <h4>REST 엔드포인트</h4><table class="ref"><thead><tr><th>서비스</th><th>method</th><th>path</th><th>요청</th><th>응답</th><th>설명</th></tr></thead><tbody>${epRows||'<tr><td colspan=6 class=muted>없음</td></tr>'}</tbody></table>
    <h4>Kafka 토픽</h4><table class="ref"><thead><tr><th>토픽</th><th>producer</th><th>consumers</th><th>Avro 필드</th><th>part.</th></tr></thead><tbody>${tpRows}</tbody></table>
    <h4>연결 디렉터리</h4><table class="ref"><thead><tr><th>대상</th><th>주소</th><th>주입 env</th><th>프로토콜</th></tr></thead><tbody>${coRows}</tbody></table>`;
  const inp=document.getElementById("ref-search");
  inp.oninput=e=>{ refFilter=e.target.value; renderReference(); document.getElementById("ref-search").focus(); };
}
function filterReference(id){ refFilter=id; renderReference(); document.getElementById("ref-region").scrollIntoView({behavior:"smooth"}); }
```

`<style>`에 추가: `table.ref{width:100%;border-collapse:collapse;font-size:12px;margin:6px 0} table.ref th,table.ref td{border:1px solid var(--line);padding:4px 6px;text-align:left} table.ref th{color:var(--muted)}`

init에 `renderReference()` 추가.

- [ ] **Step 2: 브라우저 검증** — 하단 레퍼런스에 엔드포인트/토픽/연결 표가 보이고, 검색창에 "kafka"·"platform" 입력 시 행이 필터됨. 맵 노드 패널의 "레퍼런스에서 보기 →" 클릭 시 해당 서비스로 필터+스크롤.

- [ ] **Step 3: 커밋**

```bash
git add docs/local-k8s-guide.html
git commit -m "feat(guide): 종합 레퍼런스 표 + 검색 + 맵 연동"
```

### Task 10: 푸터 + 범례 + 최종 검증/정리

**Files:**
- Modify: `docs/local-k8s-guide.html`

- [ ] **Step 1: 푸터·범례 추가**

```js
function renderFooter(){ document.getElementById("footer").innerHTML=
  `범례: <span style="color:var(--rest)">— REST</span> · <span style="color:var(--kafka)">-- Kafka</span> · <span style="color:var(--store)">— Store</span> &nbsp;|&nbsp; synapse <code>local-k8s</code> 기준 스냅샷 · 생성 2026-06-03 · 아키텍처 변경 시 <code>SYSTEM</code> 갱신`; }
```

init에 `renderFooter()` 추가. init 최종형:
```js
function init(){ runSelfTests(); renderLayerToggles(); renderScenarioPicker(); renderMap(); renderFlowRegion(); renderReference(); renderFooter(); }
window.addEventListener('DOMContentLoaded', init);
```

- [ ] **Step 2: 최종 브라우저 검증(성공 기준 대조)** — 파일을 새로 연다.
  Expected:
  1. 맵에서 서비스 경계·연결이 한눈에 보임(레이어 토글로 정리 가능)
  2. "▶ 노트→카드 생성" 재생 시 입자가 knowledge→kafka→learning-ai→knowledge→kafka→learning-card 흐름 + 단계 설명
  3. 레퍼런스 검색으로 임의 엔드포인트/토픽/주소 검색 가능
  4. 콘솔 `[SELFTEST PASS]`, 에러 없음, 인터넷 차단 상태에서도 정상(외부 요청 0)

- [ ] **Step 3: 네트워크 독립성 확인**

Run:
```bash
grep -niE 'https?://(cdn|unpkg|jsdelivr|fonts|ajax)|src=["'\'']http|@import url' docs/local-k8s-guide.html || echo "외부 의존성 없음 OK"
```
Expected: `외부 의존성 없음 OK`.

- [ ] **Step 4: 커밋**

```bash
git add docs/local-k8s-guide.html
git commit -m "feat(guide): 푸터/범례 + 최종 검증"
```

---

## Self-Review (작성자 체크 결과)

- **Spec 커버리지**: 6.1 맵→Task5/6, 6.2 패널→Task7, 6.3 애니메이션→Task8, 6.4 레퍼런스→Task9, SYSTEM 데이터 모델→Task2, 콘텐츠 전수 수집(5절)→Task3/4, 테마/위치/푸터→Task1/10. 전 섹션 매핑됨.
- **Placeholder**: Task5에서 `openEdge/highlight/openPanel`을 빈 스텁으로 두고 Task6/7에서 구현 — 의존 순서를 명시했고 각 구현은 해당 태스크에 완전한 코드로 존재(전방 선언 패턴, placeholder 아님).
- **타입/명칭 일관성**: `activeLayers`(rest/kafka/store), `POS`, `edgeList()`, `openPanel(id)`, `openEdge(ed)`, `playScenario(name)`, `renderReference()`, `filterReference(id)`, `refFilter` — 태스크 간 동일 시그니처 유지 확인.
- **콘텐츠 수집 리스크**: learning-ai(Python) 라우트는 데코레이터 패턴이 달라 Task4 Step1에 별도 grep 명시. Avro 스키마 부재 시 추정+주석 규칙(Task3) 명시.
