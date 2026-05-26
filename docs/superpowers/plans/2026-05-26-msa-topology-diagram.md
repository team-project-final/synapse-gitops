# 인터랙티브 MSA 구성도 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `local-msa-setup.html` §0의 ASCII 다이어그램을, 노드 클릭 시 포트·헬스·의존성·확인 명령이 뜨는 인터랙티브 SVG 구성도(계층형 흐름 + 상세 패널)로 교체한다.

**Architecture:** 단일 HTML 파일 내 인라인 CSS + 인라인 SVG(빈 `<g>` 골격) + 데이터 주도 JS. `NODES`/`EDGES` 정적 배열을 JS가 SVG로 렌더하고, 노드 선택 시 패널 갱신 + 연결 엣지 강조. 외부 의존성·빌드 없음.

**Tech Stack:** 순수 HTML5 + CSS + Vanilla JS + 인라인 SVG. 검증은 브라우저(playwright, `http://localhost:51300/local-msa-setup.html` — 정적 서버).

**스펙:** `docs/superpowers/specs/2026-05-26-msa-topology-diagram-design.md`

---

## 검증된 노드 데이터 (모든 태스크 공유 — 이 값만 사용)

> 직전 세션에서 `synapse-gitops/docker-compose.yml`·`synapse-shared/docker-compose.yml`로 검증한 값. 추측 금지.

| 노드 | 그룹 | 포트 ①풀컨테이너 / ②하이브리드 | 확인 명령 | 의존 |
|---|---|---|---|---|
| Client | entry | - / - | - | Gateway, platform-svc |
| Gateway | entry | 없음 / :8080 | `curl http://localhost:8080/actuator/health` | 앱 5, Redis (경로②에만 존재) |
| platform-svc | app | :8080 / stub :8081 | `curl http://localhost:8080/actuator/health` | PostgreSQL, Redis, Kafka |
| engagement-svc | app | :8082 / stub :8082 | `curl http://localhost:8082/actuator/health` | PostgreSQL, Redis, Kafka, learning-card |
| knowledge-svc | app | :8083 / stub :8083 | `curl http://localhost:8083/actuator/health` | PostgreSQL, Redis, Kafka, 검색엔진 |
| learning-card | app | :8084 / stub :8084 | `curl http://localhost:8084/actuator/health` | PostgreSQL, Redis, Kafka |
| learning-ai | app | :8000 / :8090 | `curl http://localhost:8000/health` (②: :8090) | Kafka, 검색엔진 |
| Kafka (+Zookeeper) | msg | :9092 / :9092 | `docker exec -it synapse-kafka kafka-topics --list --bootstrap-server localhost:9092` | Zookeeper (kafka-init 토픽 5개) |
| Schema Registry | msg | :8085 / :8086 | `curl http://localhost:8085/subjects` (②: :8086) | Kafka |
| PostgreSQL | data | :5432 / :5432 | `docker compose ps` | — |
| Redis | data | :6379 / :6379 | `docker exec -it synapse-redis redis-cli ping` | — |
| 검색엔진 | data | :9200 / :9200 | `curl http://localhost:9200/_cluster/health` | — (① ES 8.13 / ② OpenSearch 2.11) |

---

## 파일 구조

| 파일 | 작업 | 책임 |
|---|---|---|
| `synapse-gitops/docs/local-msa-setup.html` | Modify | §0 ASCII → 인터랙티브 SVG 구성도 (CSS·markup·JS 인라인) |

단일 파일. Task 1(CSS) → Task 2(markup) → Task 3(JS) → Task 4(QA). 각 태스크 후 커밋.

> **검증용 정적 서버 (각 QA 단계 공통):** 이미 떠 있지 않다면
> `cd /c/workspace/team-project-final/synapse-gitops/docs && python -m http.server 51300 --bind 127.0.0.1` (백그라운드).
> playwright는 `file://`를 차단하므로 반드시 `http://localhost:51300/local-msa-setup.html`로 접속.

---

## Task 1: 구성도 CSS 추가

**Files:**
- Modify: `synapse-gitops/docs/local-msa-setup.html` (`<style>` 블록 끝, `</style>` 직전)

