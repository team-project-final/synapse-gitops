# AWS 배포 가이드 — 단일 HTML 발표/레퍼런스 문서 설계

> **작성일**: 2026-06-07
> **산출물**: `docs/aws-deploy-guide.html` (단일 자기완결 HTML)
> **대상 독자**: AWS 입문 백엔드 개발자(팀원)
> **정본 디자인**: `DESIGN.md` (다크 전용, Geist/Geist Mono base64 임베드, 색 의미 잠금)
> **스타일 레퍼런스**: 기존 `docs/local-k8s-guide.html` (SYSTEM 객체 구동 동일 계열)

---

## 1. 목적 & 성공 기준

AWS를 처음 접하는 백엔드 개발자가, Synapse 서비스가 AWS에서 **어떻게 배포되고 동작하는지**를 기본 세팅부터 환경 승급까지 한 문서로 이해하게 한다.

### 성공 기준
- `file://` 더블클릭으로 열어 폰트가 **폴백 없이** 로드되고 콘솔 에러 0.
- 기본 진입 시 **발표 모드**, 버튼 한 번으로 **스크롤 레퍼런스 모드** 전환.
- 히어로 토폴로지 맵에서 **dev/staging/prod 토글** 시 구성이 애니메이션으로 변함.
- 모든 인프라 노드 클릭 시 역할·terraform 근거·접속 확인 명령이 표시됨.
- 문서의 스펙/명령/구조가 실제 `infra/aws/dev/*.tf` · `argocd/*.yaml` · `runbooks/*`와 일치.

### 비목표 (YAGNI)
라이트 모드 · 실시간 AWS API 연동 · 빌드 도구/번들러 · 한글 웹폰트 임베드(시스템 폴백 사용) · 실제 비밀값/계정 ID 포함(모두 placeholder).

---

## 2. 형식 결정 (브레인스토밍 합의)

| 항목 | 결정 |
|---|---|
| 문서 형식 | 하이브리드 — **기본 발표(슬라이드) 모드**, 버튼으로 스크롤 레퍼런스 전환 |
| 대상 수준 | AWS 입문 백엔드 개발자 (기본 개념부터, "왜 이 구조인가" 원리 중심) |
| 커버 범위 | dev → staging → prod 전체 승급 흐름 |
| 히어로 시각 | 새 AWS 토폴로지 맵 (환경 토글 시 구성 변화 애니메이션) |
| 내러티브 | A안 여정형(Journey) — 생애주기 한 줄기 스토리 |

---

## 3. 아키텍처

### 3.1 단일 파일 자기완결
- 외부 의존 0. Geist/Geist Mono woff2 라틴 서브셋을 `@font-face src:url(data:font/woff2;base64,...)`로 임베드. **CDN/외부 woff2 상대참조 금지** (Chrome `file://` unique origin 차단 회피).
- 폰트 base64 6블록과 `:root` 디자인 토큰은 `local-k8s-guide.html`에서 **그대로 복사 재사용**(190KB 재생성 금지).

### 3.2 단일 데이터 출처 — `SYSTEM` 객체
모든 콘텐츠를 전역 데이터 객체 하나로 보유. 렌더러가 이를 읽어 DOM을 생성한다. 인프라가 바뀌면 데이터만 수정.

```
SYSTEM = {
  meta:        { title, subtitle, env 기본값 },
  envs:        { dev|staging|prod: { eksNodes, mskBrokers, multiAZ, sync, hardening[] } },
  topology:    { nodes:[{id,label,kind,env가시성,color,tfFile,role,verifyCmd,detail}],
                 edges:[{from,to,kind: rest|kafka|store|route}] },
  chapters:    [{id,title,slideBody,refBody,visual}],  // 7개 섹션
  glossary:    [{term,oneLiner,whyWeUse}]               // 개념 워밍업/검색용
}
```

두 모드(발표/레퍼런스)는 **동일 `SYSTEM`을 공유** — 콘텐츠 중복 없음, 토글은 레이아웃만 전환.

