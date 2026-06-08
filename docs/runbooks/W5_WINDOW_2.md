# W5 검증 윈도우 2 — 실행 런북

대상: #91 #92 #121 #122 + Step 11 라이브 항목 / 통보 허브: synapse-shared#20
원칙: Phase 0는 무비용(윈도우 전). Phase 1 진입 시 과금 ON → Phase 6 destroy로 차단.
선행: 윈도우 1 결과(`W5_CLEARANCE_WINDOW.md`, 2026-06-05) — #120 close, #121/#122 코드 머지(PR #124), IU PR write-back 전환(PR #127). + PR #136(서비스별 DB 분리 + gateway JWT_PUBLIC_KEY, 2026-06-08) — #92 근본원인(공유 flyway_schema_history) 해소.

## Phase 0 — 선결 조건 확인 (무비용, 윈도우 전)

- [ ] gateway ECR 이미지 존재: `aws ecr describe-images --repository-name synapse/gateway --query 'imageDetails[].imageTags' --region ap-northeast-2`
- [ ] gateway SM 시크릿 시드 2종: `synapse/dev/gateway/redis-password` + `synapse/dev/gateway/jwt-public-key` (PR #136 ExternalSecret 매핑 — 미시드 시 JwtDecoderConfig fail-fast CrashLoop)
- [ ] RDS 서비스별 DB 5종 존재: `synapse_platform`/`synapse_engagement`/`synapse_knowledge`/`synapse_learning`/`synapse_ai` (PR #136 전제, psql `\l` 로 확인)
- [ ] platform-svc dev-latest 재빌드 확인: ECR `imagePushedAt` > PR #136 머지 시각
- [ ] frontend ECR 이미지 존재 (06-07 bump 3건 — 형식적 재확인)
- [ ] `GITOPS_TOKEN` 시크릿 유효 (repo Settings → Secrets, IU PR write-back 필수)
- [ ] ACM import IAM 권한 + 리전(ap-northeast-2) 점검 (윈도우 1과 동일)
- [ ] team-lead 일정 협의 — Phase 5 따라하기 검증 (불가 시 폴백: 비동기 후속)
- [ ] sim 브랜치 준비: `git checkout -b sim/incident-window2 origin/main` → `apps/engagement-svc/overlays/staging/kustomization.yaml` 의 namespace를 `synapse-sim` 으로 변경 후 push (main 머지 금지)

## Phase 1 — bring-up (과금 ON)

- [ ] `bash scripts/bring-up.sh` — alb-controller·image-updater 페이즈 포함 (PR #124 경로 **첫 라이브 검증**)
- [ ] ALB 컨트롤러 기동: `kubectl get deploy -n kube-system aws-load-balancer-controller` → Available
- [ ] IU ECR 자격: `kubectl logs -n argocd deploy/argocd-image-updater | grep -i "basic auth"` → 에러 없음
- [ ] `kubectl get applications -n argocd` — dev 7 + staging 7 + prod 7 등록 확인

## Phase 2 — #91/#92 fleet 검증

- [ ] (team-lead) `bash scripts/verify-argocd-deploy.sh synapse-dev` (스크립트는 **synapse-shared 레포**) → **7앱 ALL PASSED** (5svc+gateway+frontend)
- [ ] gateway-dev 기동 확인 — 윈도우 1 갭(ECR·SM 2종) 해소 검증 (gateway#4)
- [ ] platform-svc-dev 기동 확인 — flyway checksum 충돌 없음 (PR #136 DB 분리 효과)
- [ ] staging sync 확인 (auto) → `bash scripts/verify-argocd-deploy.sh synapse-staging` (synapse-shared 레포) → **7앱** (5svc+frontend+schema-registry)
- [ ] platform-svc-staging Running (= #92 해소: 서비스별 DB 분리로 flyway 충돌 제거, PR #136)
- [ ] 롤백 1회: `kubectl -n synapse-dev rollout undo deploy/<svc>` → 복구 <3분
- [ ] → #91·#92 close (결과 코멘트)

## Phase 3 — #121 외부 노출 완주 (ALB 의존 · Phase 4와 병행 가능)

- [ ] nip.io ingress 2종 apply (cert-arn 미설정 → ALB 프로비저닝 트리거)
- [ ] `kubectl get ingress -A` → 공유 ALB DNS 확보 (group.name=synapse-nipio)
- [ ] `bash scripts/gen-nipio-selfsigned.sh <ALB_DNS>` → `CERT_ARN=...`
- [ ] ingress `<ALB_IP>`·`<ACM_ARN>` 치환 → 재apply
- [ ] `curl --cacert .nipio-certs/ca.crt https://argocd.<IP>.nip.io` → 200 + 체인 유효
- [ ] `curl --cacert .nipio-certs/ca.crt https://dev.<IP>.nip.io/actuator/health` → gateway 도달
- [ ] GitHub webhook ping → `/api/webhook` 200
- [ ] → #121 close

## Phase 4 — #122 IU write-back E2E (Phase 3과 병행 가능)

- [ ] 대상 svc의 ECR에 새 태그 푸시 (IU 전략에 맞춰 — 기존 매니페스트 재태그):
  ```bash
  MANIFEST=$(aws ecr batch-get-image --repository-name synapse/<svc> --image-ids imageTag=dev-latest --query 'images[0].imageManifest' --output text)
  aws ecr put-image --repository-name synapse/<svc> --image-tag <new-tag> --image-manifest "$MANIFEST"
  ```
- [ ] IU 감지 → `image-updater-<svc>` 브랜치 push 확인: `git ls-remote origin 'image-updater-*'`
- [ ] `image-updater-pr.yml` 이 PR 자동 생성 (#127 경로 **첫 라이브 검증**): `gh pr list --head image-updater-<svc>`
- [ ] PR 머지 → dev 반영 시간 측정 (푸시→Pod 교체) → **≤5분** 기록
- [ ] 롤백: write-back 커밋 revert PR → 이전 태그 복귀 확인
- [ ] → #122 close

## Phase 5 — Step 11 라이브 항목 (Phase 2 완료 후)

> 시뮬레이션은 **전용 sim Application** — staging은 selfHeal=true라 직접 주입 불가(즉시 원복). fleet 무접촉.

- [ ] 스냅샷: `kubectl get pods -n synapse-staging -o wide > /tmp/staging-before.txt`
- [ ] sim 앱 생성 (manual sync — selfHeal 없음). 전제: `argocd login` 또는 `--core` 모드 (`docs/runbooks/argocd-ui-access.md` 참고):
  ```bash
  argocd app create incident-sim \
    --repo https://github.com/team-project-final/synapse-gitops \
    --revision sim/incident-window2 \
    --path apps/engagement-svc/overlays/staging \
    --dest-server https://kubernetes.default.svc --dest-namespace synapse-sim \
    --sync-option CreateNamespace=true
  argocd app sync incident-sim   # 기동 확인 (Java svc — ESO/RDS/MSK 실의존 동작)
  ```
- [ ] **시나리오 1 CrashLoop**: `kubectl set env deploy/engagement-svc -n synapse-sim SPRING_DATASOURCE_URL=jdbc:broken` → `docs/runbooks/incidents/pod-crashloop.md` 따라 진단 → 원복: `argocd app sync incident-sim` (git 상태로 복원 — set env 해제 불필요, sync가 덮어씀)
- [ ] **시나리오 2 OOM**: limit 10Mi 패치 → `docs/runbooks/incidents/oom-killed.md` 따라 진단 → `argocd app sync incident-sim` 으로 원복
  ```bash
  kubectl patch deploy engagement-svc -n synapse-sim --type=json \
    -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"10Mi"}]'
  ```
- [ ] **시나리오 3 sync 실패**: sim 브랜치에 존재하지 않는 리소스 참조 커밋 push → `argocd app sync incident-sim` Failed → `docs/runbooks/incidents/argocd-sync-failed.md` 따라 진단 → revert push → sync OK
- [ ] **team-lead 따라하기**: 시나리오 1택 재현 → team-lead가 런북만 보고 독립 복구 (1회 통과 = Step 11 검증 완료. 당일 불가 시: 비동기 후속으로 분리 기록)
- [ ] **알람 경로 테스트**: `docs/runbooks/on-call.md` 절차 (amtool warning) → Slack `#synapse-gitops` 수신 확인
- [ ] 정리: `argocd app delete incident-sim --yes` → `kubectl delete ns synapse-sim` → `git push origin --delete sim/incident-window2`
- [ ] fleet 무접촉 확인: `diff /tmp/staging-before.txt <(kubectl get pods -n synapse-staging -o wide)`

## Phase 6 — 마감

- [ ] 이슈별 결과 코멘트: #91 #92 #121 #122 (+close), gateway#4 결과 통보
- [ ] synapse-shared#20 통보 코멘트
- [ ] `TASK_gitops.md` Step 11 라이브 항목 체크 + `HISTORY_gitops.md` 윈도우 2 기록
- [ ] `bash scripts/bring-up.sh --destroy` → `terraform -chdir=infra/aws/dev show` 빈 상태 확인