- [ ] **Step 1: CSS 삽입**

기존 `<style>`의 마지막 규칙(`.sr-only`가 없으므로 `@media(max-width:880px){...}` 블록) 뒤, `</style>` 바로 앞에 아래를 추가한다.

```css
  /* ── Topology diagram ── */
  .topo{display:flex;gap:16px;align-items:flex-start;margin:14px 0}
  .topo-svg{flex:1;min-width:0;border:1px solid var(--line);border-radius:8px;background:var(--panel)}
  .topo-svg svg{width:100%;height:auto;display:block}
  .topo-panel{width:240px;flex:none;border:1px solid var(--line);border-radius:8px;background:#f8fafc;padding:14px;font-size:13.5px}
  .topo-panel h4{margin:0 0 6px;font-size:15px}
  .topo-panel .role{color:var(--muted);margin:0 0 10px}
  .topo-panel dl{margin:0;display:grid;grid-template-columns:auto 1fr;gap:4px 8px}
  .topo-panel dt{color:var(--muted);font-size:12px} .topo-panel dd{margin:0}
  .topo-panel .cmd{background:var(--code-bg);color:var(--code-ink);border-radius:5px;padding:6px 8px;
    font-family:Consolas,monospace;font-size:12px;margin-top:8px;white-space:pre-wrap;word-break:break-all}
  .topo-hint{color:var(--muted);font-style:italic;margin:0}
  .topo .edge{stroke:#cbd5e1;stroke-width:1.5;opacity:.22;fill:none;transition:opacity .15s,stroke .15s}
  .topo .edge.hl{opacity:1;stroke:var(--accent);stroke-width:2}
  .topo .node{cursor:pointer}
  .topo .node text{font-size:11px;font-family:sans-serif;pointer-events:none}
  .topo .node .port{font-size:9px;fill:var(--muted)}
  .topo .node.sel rect, .topo .node:focus rect{stroke:var(--accent);stroke-width:2.5}
  .topo .node:focus{outline:none}
  .topo .g-entry rect{fill:#dbeafe;stroke:#2563eb}
  .topo .g-app rect{fill:#dcfce7;stroke:#16a34a}
  .topo .g-msg rect{fill:#fef9c3;stroke:#ca8a04}
  .topo .g-data rect{fill:#fee2e2;stroke:#dc2626}
  .sr-only{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);border:0}
  @media(max-width:880px){ .topo{flex-direction:column} .topo-panel{width:100%} }
```

- [ ] **Step 2: 렌더 확인**

정적 서버 기동 후 `http://localhost:51300/local-msa-setup.html` 접속.
Expected: 기존 레이아웃 깨짐 없음, 콘솔 에러 0(favicon 제외). (아직 구성도 마크업 없음 — 시각 변화 없음)

- [ ] **Step 3: 커밋**

```bash
cd /c/workspace/team-project-final/synapse-gitops
git add docs/local-msa-setup.html
git commit -m "feat(guide): 구성도 CSS (노드/엣지/상세 패널)"
```

---

## Task 2: ASCII 블록을 SVG 골격 마크업으로 교체

**Files:**
- Modify: `synapse-gitops/docs/local-msa-setup.html` (§0 내 `<h3>전체 구성도</h3>` + `<pre class="ascii">...</pre>`)

- [ ] **Step 1: ASCII 교체**

§0의 다음 블록 전체(여는 `<h3>전체 구성도</h3>`부터 `</pre>`까지)를 찾는다:

```html
      <h3>전체 구성도</h3>
      <pre class="ascii">
                              ┌─────────────────────────────┐
   브라우저 / 클라이언트  ──▶ │  (하이브리드 시) Gateway :8080 │
   ... (중략) ...
   └────────────────────────────────────────────────────────────────────────────────┘</pre>
```

이를 아래로 교체한다:

