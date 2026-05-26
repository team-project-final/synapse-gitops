# "서비스 사용·확인하기" 섹션 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `local-msa-setup.html`에 새 §5 "서비스 사용·확인하기"(Swagger /docs, API 호출, Kafka 이벤트 관찰, 데이터 확인)를 추가하고 뒤 섹션 번호를 한 칸씩 이동한다.

**Architecture:** 기존 단일 HTML의 §4 뒤에 새 `<section id="usage">`(번호 5)를 삽입하고, 기존 #data/#trouble/#next 배지를 6/7/8로 이동. 새 콘텐츠는 기존 패턴(번호 단계·`.code` 복사 블록·`<details class="deep">` 심화) 재사용. 새 CSS/JS 불필요.

**Tech Stack:** 순수 HTML(기존 인라인 CSS/JS 재사용). 검증은 playwright(`http://localhost:51300/local-msa-setup.html`).

**스펙:** `docs/superpowers/specs/2026-05-26-msa-usage-section-design.md`

---

## 검증된 사실 (이 값만 사용 — 실제 파일로 확인 완료)

- **learning-ai Swagger UI**: `/docs`(+`/redoc`) 기본 제공. 경로① `http://localhost:8000/docs`, 경로② `http://localhost:8090/docs`.
- **Spring 서비스(platform/engagement/knowledge/learning-card)**: springdoc 없음 → `/actuator/health`만.
- **Gateway 라우트(경로②, :8080)** — `synapse-gateway` `RoutesConfig.java`, 모두 `stripPrefix(2)`:
  `/api/platform/**`→platform-svc · `/api/engagement/**`→engagement-svc · `/api/knowledge/**`→knowledge-svc · `/api/learning/**`→learning-card.
  예: `/api/platform/actuator/health` → platform-svc `/actuator/health`.
- **Kafka**: 컨테이너명 `synapse-kafka`(두 스택 공통), 포트 9092. 토픽 5개:
  `platform.auth.user-registered-v1`, `knowledge.note.note-created-v1`, `knowledge.note.note-updated-v1`, `learning.card.review-completed-v1`, `learning.ai.cards-generated-v1`.
- **PostgreSQL**: 컨테이너 `synapse-postgres`, user/db = `synapse`/`synapse`(로컬 exec는 비밀번호 불필요, 둘 다 동일).
- **Redis**: 컨테이너 `synapse-redis`, 비밀번호 **경로②(shared)=`redis_local_pw` / 경로①(gitops)=`redis_local`**.
- **검색엔진**: 포트 9200, `/_cluster/health`, `/_cat/indices?v`.
- **Schema Registry**: 경로① `:8085/subjects`, 경로② `:8086`.

---

## 파일 구조

| 파일 | 작업 | 책임 |
|---|---|---|
| `synapse-gitops/docs/local-msa-setup.html` | Modify | 새 §5 usage 섹션 추가 + 기존 §5/§6/§7 배지 → §6/§7/§8 |

단일 파일. Task 1(번호 이동) → Task 2(섹션 삽입) → Task 3(QA). 각 태스크 후 커밋.

> **검증용 정적 서버:** `cd /c/workspace/team-project-final/synapse-gitops/docs && python -m http.server 51300 --bind 127.0.0.1` (백그라운드). playwright는 `file://` 차단 → `http://localhost:51300/local-msa-setup.html` 사용.

---

## Task 1: 뒤 섹션 번호 이동 (5/6/7 → 6/7/8)

**Files:**
- Modify: `synapse-gitops/docs/local-msa-setup.html` (3개 섹션 헤더)

- [ ] **Step 1: 데이터 섹션 배지 5→6**

old:
```html
    <section id="data"><h2 class="sec"><span class="num">5</span>목업 · 시드 데이터 (선택)</h2>
```
new:
```html
    <section id="data"><h2 class="sec"><span class="num">6</span>목업 · 시드 데이터 (선택)</h2>
```

