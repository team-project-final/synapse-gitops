# AWS 배포 가이드 단일 HTML — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** AWS 입문 백엔드 개발자가 Synapse의 AWS 배포를 기본 세팅→구조→동작→환경 승급까지 이해하도록, 발표(기본)/스크롤 레퍼런스 토글이 되는 단일 자기완결 HTML(`docs/aws-deploy-guide.html`)을 만든다.

**Architecture:** 전역 `SYSTEM` 데이터 객체 1개가 단일 출처. 순수 데이터(envs/topology/chapters/glossary)와 렌더러(topology SVG, chapter, mode, detail, search)를 분리한다. 모든 렌더러는 `SYSTEM`을 읽기만 하며 서로의 내부를 모른다. 폰트(base64)와 `:root` 디자인 토큰은 `docs/local-k8s-guide.html`에서 그대로 복사 재사용한다.

**Tech Stack:** 순수 HTML/CSS/Vanilla JS (프레임워크·번들러·CDN 없음). 인라인 SVG. `DESIGN.md` 토큰 준수(다크 전용, Geist/Geist Mono, 색 의미 잠금, 4px 간격).

**Spec:** `docs/superpowers/specs/2026-06-07-aws-deploy-guide-design.md`

**Branch:** `docs/aws-deploy-guide` (이미 생성됨, 스펙 커밋 존재). 모든 작업은 이 브랜치에서. push는 사용자 승인 후.

---

## 확정 데이터 값 (실제 repo 근거 — 데이터 모델에 그대로 사용)

