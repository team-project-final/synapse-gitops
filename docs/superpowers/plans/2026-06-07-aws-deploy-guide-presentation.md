# 계획: AWS 배포 가이드 — web-presentation 통합 + 콘텐츠 보강

> 산출물: `docs/aws-deploy-guide.html` 재구성 설계 문서 (office-hours / builder mode, 2026-06-07)
> 대상: `synapse-gitops/docs/aws-deploy-guide.html` (단일 자기완결 HTML, `SYSTEM` 객체 구동)
> 근거 스킬: `D:\workspace\develop-study-documents\.claude\skills\web-presentation`
> 디자인 정본: `synapse-gitops/DESIGN.md` (다크 전용, 색 의미 잠금, Geist base64 임베드, file:// 자기완결)

---

## 0. 한 줄 요약

현재 가이드의 자체 슬라이드 렌더러를 **web-presentation 캐러셀 엔진**으로 교체하되, `SYSTEM`
데이터 객체를 단일 소스로 유지하고 인터랙티브 토폴로지·env토글·레퍼런스 모드·DESIGN.md
토큰을 모두 보존한다. 콘텐츠는 "최초 설정 → 배포 → 확인/검증"의 **시간축 런북형**으로 재편성하고,
지금 빠진 **배포 확인·검증** 챕터와 **트러블슈팅** 챕터를 신설한다.

## 1. 결정 사항 (office-hours)

| 결정 | 선택 | 근거 |
|------|------|------|
| D1 적용 범위 | **A+B 하이브리드** | web-presentation 캐러셀을 1차 발표 화면으로 채택(overhaul) + 검증된 SYSTEM 엔진(토폴로지·env토글·노드클릭·색의미잠금)·레퍼런스 모드 보존 |
| D2 슬라이드 구조 | **A 시간축 런북형** | 사용자가 "최초→배포→검증" 시간 순서를 명시, "엎어도 됨" → 연대기 재편 + 검증/트러블슈팅 신설 |

## 2. 현재 구조 (as-is)

- 단일 HTML, `const SYSTEM = { meta, topology{nodes,edges}, chapters[7] }`가 전부를 구동
- **듀얼 모드**: `MODE = "slide" | "ref"` (`#mode-btn`로 토글)
  - slide 모드 = 자체 렌더러가 `#stage`의 innerHTML을 SLIDE 인덱스로 스왑 (키보드/프레젠터/오버뷰/fragment 없음)
  - ref 모드 = sticky nav + 전체 refBody + GLOSSARY 롱스크롤
- **env-toggle** (dev/staging/prod) → `heroHTML(env)` 재렌더
- **인터랙티브 토폴로지**: SVG 노드 클릭 → `#detail` 패널 (역할·`tfFile`·`verifyCmd`="접속 확인")
- 챕터 7개: 1.개념워밍업 2.전체그림 3.기본세팅 4.인프라구성요소 5.배포방식 6.환경승급 7.운영·보안·비용
- 각 챕터 본문 = `slideBody`(1줄) + `refBody`(1단락) — **얇음**

## 3. 진단된 갭 (왜 보강하는가)

1. **"AWS 최초 설정"이 1단락으로 압축됨** — 계정/IAM/OIDC/도구/tfvars/state backend의 단계감 부재.
   실제 절차는 `runbooks/step1~3`에 상세히 있으나 가이드에 반영 안 됨.
2. **"배포 완료 후 확인/검증" 전용 챕터가 없음** (헤드라인 갭) — ArgoCD Synced/Healthy, `kubectl get
   pods`, `terraform output` 엔드포인트, ALB DNS→/healthz→/api E2E, Grafana/Prometheus/Loki/알람
   검증이 전부 빠짐. 근거는 `step8-observability.md` + `outputs.tf` + 노드별 `verifyCmd`에 존재.
3. **자체 slide 렌더러 ≠ web-presentation 엔진** — 키보드 네비·프레젠터·오버뷰·fragment 순차등장·
   코드 줄 하이라이트·진행바 없음. 발표 품질이 스킬 수준에 못 미침.
4. **트러블슈팅이 흩어져 있음** — `step3`, `troubleshooting-infra.md`에 실제 발생 케이스(Free Tier,
   MSK subscription, OpenSearch SLR, state lock, EIP 한도)가 있으나 가이드에 인덱스가 없음.

## 4. 전제 검증 (premise challenge)

1. **단일 자기완결 HTML, file:// 더블클릭 동작 유지** — 동의 필요. (DESIGN.md 잠금: 외부파일/CDN 금지,
   폰트 base64 임베드 유지)
