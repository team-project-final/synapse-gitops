# infra/ingress/nipio

**임시(폐기 전제) nip.io 외부 노출** — 실 도메인 부재 시 #121 검증용. ALB + self-signed ACM import.

## 파일
- `argocd-server-ingress.yaml` — ArgoCD UI + webhook → `argocd-server` (path `/` Prefix가 UI와 `/api/webhook` 모두 커버. NLB 서비스에 추가되는 ALB ingress, backend-protocol HTTPS).
- `dev-ingress.yaml` — dev gateway 단일 진입 → `gateway:80`. dev-<app> 세분은 gateway 경로 라우팅으로 충족.

두 ingress는 `group.name: synapse-nipio`로 **ALB 1개를 공유** → IP 1개 → nip.io 베이스 일관.

## 라이브 치환 (W5 clearance window, Phase 3)
1. ingress apply (cert-arn 미설정 상태로 ALB 프로비저닝 트리거).
2. `kubectl get ingress -A` 에서 ALB DNS 확보.
3. `scripts/gen-nipio-selfsigned.sh <ALB_DNS>` → `CERT_ARN=...` 획득.
4. 두 ingress의 `<ALB_IP>`·`<ACM_ARN>` 치환 후 재apply.
5. `curl --cacert .nipio-certs/ca.crt https://argocd.<IP>.nip.io` → 200.

## 주의
- nip.io의 `<IP>`는 window 동안만 유효(ALB IP는 ephemeral). 폐기 전제 검증이라 의도된 동작.
- self-signed → "인증서 유효"는 CA 신뢰 주입(`--cacert`) 기반 체인 검증으로 충족.
- 실 도메인 확보 시 상위 `infra/ingress/dev-ingress.yaml`·`staging-ingress.yaml`(ACM 공인) 사용 — 본 디렉토리는 그때 폐기.