- [ ] **Step 2: 트러블슈팅 배지 6→7**

old:
```html
    <section id="trouble"><h2 class="sec"><span class="num">6</span>트러블슈팅</h2>
```
new:
```html
    <section id="trouble"><h2 class="sec"><span class="num">7</span>트러블슈팅</h2>
```

- [ ] **Step 3: 다음 단계 배지 7→8**

old:
```html
    <section id="next"><h2 class="sec"><span class="num">7</span>다음 단계 · 더 깊이 보기</h2>
```
new:
```html
    <section id="next"><h2 class="sec"><span class="num">8</span>다음 단계 · 더 깊이 보기</h2>
```

- [ ] **Step 4: 확인**

정적 서버 기동 후 `http://localhost:51300/local-msa-setup.html` 접속.
```js
// playwright browser_evaluate
() => Array.from(document.querySelectorAll('main section[id] .num')).map(n=>n.textContent)
// Expected: ["0","1","2","3","4","6","7","8"]  (5는 Task 2에서 삽입 — 일시적 결번)
```

- [ ] **Step 5: 커밋**

```bash
cd /c/workspace/team-project-final/synapse-gitops
git add docs/local-msa-setup.html
git commit -m "docs(guide): 사용법 섹션 자리 위해 §5-7 → §6-8 번호 이동"
```

---

## Task 2: 새 §5 "서비스 사용·확인하기" 섹션 삽입