```html
      <h3>전체 구성도</h3>
      <p class="topo-hint" style="margin-bottom:8px">아래 구성도의 노드를 클릭하면 포트·헬스·확인 명령이 오른쪽(모바일은 아래)에 표시됩니다.</p>
      <div class="topo">
        <div class="topo-svg">
          <svg id="topoSvg" viewBox="0 0 640 360" role="img" aria-labelledby="topoTitle topoDesc">
            <title id="topoTitle">Synapse MSA 로컬 구성도</title>
            <desc id="topoDesc">Client에서 Gateway를 거쳐 platform·engagement·knowledge·learning-card·learning-ai 5개 서비스로 이어지고, 서비스들은 Kafka·Schema Registry·PostgreSQL·Redis·검색엔진에 연결됩니다.</desc>
            <g id="topoEdges"></g>
            <g id="topoNodes"></g>
          </svg>
        </div>
        <aside class="topo-panel" id="topoPanel" aria-live="polite">
          <p class="topo-hint">노드를 클릭하면 포트·헬스·확인 명령이 표시됩니다.</p>
        </aside>
      </div>
      <p class="sr-only">구성 요약: Client → Gateway(경로② 전용) → 서비스 5개(platform 8080, engagement 8082, knowledge 8083, learning-card 8084, learning-ai 8000/8090) → Kafka 9092, Schema Registry 8085/8086, PostgreSQL 5432, Redis 6379, 검색엔진 9200.</p>
```

(교체 후 바로 뒤의 `<p>서비스 간 비동기 통신은 ...</p>` 문단은 그대로 둔다.)

- [ ] **Step 2: 렌더 확인**

페이지 재접속.
Expected: §0에 빈 SVG 박스 + "노드를 클릭하면..." 안내 패널이 보인다. ASCII는 사라짐. 콘솔 에러 0.

```js
// playwright browser_evaluate
() => ({ hasSvg: !!document.getElementById('topoSvg'),
         hasPanel: !!document.getElementById('topoPanel'),
         asciiGone: !document.querySelector('#overview pre.ascii') })
// Expected: { hasSvg:true, hasPanel:true, asciiGone:true }
```

- [ ] **Step 3: 커밋**

```bash
git add docs/local-msa-setup.html
git commit -m "feat(guide): §0 ASCII → 인터랙티브 SVG 골격 교체"
```

---

## Task 3: 노드/엣지 데이터 + 렌더 + 상호작용 JS

**Files:**
- Modify: `synapse-gitops/docs/local-msa-setup.html` (기존 `</script>` 바로 앞에 새 `<script>` 추가)

- [ ] **Step 1: 토폴로지 스크립트 추가**

기존 인라인 `<script>...</script>`(IIFE) **뒤, `</body>` 앞**에 아래 새 `<script>`를 추가한다.