2. **콘텐츠 소스는 기존 runbooks** — 새로 쓰지 않고 `step1~12` + `troubleshooting-infra` +
   `outputs.tf`에서 발췌·압축. 코드블록은 **PowerShell**(runbook이 PowerShell 기준).
3. **web-presentation의 라이트 테마(T키)는 드롭** — DESIGN.md "다크 전용(의도적 결정)"과 충돌.
   T키 비활성 또는 제거. (이 한 항목만 스킬 체크리스트에서 의도적 미적용)
4. **960×540 고정 캔버스는 slide 모드에만 적용** — 밀집 토폴로지·340px detail 패널·검색형 레퍼런스는
   풀블리드가 가치이므로 **ref 모드는 캔버스 제약에서 제외**(현행 그리드 유지).

## 5. 엔진 통합 설계 (기술 핵심)

이 작업의 난이도는 전부 여기 있다.

### 5.1 렌더 흐름 변경
- **as-is**: `showSlide`가 `#stage.innerHTML`을 매번 교체 (단일 슬라이드만 DOM 존재)
- **to-be**: 페이지 로드 시 `SYSTEM.chapters`를 순회하여 **모든 슬라이드를 `<section class="slide">`로
  `.slides` 컨테이너에 사전 렌더** → web-presentation `showSlide(index)`(View Transitions + 입력잠금)가
  구동. 즉 **데이터 구동 유지 + 풀 엔진 획득**.

### 5.2 채택할 web-presentation 모듈 (15개 중)
- 뷰포트 스케일링(960×540), Fragment 자동 순차(`data-step`), 슬라이드 전환(View Transitions+폴백),
  키보드 네비, 터치/스와이프, URL hash(`#slide-N`), 프로그레스바+카운터, 코드 줄 하이라이트
  (`data-highlight-steps`), 오버뷰(O), 노트 패널(N), 자동재생(P), 프레젠터 뷰(S), 입력잠금(isAnimating+
  setTimeout 안전장치), ARIA/`inert`, `@media print`, `:focus-visible`
- **미적용**: 라이트 테마(T) — DESIGN.md 다크 전용

### 5.3 듀얼 모드 보존
- `#mode-btn`: **slide(캐러셀, 1차) ↔ ref(롱스크롤 카탈로그)**. A+B의 핵심 — 캐러셀이 발표,
  ref가 레퍼런스.
- `#detail` 노드 상세는 두 모드 공통 오버레이로 동작.

### 5.4 env-toggle 연동
- env 변경 시 사전 렌더된 슬라이드 중 `hero-host`/검증 명령 영역만 `heroHTML(env)`·env별 값으로
  부분 재렌더 (전체 캐러셀 재생성 금지 — 현재 SLIDE 인덱스 유지).