| 구성요소 | dev 값 | 근거 |
|---|---|---|
| EKS 노드 | `t3.medium` × desired 4 / min 4 / max 5 | `infra/aws/dev/{eks.tf,variables.tf}` |
| RDS | PostgreSQL `16.9`, `db.t3.medium`, 20GB(max 50), Multi-AZ 꺼짐 | `rds.tf` |
| MSK | Kafka `3.6.0`, broker 3, `kafka.t3.small`, TLS | `msk.tf` |
| ElastiCache | Redis `7.1`, `cache.t3.micro`, 1 node, in-transit 암호화, failover 꺼짐 | `redis.tf` |
| 검색 | Elasticsearch StatefulSet (EKS 내부, AWS 관리형 아님) | `apps/elasticsearch/base/statefulset.yaml` |
| 배포 매트릭스 | 7 대상(platform·engagement·knowledge·learning-card·learning-ai·gateway·frontend) × 3 env | `argocd/applicationset.yaml` |
| Sync 정책 | dev=automated(prune+selfHeal), staging=automated(prune+selfHeal), **prod=수동**(automated 없음, gitops-admin 승인 게이트 FR-GO-402) | `argocd/applicationset{,-staging,-prod}.yaml` |
| prod 하드닝 | NetworkPolicy 5 오버레이 + HPA 10 오버레이 + non-root + Multi-AZ | `apps/*/overlays/prod/netpol.yaml`, HPA 참조 |
| 진입/라우팅 | ALB → gateway 단일 진입: `/api/**`→백엔드(JWT 인증), catch-all→frontend(SPA, 공개) | gateway `RoutesConfig.java`·`SecurityConfig.java` (#5/#6) |
| frontend | Flutter web → Docker(nginx :80) → ECR → gitops 태그 bump | `synapse-frontend` #21/#22 |

서비스 식별색(`DESIGN.md`): platform `#58a6ff` · engagement `#3fb950` · knowledge `#f778ba` · learning-ai `#e3b341` · learning-card `#ff7b72`. 기능색: rest `#58a6ff` · kafka `#d29922` · store `#3fb950` · accent/route `#bc8cff` · danger `#f85149`.

---

## File Structure

- **Create:** `docs/aws-deploy-guide.html` — 단일 파일. 내부 논리 구획(주석 마커로 구분):
  - `<style>`: `:root` 토큰 + `@font-face`(base64) + 레이아웃/컴포넌트 CSS
  - `<body>`: topbar(모드 토글·env 토글) · `#stage`(발표/레퍼런스 컨테이너) · `#detail`(상세 패널)
  - `<script>`: `SYSTEM`(데이터) → `renderTopology()` → `renderChapters()` → `ModeController` → `DetailPanel` → `Search` → `init()`
- **Reference (읽기 전용, 복사 출처):** `docs/local-k8s-guide.html` (폰트 base64 + `:root`), `docs/aws-infra-provisioning-workflow-guide.md` (문구 소스)

단일 파일이지만 스크립트 내부는 위 순서의 함수 단위로 분리해 각 책임을 격리한다.

---

## Verification 방식 (이 플랜 공통)

HTML이므로 pytest 대신 **브라우저 관찰**로 검증한다. 각 검증 단계는:
- **열기:** `docs/aws-deploy-guide.html`을 Chrome에서 `file://`로 더블클릭(또는 gstack browse). 
- **콘솔:** DevTools Console 에러 0 확인.
- 단계별 "Expected"에 명시된 가시 동작을 눈으로 확인.

> 자동 점검 보조: 각 커밋 후 `node -e "const s=require('fs').readFileSync('docs/aws-deploy-guide.html','utf8'); if(!s.includes('SYSTEM')) process.exit(1)"` 류의 sanity 체크는 선택. 핵심 검증은 브라우저.

---

## Task 1: 스캐폴드 + 디자인 토큰 + 폰트 임베드

**Files:**
- Create: `docs/aws-deploy-guide.html`

- [ ] **Step 1: 기존 가이드에서 폰트/토큰 블록 복사**

`docs/local-k8s-guide.html`을 열어 두 블록을 그대로 복사한다:
1. `@font-face { font-family:"Geist"... src:url(data:font/woff2;base64,...) }` 6개 블록 전체.
2. `:root { --bg:#0e1116; --panel:#161b22; ... --accent:#bc8cff; ... }` 변수 블록 전체.

복사 출처를 찾으려면 해당 파일에서 `@font-face` 와 `:root {` 를 검색한다. **base64 문자열을 직접 타이핑/재생성하지 말 것 — 복사만.**

- [ ] **Step 2: HTML 뼈대 작성**

`docs/aws-deploy-guide.html` 생성:

```html
<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Synapse AWS 배포 가이드</title>
<style>
/* ===== FONTS (local-k8s-guide.html에서 복사) ===== */
/* @font-face 6블록 붙여넣기 */

/* ===== TOKENS (local-k8s-guide.html에서 복사) ===== */
:root { /* --bg, --panel, --surface-2, --line, --fg, --muted, --dim,
           --rest, --kafka, --store, --accent, --danger,
           --xs:4px; --sm:6px; --md:8px; --lg:12px; --xl:16px;
           --mono / --sans 스택 */ }

/* ===== BASE ===== */
* { box-sizing:border-box; }
html,body { margin:0; height:100%; background:var(--bg); color:var(--fg);
  font-family:var(--sans); font-size:13px; line-height:1.5; }
.mono { font-family:var(--mono); }
#topbar { display:flex; align-items:center; gap:var(--lg);
  height:44px; padding:0 var(--lg); border-bottom:1px solid var(--line);
  font-family:var(--mono); font-weight:600; font-size:16px; letter-spacing:-0.01em; }
#topbar .spacer { flex:1; }
button { font-family:var(--mono); font-size:12px; color:var(--fg);
  background:var(--surface-2); border:1px solid var(--line); border-radius:6px;
  padding:4px 10px; cursor:pointer; transition:150ms ease; }
button[aria-pressed="true"]{ border-color:var(--accent); color:var(--accent); }
</style>
</head>
<body>
<header id="topbar">
  <span>SYNAPSE · AWS 배포 가이드</span>
  <span class="spacer"></span>
  <div id="env-toggle" role="group" aria-label="환경"></div>
  <button id="mode-btn" type="button">레퍼런스 모드</button>
</header>
<main id="stage"></main>
<aside id="detail" hidden></aside>
<script>
/* SYSTEM + 렌더러는 다음 태스크에서 채운다 */
</script>
</body>
</html>
```

- [ ] **Step 3: 브라우저 검증**

열기: `docs/aws-deploy-guide.html` (Chrome file://).
Expected: 다크 배경(#0e1116), topbar에 "SYNAPSE · AWS 배포 가이드"가 **Geist Mono**로 렌더(시스템 기본 폰트로 폴백되지 않음 — 글자모양 확인). Console 에러 0.

- [ ] **Step 4: Commit**

```bash
git add docs/aws-deploy-guide.html
git commit -m "feat(guide): 스캐폴드 + 디자인 토큰/폰트 임베드"
```

---

## Task 2: SYSTEM 데이터 — envs + glossary

**Files:**
- Modify: `docs/aws-deploy-guide.html` (`<script>` 내부)

- [ ] **Step 1: SYSTEM.envs + glossary 작성**

`<script>` 최상단에 추가 (값은 위 "확정 데이터 값" 표 그대로):

```js
const SYSTEM = {
  meta: { title:"Synapse AWS 배포 가이드", env:"dev" },
  envs: {
    dev:     { label:"dev",     eksNodes:4, mskBrokers:3, multiAZ:false, sync:"auto",
               hardening:["non-root"] },
    staging: { label:"staging", eksNodes:4, mskBrokers:3, multiAZ:false, sync:"auto",
               hardening:["non-root","NetworkPolicy","HPA"] },
    prod:    { label:"prod",    eksNodes:4, mskBrokers:3, multiAZ:true,  sync:"manual",
               hardening:["non-root","NetworkPolicy","HPA","Multi-AZ"] },
  },
  glossary: [
    { term:"VPC", oneLiner:"AWS 안의 우리 전용 사설 네트워크 울타리.",
      whyWeUse:"모든 리소스를 같은 사설망에 두고 외부 노출을 ALB 한 곳으로만 제한." },
    { term:"서브넷", oneLiner:"VPC를 잘게 나눈 IP 구획(public/private).",
      whyWeUse:"DB·MSK·노드는 private, ALB만 public — 공격면 최소화." },
    { term:"보안그룹", oneLiner:"리소스 단위 방화벽(누가 어떤 포트로 접근).",
      whyWeUse:"RDS는 EKS 노드 SG에서만, 식으로 접근을 좁힘." },
    { term:"IAM / IRSA", oneLiner:"권한 정책. IRSA=파드에 IAM 역할을 매다는 방식.",
      whyWeUse:"키를 코드에 안 넣고 ServiceAccount로 ECR pull·시크릿 접근." },
    { term:"EKS", oneLiner:"AWS가 운영해주는 관리형 Kubernetes.",
      whyWeUse:"컨트롤플레인 운영을 AWS에 맡기고 노드에 서비스만 올림." },
    { term:"관리형 서비스", oneLiner:"RDS·MSK·ElastiCache처럼 AWS가 운영하는 미들웨어.",
      whyWeUse:"DB·Kafka·Redis 운영부담을 줄이고 앱에 집중." },
    { term:"ArgoCD / GitOps", oneLiner:"git의 상태를 클러스터에 자동 반영.",
      whyWeUse:"커밋이 곧 배포 — 수동 kubectl 없이 git이 단일 진실." },
  ],
  // topology / chapters는 다음 태스크
};
```

- [ ] **Step 2: 콘솔에서 무결성 확인**

열기 후 DevTools Console에서:
```js
SYSTEM.envs.prod.sync         // "manual"
SYSTEM.envs.dev.hardening     // ["non-root"]
SYSTEM.glossary.length        // 7
```
Expected: 위 주석값과 일치, 에러 0.

- [ ] **Step 3: Commit**

```bash
git add docs/aws-deploy-guide.html
git commit -m "feat(guide): SYSTEM envs + glossary 데이터"
```

---

## Task 3: SYSTEM 데이터 — topology (nodes + edges)

**Files:**
- Modify: `docs/aws-deploy-guide.html`

- [ ] **Step 1: SYSTEM.topology 작성**

`glossary` 뒤에 추가. `envs`는 노드가 보이는 환경 배열, `kind`로 시각 그룹, 좌표는 12열 그리드 기준 정수.

```js
SYSTEM.topology = {
  nodes: [
    { id:"internet", label:"인터넷", kind:"external", x:1, y:1,
      role:"사용자 브라우저", detail:"공용 인터넷에서 ALB로 진입." },
    { id:"alb", label:"ALB", kind:"edge", x:3, y:1, tfFile:"alb-controller-irsa.tf",
      role:"L7 로드밸런서", detail:"AWS Load Balancer Controller(IRSA)가 Ingress로 생성. TLS 종단(ACM).",
      verifyCmd:"kubectl get ingress -A" },
    { id:"gateway", label:"gateway", kind:"svc", color:"#bc8cff", x:5, y:1,
      role:"단일 진입 게이트웨이",
      detail:"/api/** → 백엔드(JWT 인증 필수), catch-all(non-/api) → frontend SPA(공개). RoutesConfig/SecurityConfig (#5/#6).",
      verifyCmd:"curl -k https://<alb>/api/actuator/health" },
    { id:"frontend", label:"frontend", kind:"svc", color:"#8b949e", x:5, y:3,
      role:"Flutter web SPA(nginx :80)",
      detail:"synapse-frontend에서 Docker화→ECR→gitops 배포(#21/#22). gateway catch-all이 프록시.",
      verifyCmd:"kubectl get deploy frontend" },
    { id:"platform", label:"platform-svc", kind:"svc", color:"#58a6ff", x:7, y:1,
      role:"인증/플랫폼", detail:"JWT 발급·플랫폼 API.", verifyCmd:"kubectl get deploy platform-svc" },
    { id:"engagement", label:"engagement-svc", kind:"svc", color:"#3fb950", x:7, y:2,
      role:"커뮤니티/참여", detail:"Kafka 이벤트 발행/구독.", verifyCmd:"kubectl get deploy engagement-svc" },
    { id:"knowledge", label:"knowledge-svc", kind:"svc", color:"#f778ba", x:7, y:3,
      role:"지식/검색", detail:"Elasticsearch 색인·검색.", verifyCmd:"kubectl get deploy knowledge-svc" },
    { id:"learningcard", label:"learning-card", kind:"svc", color:"#ff7b72", x:7, y:4,
      role:"학습카드", detail:"학습 카드 도메인.", verifyCmd:"kubectl get deploy learning-card" },
    { id:"learningai", label:"learning-ai", kind:"svc", color:"#e3b341", x:7, y:5,
      role:"AI 추론 컨테이너", detail:"learning 관련 AI.", verifyCmd:"kubectl get deploy learning-ai" },
    { id:"rds", label:"RDS PG16.9", kind:"managed", x:9, y:1, tfFile:"rds.tf",
      role:"PostgreSQL 16.9", detail:"db.t3.medium, 20GB(max 50), private, EKS SG에서만. dev Multi-AZ 꺼짐.",
      verifyCmd:"앱 health 또는 psql" },
    { id:"msk", label:"MSK 3.6.0", kind:"managed", x:9, y:2, tfFile:"msk.tf",
      role:"Kafka 3.6.0", detail:"broker 3, kafka.t3.small, TLS. Schema Registry 연동.",
      verifyCmd:"kafka-broker-api-versions.sh" },
    { id:"sr", label:"Schema Registry", kind:"managed", x:9, y:3,
      role:"Avro 스키마 레지스트리", detail:"MSK와 같은 VPC 내부. BACKWARD 호환.",
      verifyCmd:"GET /subjects" },
    { id:"redis", label:"ElastiCache 7.1", kind:"managed", x:9, y:4, tfFile:"redis.tf",
      role:"Redis 7.1", detail:"cache.t3.micro 1 node, in-transit 암호화, failover 꺼짐(dev).",
      verifyCmd:"redis-cli --tls ping" },
    { id:"es", label:"Elasticsearch", kind:"incluster", x:9, y:5,
      role:"검색(EKS 내 StatefulSet)", detail:"AWS 관리형 아님. apps/elasticsearch StatefulSet.",
      verifyCmd:"GET /_cluster/health" },
    { id:"ecr", label:"ECR", kind:"cicd", x:11, y:1, role:"컨테이너 레지스트리",
      detail:"GHA가 이미지 push. image-updater가 태그 추적.", verifyCmd:"aws ecr describe-images" },
    { id:"argocd", label:"ArgoCD", kind:"cicd", x:11, y:2, role:"GitOps 컨트롤러",
      detail:"ApplicationSet 7대상×3env. dev/staging auto, prod 수동.", verifyCmd:"argocd app list" },
    { id:"velero", label:"Velero", kind:"ops", x:11, y:4, tfFile:"velero.tf",
      role:"백업/복구", detail:"클러스터 리소스·PV 백업.", verifyCmd:"velero backup get" },
    { id:"bastion", label:"bastion", kind:"ops", x:11, y:5, tfFile:"bastion.tf",
      role:"점프 호스트", detail:"private 리소스 디버그 접근.", verifyCmd:"ssh bastion" },
  ],
  edges: [
    { from:"internet", to:"alb", kind:"route" },
    { from:"alb", to:"gateway", kind:"route" },
    { from:"gateway", to:"frontend", kind:"route" },
    { from:"gateway", to:"platform", kind:"rest" },
    { from:"gateway", to:"engagement", kind:"rest" },
    { from:"gateway", to:"knowledge", kind:"rest" },
    { from:"gateway", to:"learningcard", kind:"rest" },
    { from:"gateway", to:"learningai", kind:"rest" },
    { from:"platform", to:"rds", kind:"store" },
    { from:"engagement", to:"msk", kind:"kafka" },
    { from:"engagement", to:"rds", kind:"store" },
    { from:"knowledge", to:"es", kind:"store" },
    { from:"knowledge", to:"rds", kind:"store" },
    { from:"msk", to:"sr", kind:"kafka" },
    { from:"platform", to:"redis", kind:"store" },
    { from:"ecr", to:"argocd", kind:"route" },
  ],
};
```

- [ ] **Step 2: 콘솔 무결성 확인**

```js
SYSTEM.topology.nodes.length        // 18
SYSTEM.topology.edges.every(e =>
  SYSTEM.topology.nodes.find(n=>n.id===e.from) &&
  SYSTEM.topology.nodes.find(n=>n.id===e.to))   // true (끊긴 엣지 없음)
```
Expected: `18`, `true`. 에러 0.

- [ ] **Step 3: Commit**

```bash
git add docs/aws-deploy-guide.html
git commit -m "feat(guide): SYSTEM topology nodes+edges 데이터"
```

---

## Task 4: 토폴로지 SVG 렌더러 + 엣지 의미색

**Files:**
- Modify: `docs/aws-deploy-guide.html`

- [ ] **Step 1: 엣지 색 매핑 + 렌더러 작성**

`<script>`에 추가. 좌표는 x*120, y*90 px 그리드. 엣지 색은 의미 잠금 토큰 사용.

```js
const EDGE_COLOR = { rest:"var(--rest)", kafka:"var(--kafka)",
                     store:"var(--store)", route:"var(--accent)" };
const GX = 120, GY = 90, NW = 96, NH = 40;
function nodePos(n){ return { cx:n.x*GX, cy:n.y*GY }; }

function renderTopology(env){
  const t = SYSTEM.topology;
  const W = 13*GX, H = 6*GY;
  const svg = ['<svg id="map-svg" viewBox="0 0 '+W+' '+H+'" width="100%" role="img" aria-label="AWS 토폴로지">'];
  // edges
  for(const e of t.edges){
    const a = nodePos(t.nodes.find(n=>n.id===e.from));
    const b = nodePos(t.nodes.find(n=>n.id===e.to));
    svg.push('<line x1="'+a.cx+'" y1="'+a.cy+'" x2="'+b.cx+'" y2="'+b.cy+
      '" stroke="'+EDGE_COLOR[e.kind]+'" stroke-width="1.5" opacity="0.55"/>');
  }
  // nodes
  for(const n of t.nodes){
    const p = nodePos(n);
    const stroke = n.color || "var(--line)";
    svg.push(
      '<g class="node" data-id="'+n.id+'" tabindex="0" style="cursor:pointer">'+
      '<rect x="'+(p.cx-NW/2)+'" y="'+(p.cy-NH/2)+'" width="'+NW+'" height="'+NH+
        '" rx="6" fill="var(--panel)" stroke="'+stroke+'" stroke-width="1.5"/>'+
      '<text x="'+p.cx+'" y="'+(p.cy+4)+'" text-anchor="middle" '+
        'font-family="var(--mono)" font-size="11" fill="var(--fg)">'+n.label+'</text>'+
      '</g>');
  }
  svg.push('</svg>');
  return svg.join('');
}
```

- [ ] **Step 2: stage에 임시 마운트해서 눈으로 확인**

`<script>` 끝에 임시로:
```js
document.getElementById('stage').innerHTML = renderTopology('dev');
```

- [ ] **Step 3: 브라우저 검증**

열기. Expected: 18개 노드 박스가 좌→우(internet→alb→gateway→svc→managed→cicd/ops)로 배치, 엣지가 색으로 구분됨 — gateway→frontend/ecr→argocd는 퍼플(route), gateway→백엔드는 파랑(rest), msk 관련 앰버(kafka), DB/검색은 초록(store). Console 에러 0.

- [ ] **Step 4: 임시 마운트 제거 후 Commit**

Step 2의 임시 줄을 삭제한다(다음 태스크에서 init이 호출).
```bash
git add docs/aws-deploy-guide.html
git commit -m "feat(guide): 토폴로지 SVG 렌더러 + 의미색 엣지"
```

---

## Task 5: 환경 토글 (dev/staging/prod) + 애니메이션 배지

**Files:**
- Modify: `docs/aws-deploy-guide.html`

- [ ] **Step 1: env 토글 버튼 렌더 + 상태 배지**

```js
let CURRENT_ENV = SYSTEM.meta.env;
function renderEnvToggle(){
  const box = document.getElementById('env-toggle');
  box.innerHTML = Object.keys(SYSTEM.envs).map(k =>
    '<button type="button" data-env="'+k+'" aria-pressed="'+(k===CURRENT_ENV)+'">'+
    SYSTEM.envs[k].label+'</button>').join('');
  box.querySelectorAll('button').forEach(b =>
    b.addEventListener('click', ()=> setEnv(b.dataset.env)));
}
function envBadges(env){
  const e = SYSTEM.envs[env];
  const items = [
    'EKS '+e.eksNodes+' nodes', 'MSK '+e.mskBrokers+' broker',
    e.multiAZ?'Multi-AZ':'Single-AZ', 'sync: '+e.sync, ...e.hardening];
  return '<div id="badges" style="display:flex;gap:var(--sm);flex-wrap:wrap;'+
    'padding:var(--md) var(--lg);transition:opacity 300ms ease">'+
    items.map(x=>'<span class="mono" style="font-size:11px;color:var(--muted);'+
      'border:1px solid var(--line);border-radius:9999px;padding:2px 8px">'+x+'</span>').join('')+
    '</div>';
}
function setEnv(env){
  CURRENT_ENV = env;
  renderEnvToggle();
  const badges = document.getElementById('badges');
  if(badges){ badges.style.opacity = 0;
    setTimeout(()=>{ refreshHero(); }, 150); }
  else refreshHero();
}
function refreshHero(){
  const hero = document.getElementById('hero');
  if(hero) hero.innerHTML = envBadges(CURRENT_ENV) + renderTopology(CURRENT_ENV);
}
```

- [ ] **Step 2: init()로 묶기**

`<script>` 끝에:
```js
function init(){
  renderEnvToggle();
  document.getElementById('stage').innerHTML =
    '<section id="hero"></section>';
  refreshHero();
}
init();
```

- [ ] **Step 3: 브라우저 검증**

열기. Expected: topbar 우측에 dev/staging/prod 버튼(현재 dev가 accent 보더). dev 클릭 시 배지 "EKS 4 nodes / MSK 3 broker / Single-AZ / sync: auto / non-root". **prod 클릭 시** 배지가 "Multi-AZ / sync: manual / non-root / NetworkPolicy / HPA / Multi-AZ"로 바뀌고 0.3s opacity 전환이 보임. Console 에러 0.

- [ ] **Step 4: Commit**

```bash
git add docs/aws-deploy-guide.html
git commit -m "feat(guide): 환경 토글 + 상태 배지 애니메이션"
```

---

## Task 6: 상세 패널 (노드 클릭)

**Files:**
- Modify: `docs/aws-deploy-guide.html`

- [ ] **Step 1: detail 패널 CSS + 위임 핸들러**

`<style>`에 추가:
```css
#detail{ position:fixed; right:0; top:44px; width:340px; max-height:80vh; overflow:auto;
  background:var(--panel); border-left:1px solid var(--line); padding:var(--lg); }
#detail h3{ font-family:var(--mono); font-weight:600; font-size:18px; margin:0 0 var(--md); }
#detail .k{ font-family:var(--mono); font-size:11px; text-transform:uppercase;
  color:var(--dim); margin-top:var(--md); }
#detail code{ font-family:var(--mono); color:var(--accent); }
```
`<script>`에 추가:
```js
function showDetail(id){
  const n = SYSTEM.topology.nodes.find(x=>x.id===id);
  if(!n) return;
  const el = document.getElementById('detail');
  el.innerHTML = '<h3>'+n.label+'</h3>'+
    '<div>'+n.role+'</div>'+
    (n.tfFile?'<div class="k">terraform</div><code>infra/aws/dev/'+n.tfFile+'</code>':'')+
    '<div class="k">설명</div><div>'+n.detail+'</div>'+
    (n.verifyCmd?'<div class="k">접속 확인</div><code>'+n.verifyCmd+'</code>':'');
  el.hidden = false;
}
document.getElementById('stage').addEventListener('click', ev=>{
  const g = ev.target.closest('.node'); if(g) showDetail(g.dataset.id);
});
document.getElementById('stage').addEventListener('keydown', ev=>{
  if(ev.key==='Enter'){ const g=ev.target.closest('.node'); if(g) showDetail(g.dataset.id); }
});
```

- [ ] **Step 2: 브라우저 검증**

열기. Expected: `rds` 노드 클릭 → 우측 패널에 "RDS PG16.9", role, `infra/aws/dev/rds.tf`, 설명, 접속 확인 `앱 health 또는 psql` 표시. `gateway` 클릭 → catch-all 설명 표시. Console 에러 0.

- [ ] **Step 3: Commit**

```bash
git add docs/aws-deploy-guide.html
git commit -m "feat(guide): 노드 클릭 상세 패널"
```

---

## Task 7: SYSTEM.chapters 데이터 (7섹션 본문)

**Files:**
- Modify: `docs/aws-deploy-guide.html`

- [ ] **Step 1: chapters 배열 작성**

`SYSTEM.topology` 뒤에 추가. `slideBody`(발표용 핵심), `refBody`(레퍼런스 보충), `visual`(hero|none). 문구는 `docs/aws-infra-provisioning-workflow-guide.md`를 입문자 톤으로 압축.

```js
SYSTEM.chapters = [
  { id:"warmup", title:"1. AWS 개념 워밍업", visual:"none",
    slideBody:"AWS를 처음 봐도 괜찮다. 딱 7개 단어만 알면 된다.",
    refBody:"GLOSSARY" },  // 렌더러가 glossary 표로 치환
  { id:"big-picture", title:"2. 전체 그림", visual:"hero",
    slideBody:"커밋 → ECR → ArgoCD → EKS. 사용자는 ALB→gateway로 들어와 /api는 백엔드, 나머지는 frontend.",
    refBody:"배포 파이프라인과 사용자 트래픽 경로는 분리된 두 흐름이다. 배포: dev/GHA→docker build→ECR push→gitops 태그 bump→ArgoCD sync→EKS. 트래픽: 인터넷→ALB(ACM TLS)→gateway→(/api/** 백엔드 JWT | catch-all frontend SPA)." },
  { id:"setup", title:"3. 기본 세팅", visual:"none",
    slideBody:"AWS 계정/OIDC를 잡고 Terraform을 순서대로 적용한다: vpc→eks→rds/msk/redis→addons→irsa.",
    refBody:"근거: runbooks/step1-aws-account-setup.md, plans/2026-05-14-aws-infra-terraform.md. 순서가 중요한 이유: 네트워크(vpc)가 먼저 있어야 컴퓨트(eks)가 그 위에 뜨고, 데이터 계층이 같은 사설망에 들어가며, addons/IRSA는 클러스터가 존재해야 붙는다." },
  { id:"components", title:"4. 인프라 구성요소", visual:"hero",
    slideBody:"각 박스를 클릭하면 역할·terraform 파일·접속 확인이 나온다.",
    refBody:"EKS(t3.medium×4) · RDS(PG16.9 db.t3.medium) · MSK(3.6.0 broker3 kafka.t3.small TLS) · ElastiCache(Redis7.1 cache.t3.micro) · 검색은 EKS 내 Elasticsearch StatefulSet(관리형 아님) · ECR/ArgoCD/ALB · bastion/Velero. 모두 private 우선, ALB만 public." },
  { id:"how-deploy", title:"5. 배포가 도는 방식", visual:"none",
    slideBody:"ApplicationSet이 7개 대상 × 3환경을 matrix로 찍어낸다. 커밋하면 image-updater가 태그를 올리고 ArgoCD가 동기화.",
    refBody:"근거: argocd/applicationset.yaml. 대상=platform·engagement·knowledge·learning-card·learning-ai·gateway·frontend. frontend는 synapse-frontend에서 Flutter web→Docker(nginx)→ECR(#21/#22) 후 gitops 태그 bump로 합류. dev/staging은 automated(prune+selfHeal)." },
  { id:"promote", title:"6. 환경 승급", visual:"hero",
    slideBody:"dev·staging은 자동 sync, prod는 사람이 승인하고 수동 sync. 위 환경 토글로 차이를 보라.",
    refBody:"근거: applicationset{,-staging,-prod}.yaml + apps/*/overlays/*. prod만 automated가 없다 — main 머지 후 OutOfSync 대기 → gitops-admin 수동 sync(FR-GO-402 승인 게이트). prod 하드닝: NetworkPolicy(5 오버레이)+HPA(10 오버레이)+non-root+Multi-AZ." },
  { id:"ops", title:"7. 운영·보안·비용", visual:"none",
    slideBody:"백업은 Velero, 시크릿은 ESO로 외부 주입, dev는 월 $200 제약. 다 쓰면 destroy.",
    refBody:"근거: runbooks/step11-operational-runbook.md, velero.tf, eso-irsa.tf. ESO(External Secrets)가 AWS Secrets Manager 값을 클러스터 Secret으로 동기화 — 비밀값은 git에 없다. dev 비용 상한 월 $200. 미사용 시 terraform destroy로 정리." },
];
```

- [ ] **Step 2: 콘솔 확인**

```js
SYSTEM.chapters.length          // 7
SYSTEM.chapters.map(c=>c.visual) // ["none","hero","none","hero","none","hero","none"]
```
Expected: 일치. 에러 0.

- [ ] **Step 3: Commit**

```bash
git add docs/aws-deploy-guide.html
git commit -m "feat(guide): SYSTEM chapters 7섹션 본문"
```

---

## Task 8: 발표 모드 챕터 렌더러 + 키보드 네비

**Files:**
- Modify: `docs/aws-deploy-guide.html`

- [ ] **Step 1: 슬라이드 렌더러 + 네비 작성**

```js
let SLIDE = 0;
function renderGlossaryTable(){
  return '<table style="border-collapse:collapse;width:100%">'+
    '<thead><tr>'+['용어','한 줄','왜 쓰나'].map(h=>
      '<th class="mono" style="text-align:left;font-size:11px;text-transform:uppercase;'+
      'color:var(--dim);border-bottom:1px solid var(--line);padding:var(--sm)">'+h+'</th>').join('')+
    '</tr></thead><tbody>'+
    SYSTEM.glossary.map(g=>'<tr>'+
      '<td class="mono" style="padding:var(--sm);color:var(--accent)">'+g.term+'</td>'+
      '<td style="padding:var(--sm)">'+g.oneLiner+'</td>'+
      '<td style="padding:var(--sm);color:var(--muted)">'+g.whyWeUse+'</td></tr>').join('')+
    '</tbody></table>';
}
function chapterInner(c){
  let body = '<p style="font-size:16px">'+c.slideBody+'</p>';
  if(c.refBody==="GLOSSARY") body += renderGlossaryTable();
  if(c.visual==="hero") body += '<section id="hero"></section>';
  return '<h2 class="mono" style="font-size:18px">'+c.title+'</h2>'+body;
}
function renderSlide(){
  const c = SYSTEM.chapters[SLIDE];
  const stage = document.getElementById('stage');
  stage.innerHTML = '<article class="slide" style="padding:var(--xl);max-width:1100px;margin:0 auto">'+
    chapterInner(c)+'</article>'+
    '<footer class="mono" style="position:fixed;bottom:0;left:0;right:0;'+
    'display:flex;justify-content:center;gap:var(--sm);padding:var(--md);'+
    'border-top:1px solid var(--line);color:var(--dim);font-size:11px">'+
    SYSTEM.chapters.map((_,i)=>'<span style="color:'+(i===SLIDE?'var(--accent)':'var(--dim)')+'">●</span>').join('')+
    '<span>&nbsp;'+(SLIDE+1)+' / '+SYSTEM.chapters.length+'</span></footer>';
  if(c.visual==="hero") refreshHero();
  location.hash = 'ch-'+c.id;
}
function go(d){ SLIDE = Math.max(0, Math.min(SYSTEM.chapters.length-1, SLIDE+d)); renderSlide(); }
window.addEventListener('keydown', ev=>{
  if(MODE!=="slide") return;
  if(ev.key==="ArrowRight"||ev.key===" "){ ev.preventDefault(); go(1); }
  if(ev.key==="ArrowLeft"){ ev.preventDefault(); go(-1); }
});
```

- [ ] **Step 2: init()를 발표 모드로 전환**

`init()`의 stage 채우는 부분을 교체:
```js
let MODE = "slide";
function init(){
  renderEnvToggle();
  if(location.hash.startsWith('#ch-')){
    const i = SYSTEM.chapters.findIndex(c=>'ch-'+c.id===location.hash.slice(1));
    if(i>=0) SLIDE = i;
  }
  renderSlide();
}
init();
```
(Task 5의 `init` 정의는 이 정의로 대체 — 중복 정의 남기지 말 것.)

- [ ] **Step 3: 브라우저 검증**

열기. Expected: 슬라이드 1 "AWS 개념 워밍업" + glossary 7행 표. →(또는 Space) 누르면 슬라이드 2 "전체 그림" + 히어로 토폴로지 맵 표시. 하단 진행 점에서 현재 위치 accent. ←로 복귀. prod 환경 토글이 히어로 슬라이드에서 동작. Console 에러 0.

- [ ] **Step 4: Commit**

```bash
git add docs/aws-deploy-guide.html
git commit -m "feat(guide): 발표 모드 슬라이드 렌더러 + 키보드 네비"
```

---

## Task 9: 레퍼런스 모드 + 모드 토글

**Files:**
- Modify: `docs/aws-deploy-guide.html`

- [ ] **Step 1: 레퍼런스 렌더러 + 토글**

```js
function renderReference(){
  const stage = document.getElementById('stage');
  const nav = '<nav class="mono" style="position:sticky;top:0;align-self:start;'+
    'display:flex;flex-direction:column;gap:var(--xs);padding:var(--lg);'+
    'border-right:1px solid var(--line);min-width:200px;font-size:12px">'+
    SYSTEM.chapters.map(c=>'<a href="#ch-'+c.id+'" style="color:var(--muted);'+
      'text-decoration:none">'+c.title+'</a>').join('')+'</nav>';
  const body = '<div style="padding:var(--xl);max-width:900px">'+
    SYSTEM.chapters.map(c=>{
      let inner = '<h2 class="mono" id="ch-'+c.id+'" style="font-size:18px;margin-top:var(--2xl,24px)">'+c.title+'</h2>'+
        '<p style="font-size:16px">'+c.slideBody+'</p>';
      if(c.refBody==="GLOSSARY") inner += renderGlossaryTable();
      else inner += '<p style="color:var(--muted)">'+c.refBody+'</p>';
      if(c.visual==="hero") inner += '<section id="hero-'+c.id+'"></section>';
      return inner;
    }).join('')+'</div>';
  stage.innerHTML = '<div style="display:flex;gap:var(--lg)">'+nav+body+'</div>';
  // 레퍼런스에서는 첫 hero에만 토폴로지(중복 id 방지) — big-picture 기준
  const h = document.getElementById('hero-big-picture');
  if(h) h.innerHTML = envBadges(CURRENT_ENV) + renderTopology(CURRENT_ENV);
}
function setMode(m){
  MODE = m;
  document.getElementById('mode-btn').textContent =
    m==="slide" ? "레퍼런스 모드" : "발표 모드";
  if(m==="slide") renderSlide(); else renderReference();
}
document.getElementById('mode-btn').addEventListener('click', ()=>
  setMode(MODE==="slide" ? "ref" : "slide"));
```

> 참고: 레퍼런스 모드에서 `refreshHero()`는 `#hero` 단일 id를 쓰므로, 토폴로지는 big-picture 섹션의 `#hero-big-picture`에만 그린다. env 토글 시 레퍼런스 모드면 이 노드를 다시 그리도록 `setEnv`에 분기 추가:

```js
// setEnv 내부 refreshHero 호출부를 교체:
function applyEnv(){
  if(MODE==="slide"){ refreshHero(); }
  else { const h=document.getElementById('hero-big-picture');
    if(h) h.innerHTML = envBadges(CURRENT_ENV)+renderTopology(CURRENT_ENV); }
}
```
그리고 `setEnv`에서 `refreshHero()` 대신 `applyEnv()`를 호출하도록 수정.

- [ ] **Step 2: 브라우저 검증**

열기(발표 모드). "레퍼런스 모드" 버튼 클릭 → 좌측 7섹션 네비 + 연속 스크롤 본문, big-picture에 토폴로지. 네비 링크 클릭 시 해당 섹션 점프. env 토글이 토폴로지 갱신. 버튼이 "발표 모드"로 바뀌고 다시 누르면 슬라이드 복귀(현재 챕터 유지). Console 에러 0.

- [ ] **Step 3: Commit**

```bash
git add docs/aws-deploy-guide.html
git commit -m "feat(guide): 레퍼런스 모드 + 모드 토글"
```

---

## Task 10: 최종 QA + 콘텐츠 크로스체크 + 한글 폴백 확인

**Files:**
- Modify: `docs/aws-deploy-guide.html` (필요 시 수정만)

- [ ] **Step 1: 콘텐츠 정합성 크로스체크**

다음을 실제 파일과 대조하고 어긋나면 데이터 수정:
- EKS/RDS/MSK/Redis 스펙 ↔ `infra/aws/dev/{eks,rds,msk,redis,variables}.tf`
- 7 대상 목록 ↔ `argocd/applicationset.yaml`(line 12-18)
- prod 수동 sync ↔ `argocd/applicationset-prod.yaml`(automated 없음)
- gateway 라우팅 ↔ gateway `RoutesConfig.java`/`SecurityConfig.java`

Run(대조 보조):
```bash
grep -nE "service:" ../synapse-gitops/argocd/applicationset.yaml
```
Expected: platform/engagement/knowledge/learning-card/learning-ai/gateway/frontend 7개.

- [ ] **Step 2: 폰트 폴백/오프라인 검증**

`file://`로 더블클릭(로컬 서버 아님) 열기. Expected: 라틴/숫자/코드가 Geist(폴백 아님)로 렌더, 한글은 시스템 폰트(Pretendard/Malgun)로 정상 표시. 네트워크 끊고 새로고침해도 동일(외부 의존 0).

- [ ] **Step 3: 인터랙션 전수 확인**

Expected 체크리스트(모두 통과):
- 발표 모드 ←/→/Space 7슬라이드 이동, 진행 점 정확
- 히어로 슬라이드(2·4·6)에서 env 토글 dev↔staging↔prod 배지/토폴로지 변화 + 0.3s 전환
- 18개 노드 전부 클릭 → 상세 패널(역할/tf/설명/접속확인) 표시
- 레퍼런스 모드 토글 + 네비 점프 + 모드 복귀 시 챕터 유지
- DevTools Console 에러/경고 0

- [ ] **Step 4: 비밀값 미포함 확인**

Run:
```bash
grep -nE "AKIA|BEGIN (RSA |EC )?PRIVATE|secret|password|[0-9]{12}" docs/aws-deploy-guide.html
```
Expected: 실제 키/계정ID/비밀번호 매치 없음(placeholder만). 있으면 제거.

- [ ] **Step 5: Commit**

```bash
git add docs/aws-deploy-guide.html
git commit -m "test(guide): 최종 QA + 콘텐츠 크로스체크 + 오프라인 폰트 확인"
```

---

## Self-Review 결과 (작성자 점검)

- **Spec coverage:** 스펙 §3 아키텍처(SYSTEM/모듈 경계)→T2·T3·T7, §4 히어로/env토글→T4·T5, §4 라우팅→T3·T6, §5 7섹션→T7~T9, §6 스타일→T1, §7 모드→T8·T9, §8 검증→T10. 누락 없음.
- **Placeholder scan:** 모든 코드 단계에 실제 코드/값. "적절히 처리" 류 없음. 데이터 값은 terraform 실측.
- **Type consistency:** `renderTopology(env)`·`refreshHero()`·`setEnv()`→`applyEnv()`(T9에서 교체 명시)·`MODE`/`SLIDE`/`CURRENT_ENV` 전역 일관. `init()`는 T5 정의를 T8에서 대체하라고 명시(중복 방지). `#hero`(슬라이드)와 `#hero-big-picture`(레퍼런스) id 분리로 중복 회피.
- **알려진 주의:** T8에서 T5의 `init` 대체, T9에서 `setEnv`의 `refreshHero`→`applyEnv` 교체 — 실행자는 이전 정의를 남기지 말 것.