```html
<script>
(function(){
  var NS='http://www.w3.org/2000/svg';
  var NODES=[
    {id:'client',g:'entry',label:'Client',x:60,y:14,w:130,h:40,role:'브라우저/앱 진입점',tech:'-',p1:'-',p2:'-',check:'-',deps:['Gateway','platform-svc'],note:'경로①은 앱 포트 직접 호출, 경로②는 Gateway 경유'},
    {id:'gateway',g:'entry',label:'Gateway',x:410,y:14,w:170,h:40,role:'외부 트래픽 라우팅',tech:'Spring Cloud Gateway / JDK 21',p1:'없음',p2:':8080',check:'curl http://localhost:8080/actuator/health',deps:['platform-svc','engagement-svc','knowledge-svc','learning-card','Redis'],note:'경로②(synapse-shared compose)에만 존재'},
    {id:'platform',g:'app',label:'platform-svc',x:6,y:104,w:116,h:40,role:'인증·결제·알림',tech:'Spring Boot / JDK 21',p1:':8080',p2:'stub :8081',check:'curl http://localhost:8080/actuator/health',deps:['PostgreSQL','Redis','Kafka']},
    {id:'engagement',g:'app',label:'engagement-svc',x:132,y:104,w:116,h:40,role:'참여·활동',tech:'Spring Boot / JDK 21',p1:':8082',p2:'stub :8082',check:'curl http://localhost:8082/actuator/health',deps:['PostgreSQL','Redis','Kafka','learning-card']},
    {id:'knowledge',g:'app',label:'knowledge-svc',x:258,y:104,w:116,h:40,role:'노트·검색',tech:'Spring Boot / JDK 21',p1:':8083',p2:'stub :8083',check:'curl http://localhost:8083/actuator/health',deps:['PostgreSQL','Redis','Kafka','검색엔진']},
    {id:'learningcard',g:'app',label:'learning-card',x:384,y:104,w:116,h:40,role:'학습 카드',tech:'Spring Boot / JDK 21',p1:':8084',p2:'stub :8084',check:'curl http://localhost:8084/actuator/health',deps:['PostgreSQL','Redis','Kafka']},
    {id:'learningai',g:'app',label:'learning-ai',x:510,y:104,w:116,h:40,role:'AI 카드 생성',tech:'FastAPI / Python 3.12',p1:':8000',p2:':8090',check:'curl http://localhost:8000/health   (②: :8090)',deps:['Kafka','검색엔진']},
    {id:'kafka',g:'msg',label:'Kafka',x:120,y:210,w:180,h:40,role:'이벤트 메시징 (+Zookeeper)',tech:'Confluent 7.6.1(①)/7.7.0(②)',p1:':9092',p2:':9092',check:'docker exec -it synapse-kafka kafka-topics --list --bootstrap-server localhost:9092',deps:['Zookeeper'],note:'kafka-init가 토픽 5개 자동 생성'},
    {id:'schema',g:'msg',label:'Schema Registry',x:350,y:210,w:170,h:40,role:'Avro 스키마 관리',tech:'Confluent Schema Registry',p1:':8085',p2:':8086',check:'curl http://localhost:8085/subjects   (②: :8086)',deps:['Kafka']},
    {id:'postgres',g:'data',label:'PostgreSQL',x:20,y:300,w:150,h:40,role:'관계형 DB',tech:'① pgvector-pg16 / ② postgres:16-alpine',p1:':5432',p2:':5432',check:'docker compose ps',deps:[]},
    {id:'redis',g:'data',label:'Redis',x:200,y:300,w:140,h:40,role:'세션·캐시',tech:'redis:7',p1:':6379',p2:':6379',check:'docker exec -it synapse-redis redis-cli ping',deps:[]},
    {id:'search',g:'data',label:'검색엔진',x:360,y:300,w:180,h:40,role:'전문 검색',tech:'① Elasticsearch 8.13 / ② OpenSearch 2.11',p1:':9200',p2:':9200',check:'curl http://localhost:9200/_cluster/health',deps:[]}
  ];
  var EDGES=[
    ['client','gateway'],
    ['gateway','platform'],['gateway','engagement'],['gateway','knowledge'],['gateway','learningcard'],['gateway','redis'],
    ['platform','kafka'],['engagement','kafka'],['knowledge','kafka'],['learningcard','kafka'],['learningai','kafka'],['schema','kafka'],
    ['platform','postgres'],['engagement','postgres'],['knowledge','postgres'],['learningcard','postgres'],
    ['platform','redis'],['engagement','redis'],['learningcard','redis'],
    ['knowledge','search'],['learningai','search']
  ];
  var edgesG=document.getElementById('topoEdges'), nodesG=document.getElementById('topoNodes'), panel=document.getElementById('topoPanel');
  if(!edgesG||!nodesG||!panel) return;
  var byId={}; NODES.forEach(function(n){byId[n.id]=n;});
  function cx(n){return n.x+n.w/2;} function cy(n){return n.y+n.h/2;}
  function esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}

  EDGES.forEach(function(e){
    var a=byId[e[0]], b=byId[e[1]];
    var ln=document.createElementNS(NS,'line');
    ln.setAttribute('x1',cx(a));ln.setAttribute('y1',cy(a));ln.setAttribute('x2',cx(b));ln.setAttribute('y2',cy(b));
    ln.setAttribute('class','edge'); ln.dataset.a=e[0]; ln.dataset.b=e[1];
    edgesG.appendChild(ln);
  });

  NODES.forEach(function(n){
    var hasPort = n.p1 && n.p1!=='-';
    var g=document.createElementNS(NS,'g');
    g.setAttribute('class','node g-'+n.g); g.setAttribute('tabindex','0'); g.setAttribute('role','button');
    g.setAttribute('aria-label', n.label + (hasPort? (' 포트 '+(n.p1===n.p2?n.p1:n.p1+' 또는 '+n.p2)) : ''));
    g.dataset.id=n.id;
    var r=document.createElementNS(NS,'rect');
    r.setAttribute('x',n.x);r.setAttribute('y',n.y);r.setAttribute('width',n.w);r.setAttribute('height',n.h);r.setAttribute('rx',6);
    g.appendChild(r);
    var t=document.createElementNS(NS,'text');
    t.setAttribute('x',cx(n));t.setAttribute('y', n.y + (hasPort?17:24));t.setAttribute('text-anchor','middle');
    t.textContent=n.label; g.appendChild(t);
    if(hasPort){
      var pt=document.createElementNS(NS,'text');
      pt.setAttribute('x',cx(n));pt.setAttribute('y',n.y+32);pt.setAttribute('text-anchor','middle');pt.setAttribute('class','port');
      pt.textContent=(n.p1===n.p2)?n.p1:(n.p1+' / '+n.p2);
      g.appendChild(pt);
    }
    g.addEventListener('click',function(){select(n.id);});
    g.addEventListener('keydown',function(ev){ if(ev.key==='Enter'||ev.key===' '){ ev.preventDefault(); select(n.id); }});
    nodesG.appendChild(g);
  });

  function select(id){
    var n=byId[id];
    nodesG.querySelectorAll('.node').forEach(function(g){ g.classList.toggle('sel', g.dataset.id===id); });
    edgesG.querySelectorAll('.edge').forEach(function(ln){ ln.classList.toggle('hl', ln.dataset.a===id||ln.dataset.b===id); });
    var portRow = (n.p1===n.p2) ? esc(n.p1) : ('① '+esc(n.p1)+'  ·  ② '+esc(n.p2));
    var deps = n.deps.length ? n.deps.map(esc).join(', ') : '—';
    var html='<h4>'+esc(n.label)+'</h4><p class="role">'+esc(n.role)+'</p>'
      +'<dl><dt>기술</dt><dd>'+esc(n.tech)+'</dd>'
      +'<dt>포트</dt><dd>'+portRow+'</dd>'
      +'<dt>의존</dt><dd>'+deps+'</dd></dl>';
    if(n.note) html+='<p class="role" style="margin-top:8px">ℹ '+esc(n.note)+'</p>';
    if(n.check && n.check!=='-') html+='<div class="cmd">'+esc(n.check)+'</div>';
    panel.innerHTML=html;
  }
})();
</script>
```