### 3.3 모듈 경계
- **데이터(`SYSTEM`)**: 순수 콘텐츠. 렌더링 로직 없음.
- **토폴로지 렌더러**: `SYSTEM.topology` + 현재 env → SVG 맵 생성/갱신. 입력=데이터+env, 출력=SVG. 다른 모듈을 모름.
- **챕터 렌더러**: `SYSTEM.chapters` → 발표 슬라이드 또는 레퍼런스 스크롤 섹션. 모드 플래그를 입력받음.
- **모드 컨트롤러**: 발표↔레퍼런스 전환, 키보드(←/→/Space), URL 해시 동기화.
- **상세 패널**: 노드 클릭 시 `node.detail` 표시. 토폴로지 렌더러가 이벤트만 위임.

각 모듈은 `SYSTEM`을 읽기만 하고 서로의 내부를 모른다 → 독립 이해/수정 가능.

---

## 4. 히어로: AWS 토폴로지 맵

- 손으로 그린 SVG: **인터넷 → ALB → gateway(단일 진입점) → EKS(백엔드 5 svc + frontend SPA + 클러스터 내 Elasticsearch StatefulSet) → AWS 관리형 서비스(RDS·MSK+Schema Registry·ElastiCache Redis) → ECR·ArgoCD → bastion·Velero**.
- **진입/라우팅(2026-06-07 반영)**: gateway가 ALB 뒤 단일 진입점. `/api/**` → 백엔드 서비스(JWT 인증 필수, route 색 퍼플), **catch-all(non-/api) → frontend**(Flutter web/nginx :80, 공개 — SPA 셸·정적 자산·딥링크). 근거: gateway `RoutesConfig.java`(catch-all `Ordered.LOWEST_PRECEDENCE`, `FRONTEND_SVC_URI`) · `SecurityConfig.java`.
- 검색은 AWS 관리형(OpenSearch)이 아니라 **EKS 위 Elasticsearch StatefulSet**(`apps/elasticsearch`)으로 자체 호스팅됨에 유의 — 토폴로지에서 관리형 박스가 아닌 EKS 내부 노드로 표현.
- 상단 **dev / staging / prod 세그먼트 토글**. 전환 시 300ms 애니메이션으로 변화:
  - EKS 노드 수, MSK broker 수
  - Multi-AZ 유무 배지
  - sync 정책 배지(dev=auto / staging·prod=manual)
  - 하드닝 배지(NetworkPolicy · HPA · non-root · Multi-AZ)
- 엣지 색 = 의미 잠금: REST=`--rest` 파랑, Kafka=`--kafka` 앰버, store=`--store` 초록, route=`--accent` 퍼플.
- 노드 클릭 → 상세 패널: 역할 / dev 스펙 / 핵심 설정 / terraform 파일 / 접속 확인 명령.

---

## 5. 섹션 구성 (A안 여정형, 실제 repo 근거)

