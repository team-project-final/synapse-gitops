# W5 진입 차단 클리어 — 실행 런북

대상: #91 #92 #120 #121 #122 / 통보 허브: synapse-shared#20
원칙: Phase 0는 무비용(사전 머지). Phase 1 진입 시 과금 ON → Phase 4 destroy로 차단.

## Phase 0 — 사전 (window 전, main 머지 완료)
- [ ] nip.io ingress 2종 + gen-nipio-selfsigned.sh + README 머지
- [ ] kafka-topics/k8s-kafka-config .terraform.lock.hcl 커밋
- [ ] Image Updater annotation 6종 확인 (`grep -c ... argocd/applicationset.yaml` == 6)
- [ ] ACM import IAM 권한 + 리전(ap-northeast-2) 사전 점검

## Phase 1 — apply + 부트스트랩 (과금 ON)
- [ ] `bash scripts/bring-up.sh` (terraform apply → ArgoCD HA+ESO+ApplicationSet, dev auto-sync)
- [ ] bastion에서 `terraform -chdir=infra/aws/dev/kafka-topics apply` (MSK TLS provider)
- [ ] `kubectl get applications -n argocd` 으로 App 등록 확인

## Phase 2 — 핵심 검증 (bastion SSM, 병렬 가능)
### #91/#92
- [ ] (team-lead) `bash scripts/verify-argocd-deploy.sh synapse-dev` → 15/15 ALL PASSED
- [ ] (team-lead) staging 수동 sync: `argocd app sync synapse-<svc>-staging` (5개)
- [ ] (team-lead) `bash scripts/verify-argocd-deploy.sh synapse-staging` → 5/5 (platform-svc 포함)
- [ ] 롤백 1회: `kubectl -n synapse-dev rollout undo deploy/<svc>` → 복구 <3분
### #120
- [ ] 토픽 생성 확인: `kafka-topics.sh --bootstrap-server <MSK_TLS> --command-config tls.properties --list`
- [ ] ACL 확인: `kafka-acls.sh --bootstrap-server <MSK_TLS> --command-config tls.properties --list`
- [ ] TLS 핸드셰이크: `openssl s_client -connect <MSK_BROKER>:9094 -servername <broker>` → 인증서 체인 확인
- [ ] produce/consume: `kafka-console-producer/consumer` 로 토픽 송수신 통과
### #122
- [ ] ECR에 새 semver 태그 푸시(5개 앱 중 대상) → Image Updater git write-back 확인
- [ ] 푸시→dev 반영 평균 시간 측정 → ≤5분
- [ ] 롤백: write-back 커밋 revert(또는 이전 태그) → 이전 이미지 복귀 확인

## Phase 3 — #121 외부 노출 (ALB 의존)
- [ ] nip.io ingress 2종 apply (cert-arn 미설정 → ALB 프로비저닝)
- [ ] `kubectl get ingress -A` 에서 공유 ALB DNS 확보
- [ ] `bash scripts/gen-nipio-selfsigned.sh <ALB_DNS>` → `CERT_ARN=...`
- [ ] ingress의 `<ALB_IP>`·`<ACM_ARN>` 치환 후 재apply
- [ ] `curl --cacert .nipio-certs/ca.crt https://argocd.<IP>.nip.io` → 200 + 체인 유효
- [ ] `curl --cacert .nipio-certs/ca.crt https://dev.<IP>.nip.io/actuator/health` → gateway 도달
- [ ] GitHub webhook ping → argocd `/api/webhook` → 200 도달

## Phase 4 — 정리
- [ ] 5 이슈 DoD 결과를 synapse-shared#20 에 코멘트 (이슈별)
- [ ] #92 해소 시 #91과 동반 클로즈
- [ ] `bash scripts/bring-up.sh --destroy` (terraform destroy, 과금 차단)
- [ ] destroy 후 `terraform -chdir=infra/aws/dev show` 빈 상태 확인