### 5.5 디자인 토큰 매핑 (web-presentation → DESIGN.md)
| web-presentation | DESIGN.md | 비고 |
|---|---|---|
| `--color-bg #0f0f23` | `--bg #0e1116` | |
| `--color-surface` | `--panel #161b22` / `--surface-2 #21262d` | |
| `--color-primary #4fc3f7` | `--accent #bc8cff` | 헤더/진행바/포커스 = 브랜드 퍼플 |
| `--color-success/danger` | `--store #3fb950` / `--danger #f85149` | 의미색 잠금 재사용 |
| tag/callout/compare 색 | `--rest/--kafka/--store/--danger/--accent` | 색=기능, 임의 재도색 금지 |
| `--font-sans` Noto Sans KR | `--sans` (Geist+Pretendard 폴백) | |
| `--font-mono` Fira Code | `--mono` Geist Mono | |
| 폰트 로딩 | **base64 data-URI 임베드** | 웹폰트 금지(file:// CORS), 현행 유지 |

## 6. 콘텐츠 계획 — 시간축 런북형 (구조 A)

각 챕터는 web-presentation 컴포넌트(fragment 단계, code-block, callout, compare-grid, diagram,
`data-highlight-steps`)로 구성. 소스 runbook 명시.

| # | 챕터 | 핵심 슬라이드(요지) | 소스 |
|---|------|------|------|
| 0 | 타이틀 | 제목 + env 배지 + 한 줄 가치 | meta |
| 1 | 개념 워밍업 | 7단어 glossary (EKS·ECR·ALB·RDS·MSK·IRSA·ArgoCD) | 기존 warmup |
| 2 | 전체 그림 | hero 토폴로지 + **두 흐름**(배포 파이프라인 vs 트래픽 경로) | 기존 big-picture |
| 3 | 사전 준비 | IAM(`synapse-admin`+AdministratorAccess)·OIDC·도구(aws/terraform/kubectl/helm)·tfvars | step1, step2 |
| 4 | **인프라 프로비저닝** (대폭 신설) | 4.1 state backend 수동(S3+DynamoDB, chicken-egg) · 4.2 init→plan(`destroy:0` 확인)→apply(순서 vpc→eks→data→addons→irsa, 20~25분, `data-highlight-steps`) · 4.3 완료 신호(`Apply complete`+outputs) · 4.4 자주 막히는 곳(Free Tier·MSK subscription·OpenSearch SLR·state lock·EIP) | step3, troubleshooting-infra |
| 5 | 앱 배포 | dev overlay → ESO 시크릿 → ECR 이미지 → ApplicationSet(7×3 matrix) → image-updater → ArgoCD sync | step4, step5, step6 |
| 6 | **★ 배포 확인·검증** (신설, 헤드라인) | 6.1 인프라(`terraform output`: rds_endpoint·msk_bootstrap_brokers_tls·eks_cluster_endpoint, `kubectl get nodes`) · 6.2 ArgoCD(10 App Synced+Healthy, UI 접속) · 6.3 워크로드(`kubectl get pods -n synapse-dev` Running, 노드별 `verifyCmd`) · 6.4 트래픽(ALB DNS→/healthz→/api E2E, gateway /api vs catch-all) · 6.5 관측(Grafana 로그인, Prometheus targets UP, Loki 조회, `vector(1)` 알람 테스트) · 6.6 검증 체크리스트(compare-grid 정상/비정상) | step8, outputs.tf, argocd-ui-access, 노드 verifyCmd |
| 7 | 환경 승급 | dev(auto)→staging(auto)→prod(**수동 승인 게이트**: OutOfSync 대기→gitops-admin sync) + prod 하드닝(NetworkPolicy/HPA/non-root/Multi-AZ) | step7, step9, dev-to-staging-promotion |
| 8 | 운영·보안·비용 | Velero 백업/복구 · ESO 시크릿 · 롤백 · 월 $200 상한 · `terraform destroy` + orphan 정리 | step10, step11, step12 |
| 9 | **트러블슈팅** (신설) | provisioning/deploy/verify별 자주 막히는 지점 인덱스 + bastion SSM 접속 | troubleshooting-infra, bastion-ssm-access |
| — | (공통) 인터랙티브 토폴로지 슬라이드 + 레퍼런스 모드 카탈로그(refBody 전체 + GLOSSARY + outputs 카탈로그) | | SYSTEM |

오버플로 규칙: 슬라이드당 코드 15줄·리스트 6~8개·콘텐츠 460px. 밀집 챕터(특히 4)는 `two-columns`로
수직 절약 또는 슬라이드 분할. 깊은 내용은 ref 모드로 위임.

## 7. 데이터 모델 변경 (`SYSTEM`)

- `chapters[]` 확장: 기존 `slideBody`(1줄) → `slides: [{ title, steps:[...fragment], code?, highlight?,
  callout?, compare?, visual? }]`. `refBody`는 ref 모드용으로 유지.
- `verify` 블록 신설: 6장 검증 명령을 env별로 그룹화 (`outputs.tf` 출력명 + step8 체크리스트 발췌).
- `topology.nodes`: 기존 `tfFile`/`verifyCmd`/role 재사용 (6.3 + detail 패널).
- `meta` 불변.

## 8. 구현 단계 (실행 시)

1. 토큰 정합 레이어: web-presentation CSS 아키텍처를 DESIGN.md 변수로 오버라이드. 다크 전용·base64 폰트 확인.
2. 엔진 스왑: web-presentation JS 엔진을 slide 모드 구동기로 통합. `SYSTEM.chapters` → `.slides`에 전 슬라이드 사전 렌더.
3. ref 모드 렌더러 + `#mode-btn` 유지. env-toggle이 활성 슬라이드 hero/검증값 부분 재렌더.
4. `SYSTEM.chapters`를 시간축 구조로 재작성 + `slides[]` + `verify` 데이터를 runbook에서 발췌.
5. 6장(검증) · 9장(트러블슈팅) 신설.
6. 인터랙티브 토폴로지를 해당 슬라이드에 임베드. 노드 클릭 detail이 양 모드에서 동작.
7. QA: `counterTotal`==실제 슬라이드 수 · 460px 오버플로 · file:// 더블클릭 · 전 슬라이드 env-toggle · `@media print` · a11y · 한글 폴백 캔버스 오버플로.
8. 메모리 `aws-deploy-guide.md` 갱신(아키텍처 변경 반영 — 기존 "SYSTEM만 갱신" 패턴이 깨짐).

## 9. 위험

- **캔버스 460px vs 밀집 콘텐츠** (최대 위험): 특히 4장(state backend+apply+트러블슈팅)이 슬라이드 폭발 가능 → two-columns/분할/ref 위임으로 완화.
- **960×540 안의 토폴로지**: 다운스케일 시 가독성 → 전체 맵은 ref 모드 풀블리드로 제공.
- **엔진 통합 복잡도**: 15모듈 + 데이터구동 렌더 + 듀얼모드 + env-toggle 병합이 L 난이도.
- **라이트 테마 충돌**: T키 드롭으로 해소(전제 4.3).
- **파일 크기 증가**: base64 폰트(~190KB)+콘텐츠+엔진 JS. 여전히 자기완결, 허용.

## 10. 노력 추정

전체 **M~L**. 엔진 정합/스왑 = L. 콘텐츠 보강 = M(소스 존재, runbook 발췌). 토큰 매핑 = S.

## 11. The Assignment (다음 한 가지 — 빌드 전 검증)

**가장 큰 미지(캔버스 적합도)를 먼저 깬다.** 풀 엔진 스왑에 착수하기 전에, 가장 밀집한 **4장(인프라
프로비저닝: state backend + init/plan/apply + 트러블슈팅)** 하나만 web-presentation 슬라이드로
960×540에 손으로 목업한다. 이 챕터가 **≤5 슬라이드**로 깔끔히 들어가면 덱 전체가 성립한다. 폭발하면
밀집 챕터에 한해 3-액트 압축(D2의 B안)으로 재고한다. 한 챕터 목업이 통합 난이도(엔진+데이터+캔버스)를
가장 정직하게 노출한다.

---

## 부록: 확인된 레포 자산

- 콘텐츠 소스: `docs/runbooks/step1~12-*.md`, `troubleshooting-infra.md`, `argocd-ui-access.md`, `bastion-ssm-access.md`, `dev-to-staging-promotion.md`
- 검증 근거: `infra/aws/dev/outputs.tf` (vpc/eks/rds/msk/redis/bastion/velero 엔드포인트), 노드 `verifyCmd`
- argocd: `applicationset{,-staging,-prod}.yaml`, `image-updater.yaml`, `projects.yaml`
- 디자인 정본: `DESIGN.md`
