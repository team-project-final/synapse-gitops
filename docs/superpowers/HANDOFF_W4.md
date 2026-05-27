# W4 핸드오프: synapse-gitops

> **최종 갱신**: 2026-05-27 (W3 정리·마감 완료 + W4 설계 — 세션 종료)
> **이전**: [HANDOFF_W3.md](./HANDOFF_W3.md)
> **담당**: @VelkaressiaBlutkrone

---

## 1. 이번 세션 완료 사항 (2026-05-27)

### W3 정리·마감 (비용 0 트랙)
- T1~T11 완료 (PR #59~#67) — 상세: [HANDOFF_W3 §1](./HANDOFF_W3.md), 플랜 `plans/2026-05-27-w3-consolidation.md`
  - A1 cross-repo work order(`synapse-platform-svc#37`) · A2 ESO IRSA terraform · A3 노드 3→4 · A4 staging ACM/TLS terraform · A5 image-updater A안 준비
  - C1 아티팩트 정리·가이드 안착 · C2 local-k8s README · C3 브랜치 프루닝 · C4 PM 정합
  - B1 docs-portal 콘텐츠 이미 main 안착 확인 / B2 핸드오프 허브 뷰 → W4 이월
- `feat/docs-portal-v2` 폐기 (PR #68, content superseded)

### W4 설계 (brainstorming)
- **W4 백로그** (PR #69): [`specs/2026-05-27-w4-backlog.md`](./specs/2026-05-27-w4-backlog.md)
- **W4 prod 설계** (PR #72): [`specs/2026-05-27-w4-prod-design.md`](./specs/2026-05-27-w4-prod-design.md) — brainstorming 완료, spec 커밋됨. **user-review→writing-plans 게이트는 이 핸드오프로 이관**

---

## 2. 다음 세션 시작점 (W4 실행)

1. **W4 prod 설계 spec 리뷰** — `specs/2026-05-27-w4-prod-design.md` 확인/수정 (brainstorming의 리뷰 게이트가 보류됨)
2. 리뷰 통과 시 **`superpowers:writing-plans`** 로 W4 구현 플랜 작성
   - Step 9(prod+승인게이트) / Step 10(롤백·백업) — 플랜 2단위 분리 가능(롤백/백업은 staging 독립 검증)
3. **비용 0 준비분 먼저** — prod overlay `REPLACE_ME` 치환, `synapse-prod` AppProject, `applicationset-prod.yaml`(manual), RBAC(`gitops-admin`/`prod-deployer`), Velero 버킷+IRSA terraform
4. **라이브는 조건부 단일 사이클** — W3 이월 검증(§4)과 batching, 종료 시 `terraform destroy`
5. 진입 체크리스트: [W4 백로그 §6](./specs/2026-05-27-w4-backlog.md)

---

## 3. W4 prod 핵심 결정 (확정)

| 영역 | 결정 |
|---|---|
| 격리 | 논리 분리 — dev 클러스터 내 `synapse-prod` ns. 공유 dev 데이터스토어 + DB명(`synapse_prod`)/Redis index(1) 분리. Kafka 토픽 공유는 캡스톤 한계 |
| 승인 게이트 | ArgoCD Manual Sync + RBAC. prod ApplicationSet `automated` 없음. 변경 게이트=기존 main PR 보호 |
| 권한 | ArgoCD 로컬 계정 `gitops-admin` + `role:prod-deployer`(`synapse-prod/*` sync). 일반=readonly 거부 |
| prod 이미지 | 명시적 PR 승격 (prod엔 image-updater 자동 bump 없음) |
| 롤백/백업 | GitOps 우선(ArgoCD History/git revert, DB forward-only) + Velero ns 최소(synapse-prod/staging). RTO 30m/RPO 1h |

---

## 4. 전제 · 블로커 (라이브 전 처리)

- **실 Route53 도메인** — 없으면 FR-GO-404는 port-forward 대체(A4 staging TLS와 공통 의존)
- **prod 시크릿** `synapse/prod/{app}/*` AWS SM 생성 (ESO `synapse/*` 정책이 이미 커버 — W3 A2)
- **`synapse_prod` DB** — 공유 dev RDS에 생성
- **D-039 ESO role 충돌** — `eso-irsa.tf` apply 전 `terraform import aws_iam_role.eso synapse-dev-eso-role` 또는 수동 role 삭제
- **cross-repo `synapse-platform-svc#37`** — platform-svc staging/prod 프로필 진행 확인 (5/5 차단요인)
- **Velero 전용 S3 버킷 + IRSA** — terraform 신규

---

## 5. W3 이월 라이브 검증 (W4 사이클에 batching)

코드 완료/라이브 미검증 — [W4 백로그 §2](./specs/2026-05-27-w4-backlog.md):
- A3 engagement-svc 5/5 capacity(노드4 apply) · A4 staging ACM/TLS(도메인) · A5 image-updater write-back E2E(bypass) · platform-svc staging 5/5(`#37` 도착 후)

---

## 6. 레포 상태

- **main HEAD**: `85c5afe` (PR #72 머지)
- **W4 관련 spec(main)**: `w4-backlog.md`, `w4-prod-design.md`
- **잔존 로컬 브랜치**: `docs/unified-handoff-hub-spoke`(W4 B2 핸드오프 허브 뷰 base 후보), `feat/deploy-mirror-standardization`(타 트랙 — PR #71로 main 반영됨)
- **CI**: main 보호(PR + validate/diff-comment/parse 필수, 봇 자동삭제). 브랜치는 머지 시 base 최신화 필요(`gh pr update-branch`)

---

## 7. 비용

~$0.41/hr (EKS+RDS+MSK+Redis+OpenSearch). 라이브 사이클 후 `cd infra/aws/dev && terraform destroy -auto-approve`. 유지: S3 state bucket + DynamoDB lock.