- [ ] **Step 2: 브라우저 동작 검증**

페이지 재접속 후 playwright `browser_evaluate`:

```js
() => {
  var nodes=document.querySelectorAll('#topoNodes .node');
  var edges=document.querySelectorAll('#topoEdges .edge');
  // learning-ai 선택 → 패널/하이라이트 확인
  var la=document.querySelector('#topoNodes .node[data-id="learningai"]');
  la.dispatchEvent(new MouseEvent('click',{bubbles:true}));
  var panel=document.getElementById('topoPanel');
  var hlEdges=document.querySelectorAll('#topoEdges .edge.hl').length;
  return {
    nodeCount: nodes.length, edgeCount: edges.length,
    panelHasLearningAi: panel.textContent.includes('learning-ai'),
    panelHasPorts: panel.textContent.includes('8000') && panel.textContent.includes('8090'),
    panelHasCheck: panel.textContent.includes('/health'),
    selectedHighlighted: document.querySelector('#topoNodes .node.sel').dataset.id==='learningai',
    connectedEdgesHl: hlEdges
  };
}
// Expected: nodeCount 12, edgeCount 21, panelHasLearningAi true, panelHasPorts true,
//           panelHasCheck true, selectedHighlighted true, connectedEdgesHl 2 (kafka, search)
```

- [ ] **Step 3: 키보드 접근성 확인**

```js
() => {
  var gw=document.querySelector('#topoNodes .node[data-id="gateway"]');
  gw.focus();
  gw.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true}));
  var p=document.getElementById('topoPanel').textContent;
  return { focusable: gw.getAttribute('tabindex')==='0', role: gw.getAttribute('role'),
           gwSelectedByKeyboard: p.includes('Gateway') && p.includes('8080') && p.includes('경로②') };
}
// Expected: focusable true, role "button", gwSelectedByKeyboard true
```

