# #126 main-protection bypass — 옵션 분석 (결정 메모)

> 작성: 2026-06-08 (W5 Day1) · 성격: **분석·권고**(결정은 팀). 이슈 #126.
> 결정 사항이 아니라 의사결정 입력이다 — bypass 유지/축소/전환 중 팀이 선택.

## 배경

`main-protection` ruleset(ID 17307721)에 **RepositoryRole=Maintain(always)** bypass가 추가돼 있다(2026-06-05, gateway 배포 복구 중). 보존 규칙: 브랜치 삭제·force-push 금지, required check `validate`(strict), PR 요구.

**왜 있나:** shared `deploy-service.yml`(전 서비스 공용 reusable deploy)이 빌드 후 `GITOPS_TOKEN`으로 이 레포 main에 **직접 push**(`deploy: bump <app> to <sha>`)한다. bypass 없으면 `GH013`(push declined)로 배포 실패.

**현재 bypass 소비자:** `deploy-service.yml` **단 하나**. (ArgoCD Image Updater는 PR write-back으로 전환됨 — PR #127, bypass 불필요.)

**문제:** Maintain(always)는 **자동화 봇뿐 아니라 모든 Maintainer 이상 인간**의 PR·검사 우회 직접 push를 허용 — 최소권한 원칙 위반. 거버넌스 리스크.

## 옵션 비교

| # | 옵션 | 거버넌스 | 배포 지연 | 작업량 | blast radius |
|---|------|---------|----------|--------|--------------|
| 1 | **현상 유지**(Maintain always) | ✗ 인간 우회 허용 | 없음 | 0 | gitops |
| 2 | bypass를 **Admin**으로 축소 | △ 여전히 역할기반 인간 우회 | 없음 | 소(ruleset 1줄) | gitops |
| 3 | **전용 자동화 ID**(GitHub App/머신계정)만 bypass | ✓ 인간 우회 차단, 봇만 | 없음 | 중(App 생성+토큰 회전) | gitops |
| 4 | deploy-service.yml **PR write-back 전환** | ✓✓ bypass 0(전부 PR+검사) | 있음(PR 사이클) | 대(shared 수정) | **전 서비스** |

### 각 옵션 상세

**1. 현상 유지** — 즉시·무변경이나 #126이 제기한 리스크(인간 우회) 그대로. 권장 안 함(최소한 2~3으로).

**2. Admin 축소** — ruleset bypass_actors를 Admin으로 변경. Maintainer 우회는 막으나 Admin은 여전히 우회. GITOPS_TOKEN 소유자가 Admin 권한이어야 동작. 역할기반이라 "특정 봇만"이 아님 — 부분 개선.

**3. 전용 자동화 ID (권장)** — GitHub App(또는 머신계정)을 만들고 ruleset bypass_actors에 **그 App만** 등록. `GITOPS_TOKEN`을 App 설치토큰/머신계정 PAT로 회전. 결과: **인간은 역할 무관 전부 PR**, 배포 자동화만 직접 push. 배포 지연 0. GitHub ruleset은 App을 bypass actor로 지원. 작업 = App 생성·권한(contents:write)·shared 시크릿 회전. **거버넌스 대비 비용 최적.**

**4. PR write-back 전환 (이상적 종착)** — image-updater(#127)처럼 deploy-service.yml이 `deploy/<app>` 브랜치 push→PR→(auto)merge. bypass **완전 제거** = 모든 변경 PR+검사. 단 ① 배포 지연(PR 사이클) ② `deploy-service.yml`은 **shared 소속·전 서비스 공용** → 변경이 모든 서비스 배포에 영향(크로스레포 조율+리스크) ③ auto-merge 설정 복잡. 효과는 최상이나 비용·blast radius 큼.

## 권고

- **단기(저비용)**: **옵션 3** — 전용 자동화 ID로 bypass를 봇 한정. 인간 우회 리스크(#126 핵심)를 배포 지연·크로스레포 변경 없이 제거.
- **장기(이상)**: **옵션 4** — 팀이 배포 지연을 수용하고 shared 차원 표준화를 원하면 PR write-back으로 bypass 0. image-updater가 이미 그 경로라 패턴 재사용 가능.
- **비권장**: 옵션 1(현상 유지), 옵션 2(부분 개선에 그침).

> 결정 주체 = 팀(특히 shared `deploy-service.yml` 소유자). 옵션 3/4는 shared·org 시크릿(GITOPS_TOKEN) 변경을 수반하므로 단독 진행 불가. 본 메모는 #126 코멘트로 공유.

## 연계
- 이슈 #126(OPEN, 결정 대기) · image-updater PR write-back 선례 PR #127 · shared `deploy-service.yml`.