1. **AWS 개념 워밍업** — VPC·서브넷·보안그룹·IAM·IRSA·EKS·관리형 서비스를 입문자용 1줄 비유 + "우리는 왜 쓰나". (`SYSTEM.glossary`)
2. **전체 그림** — 히어로 맵 + GitOps 한 줄 흐름: `dev/GHA → docker build → ECR push → gitops 이미지 태그 업데이트 → ArgoCD → EKS`. 사용자 트래픽 경로(ALB → gateway → /api 백엔드 / catch-all frontend)도 함께 표시.
3. **기본 세팅** — 근거: `runbooks/step1-aws-account-setup.md`, `superpowers/plans/2026-05-14-aws-infra-terraform.md`. 계정/OIDC → Terraform 적용 순서(vpc → eks → rds/msk/redis → addons → irsa).
4. **인프라 구성요소** — 근거: `infra/aws/dev/*.tf`. 카드: EKS(`eks.tf`) · RDS PG16(`rds.tf`) · MSK+Schema Registry(`msk.tf`) · ElastiCache Redis(`redis.tf`) · ECR · ACM(`acm.tf`) · ALB IRSA(`alb-controller-irsa.tf`) · ESO IRSA(`eso-irsa.tf`) · image-updater IRSA(`image-updater-irsa.tf`) · bastion(`bastion.tf`) · Velero(`velero.tf`). 검색은 AWS 관리형이 아닌 **클러스터 내 Elasticsearch StatefulSet**(`apps/elasticsearch/base/statefulset.yaml`)로 별도 카드. 각 카드: 역할 / dev 스펙 / 핵심 설정 / 접속 확인.
5. **배포가 도는 방식** — 근거: `argocd/applicationset.yaml`. 매트릭스는 이제 **7개 배포 대상**(platform/engagement/knowledge/learning-card/learning-ai 백엔드 + **gateway + frontend**) × 3 env(2026-06-07 frontend·gateway 합류). 서비스별 image-updater write-branch(`image-updater-<svc>`), `argocd/image-updater.yaml`. "커밋하면 무슨 일이 일어나는가" 시퀀스 + autoSync. frontend는 별도 레포(`synapse-frontend`)에서 Flutter web→Docker(nginx)→ECR push(#21/#22) 후 gitops 태그 bump로 배포됨.
6. **환경 승급** — 근거: `applicationset-staging.yaml` · `applicationset-prod.yaml` · `apps/*/overlays/{dev,staging,prod}`. dev(autoSync) → staging → prod(manual sync) 차이 + prod 하드닝(NetworkPolicy/HPA/non-root/Multi-AZ). 히어로 맵 토글과 연동.
7. **운영·보안·비용** — 근거: `runbooks/step11-operational-runbook.md`, `velero.tf`, `eso-irsa.tf`. Velero 백업 · ESO 시크릿 흐름 · dev 월 $200 제약 · destroy 주의.

---

## 6. 스타일 / DESIGN.md 준수

- `:root` 변수·`@font-face` base64 6블록 = `local-k8s-guide.html` 복사 재사용.
- 색 의미 잠금 준수. 서비스 식별색은 DESIGN.md 값(platform `#58a6ff`, engagement `#3fb950`, knowledge `#f778ba`, learning-ai `#e3b341`, learning-card `#ff7b72`).
- 구조 라벨(topbar/h3/h4/표헤더/푸터) = Geist Mono. 본문 = Geist 13px/1.5. 간격 = 4px 스케일 변수.
- 다크 전용. 장식 없음 — 색과 1px 보더가 일한다.

---

## 7. 모드 메커니즘

- **발표 모드(기본)**: 한 화면=한 슬라이드. ←/→/Space 이동, 진행 점·번호, 풀스크린. 히어로 맵 중심.
- **레퍼런스 모드(토글)**: 좌측 섹션 네비 + 연속 스크롤. 검색(Ctrl+K)으로 용어/리소스 점프.
- URL 해시(`#ch-eks`)로 위치 보존, 모드 전환 시에도 현재 챕터 유지.

---

## 8. 검증 계획

1. `file://` 더블클릭 → 폰트 정상 로드(폴백 아님), 콘솔 에러 0.
2. 발표↔레퍼런스 토글, 키보드 네비, env 토글 동작.
3. 모든 토폴로지 노드 클릭 → 상세 표시.
4. 문서 내 스펙/명령/구조를 `infra/aws/dev/*.tf` · `argocd/*.yaml` · `runbooks/*`와 크로스체크.
5. 실제 비밀값/계정 ID 미포함 확인(placeholder만).

---

## 9. 근거 파일 인덱스

- 인프라: `infra/aws/dev/{vpc,eks,rds,msk,redis,acm,addons,bastion,velero,eso-irsa,alb-controller-irsa,image-updater-irsa}.tf`
- 배포: `argocd/{applicationset,applicationset-staging,applicationset-prod,image-updater}.yaml`(7 대상 × 3 env), `apps/*/overlays/{dev,staging,prod}`, `apps/frontend/overlays/*`
- 진입/라우팅: `synapse-gateway` `RoutesConfig.java`·`SecurityConfig.java`(#5 JWT, #6 catch-all→frontend)
- frontend: `synapse-frontend` Flutter web Dockerize(#21)·ECR deploy CI(#22)
- 절차: `docs/runbooks/{step1-aws-account-setup,w1-argocd-bootstrap-runbook,w2-dev-deploy-runbook,step11-operational-runbook}.md`
- 기존 자산: `docs/aws-infra-provisioning-workflow-guide.md`(콘텐츠 소스), `docs/local-k8s-guide.html`(스타일/엔진 레퍼런스)