- [ ] **Step 4: 커밋**

```bash
git add docs/local-msa-setup.html
git commit -m "feat(guide): 구성도 노드/엣지 데이터 + 상호작용 JS"
```

---

## Task 4: 최종 QA + 정확성 대조 + 반응형

**Files:**
- Modify: `synapse-gitops/docs/local-msa-setup.html` (필요 시 수정만)

- [ ] **Step 1: 전체 노드 순회 검증**

```js
() => {
  var ids=['client','gateway','platform','engagement','knowledge','learningcard','learningai','kafka','schema','postgres','redis','search'];
  var bad=[];
  ids.forEach(function(id){
    var el=document.querySelector('#topoNodes .node[data-id="'+id+'"]');
    if(!el){ bad.push(id+':missing'); return; }
    el.dispatchEvent(new MouseEvent('click',{bubbles:true}));
    var t=document.getElementById('topoPanel').textContent;
    if(t.trim().length<10) bad.push(id+':emptyPanel');
  });
  return { allOk: bad.length===0, bad };
}
// Expected: { allOk:true, bad:[] }
```

- [ ] **Step 2: 콘솔 에러 확인** — playwright `browser_console_messages` level error.
Expected: favicon 404 외 0건.

- [ ] **Step 3: 반응형 확인** — `browser_resize` 800×900 후:

```js
() => getComputedStyle(document.querySelector('.topo')).flexDirection
// Expected: "column"  (패널이 다이어그램 아래로)
```
확인 후 1280×900으로 복귀.

- [ ] **Step 4: 정확성 최종 대조**

`synapse-gitops/docker-compose.yml`·`synapse-shared/docker-compose.yml`을 열어 구성도 포트(8080/8082/8083/8084/8000/8090/8085/8086/9092/5432/6379/9200)·확인 명령이 일치하는지 1:1 확인. 불일치 시 `NODES` 데이터 수정 후 Step 1~3 재검증.

- [ ] **Step 5: 전체 페이지 스크린샷(기록용, 비커밋)**

playwright `browser_take_screenshot` fullPage → 확인용. 커밋하지 않으며 QA 후 삭제(`rm -f`).

- [ ] **Step 6: 최종 커밋(코드 수정이 있었던 경우만)**

```bash
git add docs/local-msa-setup.html
git commit -m "docs(guide): 구성도 QA — 포트 정확성/반응형 검증"
```
(Step 4에서 수정이 없었다면 Task 3 커밋으로 충분 — 이 단계 생략.)

---

## Self-Review (작성자 체크리스트 결과)

**1. 스펙 커버리지:** §3 배치(ASCII 완전 교체+sr-only)→Task 2. §4 레이아웃 A(계층형+패널)→Task 1 CSS + Task 2 markup. §5 노드 12/엣지→Task 3 `NODES`(12)/`EDGES`(21). §6 상세 데이터(포트①②·헬스·확인명령·의존)→Task 3 `select()` 패널. §7 상호작용/접근성(클릭·키보드·aria-live·하이라이트)→Task 3 Step 1~3. §8 검증→Task 4. §9 범위밖(라이브/새페이지)→미포함.

**2. 플레이스홀더 스캔:** 모든 노드 값은 검증 표에서 가져온 실제 값. 코드 블록 완전(CSS·markup·JS 전체 제시). TBD 없음.

**3. 타입/이름 일관성:** DOM id(`topoSvg`/`topoEdges`/`topoNodes`/`topoPanel`)가 Task 2 markup ↔ Task 3 JS에서 일치. CSS 클래스(`.topo`,`.node`,`.edge`,`.g-*`,`.sel`,`.hl`,`.topo-panel`,`.cmd`,`.sr-only`)가 Task 1 ↔ Task 3에서 일치. 노드 id 12개가 `NODES`·`EDGES`·Task 3/4 검증 스크립트에서 동일. 엣지 수 21 = `EDGES` 배열 길이(1+5+6+4+3+2=21)와 일치.