**Files:**
- Modify: `synapse-gitops/docs/local-msa-setup.html` (#data 섹션 바로 앞에 삽입)

- [ ] **Step 1: 섹션 삽입**

`    <section id="data"><h2 class="sec"><span class="num">6</span>목업 · 시드 데이터 (선택)</h2>` 바로 앞에 아래 블록을 삽입한다(즉 이 한 줄을 "새 섹션 + 같은 data 줄"로 치환).

치환 대상(old):
```html
    <section id="data"><h2 class="sec"><span class="num">6</span>목업 · 시드 데이터 (선택)</h2>
```

치환 결과(new):
```html
    <section id="usage"><h2 class="sec"><span class="num">5</span>서비스 사용·확인하기</h2>
      <p>설치(<a href="#path1">§3</a>/<a href="#path2">§4</a>)로 서비스가 떴다면, 이제 실제로 열어보고 호출하고 이벤트가 흐르는 걸 확인해 봅시다. 경로①은 포트를 직접, 경로②는 Gateway(:8080)를 경유합니다.</p>

      <h3>5.1 브라우저로 열어보는 뷰</h3>
      <p>⭐ <strong>learning-ai Swagger UI</strong> — 이 프로젝트에서 버튼으로 API를 직접 실행("Try it out")해볼 수 있는 유일한 GUI입니다.</p>
      <div class="code">http://localhost:8000/docs     # 경로① Swagger UI
http://localhost:8090/docs     # 경로② Swagger UI
http://localhost:8000/redoc    # ReDoc (읽기용 문서)</div>
      <p>브라우저로 바로 열리는 상태(JSON) 뷰:</p>
      <div class="code">http://localhost:8080/actuator/health   # platform-svc 상태
http://localhost:8085/subjects           # 등록된 Avro 스키마 (경로② :8086)
http://localhost:9200/_cluster/health    # 검색엔진 상태</div>
      <details class="deep"><summary>다른 서비스는 왜 Swagger UI가 없나? (심화)</summary>
        <div class="body">Spring 서비스(platform·engagement·knowledge·learning-card)에는 springdoc이 적용돼 있지 않아 Swagger UI가 없습니다. 대신 <code>/actuator/health</code> 등 actuator 엔드포인트로 상태를 확인합니다. learning-ai만 FastAPI 기본 제공으로 <code>/docs</code>가 열립니다.</div>
      </details>

      <h3>5.2 API 호출해보기 — Gateway 경유 vs 직접</h3>
      <p>경로②는 Gateway가 <code>/api/{서비스}/**</code> 요청을 받아 해당 서비스로 전달합니다(앞 2개 세그먼트 제거 후 전달).</p>
      <div class="code">curl http://localhost:8080/api/platform/actuator/health     # → platform-svc
curl http://localhost:8080/api/knowledge/actuator/health    # → knowledge-svc</div>
      <p>경로①은 Gateway가 없으니 서비스 포트로 직접 호출합니다.</p>
      <div class="code">curl http://localhost:8080/actuator/health   # platform-svc 직접
curl http://localhost:8083/actuator/health   # knowledge-svc 직접</div>
      <details class="deep"><summary>Gateway 라우팅 규칙 (심화)</summary>
        <div class="body">Gateway(<code>synapse-gateway</code>)는 4개 경로를 stripPrefix(2)로 전달합니다: <code>/api/platform/**</code>→platform-svc, <code>/api/engagement/**</code>→engagement-svc, <code>/api/knowledge/**</code>→knowledge-svc, <code>/api/learning/**</code>→learning-card. 예: <code>/api/platform/actuator/health</code> → platform-svc의 <code>/actuator/health</code>. (Redis 기반 rate limit 적용)</div>
      </details>

      <h3>5.3 Kafka 이벤트가 흐르는 걸 보기</h3>
      <p>한 터미널에서 토픽을 구독해 두고, 다른 터미널에서 액션을 일으키면 이벤트가 실시간으로 출력됩니다 — MSA가 이벤트로 도는 걸 눈으로 확인할 수 있습니다.</p>
      <div class="code">docker exec -it synapse-kafka kafka-console-consumer --bootstrap-server localhost:9092 --topic knowledge.note.note-created-v1 --from-beginning</div>
      <p>자동 생성되는 토픽 5개:</p>
      <div class="code">platform.auth.user-registered-v1
knowledge.note.note-created-v1
knowledge.note.note-updated-v1
learning.card.review-completed-v1
learning.ai.cards-generated-v1</div>

      <h3>5.4 저장된 데이터 직접 확인</h3>
      <div class="code">docker exec -it synapse-postgres psql -U synapse -d synapse -c "\dt"</div>
      <div class="code">docker exec -it synapse-redis redis-cli -a redis_local_pw keys '*'   # 경로② (경로①: -a redis_local)</div>
      <div class="code">curl http://localhost:9200/_cat/indices?v</div>
      <details class="deep"><summary>자격증명은 어디서 오나? (심화)</summary>
        <div class="body">두 스택 모두 PostgreSQL 사용자/DB는 <code>synapse</code>/<code>synapse</code>이며 컨테이너 내부 로컬 접속은 비밀번호가 필요 없습니다. Redis 비밀번호만 다릅니다 — 경로②(synapse-shared)는 <code>redis_local_pw</code>, 경로①(synapse-gitops)는 <code>redis_local</code>. 값은 각 <code>docker-compose.yml</code>·<code>.env</code> 기본값입니다.</div>
      </details>
    </section>
    <section id="data"><h2 class="sec"><span class="num">6</span>목업 · 시드 데이터 (선택)</h2>
```

- [ ] **Step 2: 렌더 확인**

페이지 재접속 후 playwright `browser_evaluate`:
```js
() => {
  var s=document.getElementById('usage');
  return {
    exists: !!s,
    numBadge: s.querySelector('.num').textContent,
    h3count: s.querySelectorAll('h3').length,
    codeBlocks: s.querySelectorAll('.code').length,
    copyBtns: s.querySelectorAll('.code .copy').length,
    deeps: s.querySelectorAll('details.deep').length,
    tocHasUsage: !!document.querySelector('nav.toc a[data-target="usage"]'),
    badges: Array.from(document.querySelectorAll('main section[id] .num')).map(n=>n.textContent)
  };
}
// Expected: exists true, numBadge "5", h3count 4, codeBlocks 9, copyBtns 9, deeps 3,
//           tocHasUsage true, badges ["0","1","2","3","4","5","6","7","8"]
```

- [ ] **Step 3: 커밋**

```bash
git add docs/local-msa-setup.html
git commit -m "docs(guide): §5 서비스 사용·확인하기 (Swagger/API/Kafka/데이터)"
```

---

## Task 3: 최종 QA + 정확성 대조

**Files:**
- Modify: `synapse-gitops/docs/local-msa-setup.html` (필요 시 수정만)

- [ ] **Step 1: 상호작용/콘솔 확인**

페이지 접속 후:
```js
() => {
  var s=document.getElementById('usage');
  // 첫 코드블록 복사 동작
  s.querySelector('.code .copy').click();
  // 모든 details 펼침 가능
  s.querySelectorAll('details.deep').forEach(d=>d.open=true);
  return {
    swaggerDocs: s.textContent.includes('localhost:8000/docs') && s.textContent.includes('localhost:8090/docs'),
    gatewayRoute: s.textContent.includes('/api/platform/actuator/health'),
    kafkaConsumer: s.textContent.includes('kafka-console-consumer') && s.textContent.includes('knowledge.note.note-created-v1'),
    redisBoth: s.textContent.includes('redis_local_pw') && s.textContent.includes('redis_local'),
    detailsOpen: Array.from(s.querySelectorAll('details.deep')).every(d=>d.open)
  };
}
// Expected: 전부 true
```
이어서 playwright `browser_console_messages` level error → favicon 외 0건.

- [ ] **Step 2: 정확성 최종 대조**

다음을 실제 파일과 1:1 확인:
- Swagger 포트 8000/8090, ReDoc → learning-ai(`app/main.py` FastAPI 기본).
- Gateway 라우트 `/api/{platform|engagement|knowledge|learning}/**` → `synapse-gateway/src/main/java/com/synapse/gateway/config/RoutesConfig.java`.
- Kafka 컨테이너 `synapse-kafka`·토픽 5개 → 두 `docker-compose.yml`의 `kafka-init`.
- Redis 비밀번호 `redis_local_pw`(shared)/`redis_local`(gitops), postgres user/db `synapse`/`synapse` → 두 `docker-compose.yml`.
불일치 시 해당 `.code`/`<details>` 수정 후 Step 1 재검증.

- [ ] **Step 3: 반응형 + 전체 배지 확인**

```js
() => Array.from(document.querySelectorAll('main section[id] .num')).map(n=>n.textContent).join(',')
// Expected: "0,1,2,3,4,5,6,7,8"
```

- [ ] **Step 4: 커밋(수정이 있었던 경우만)**

```bash
git add docs/local-msa-setup.html
git commit -m "docs(guide): 사용법 섹션 QA — 포트/라우트/자격증명 정확성 검증"
```
(Step 2에서 수정이 없었다면 Task 2 커밋으로 충분 — 생략.)

---

## Self-Review (작성자 체크리스트 결과)

**1. 스펙 커버리지:** §3 배치(새 §5 + 6/7/8 이동)→Task 1+2. §4 5.1 Swagger/상태 뷰→Task 2 5.1. 5.2 API(gateway/직접)→5.2. 5.3 Kafka 관찰→5.3. 5.4 데이터→5.4. §5 레벨링(번호+코드+details)→섹션 전반. §6 검증→Task 3. §7 범위밖(minikube)→미포함.

**2. 플레이스홀더 스캔:** 스펙의 `<route>/<user>/<pw>`는 실제 값으로 확정(/api/platform·synapse·redis_local_pw/redis_local). TBD 없음. 모든 명령 검증 완료.

**3. 타입/이름 일관성:** 섹션 id `usage`(Task 2 markup ↔ Task 2/3 검증 스크립트) 일치. 배지 시퀀스 0~8이 Task 1 Step4·Task 2 Step2·Task 3 Step3에서 동일. 코드블록 9개(5.1=2, 5.2=2, 5.3=2, 5.4=3) — Task 2 Step2 기대값 `codeBlocks 9, copyBtns 9`와 일치.
