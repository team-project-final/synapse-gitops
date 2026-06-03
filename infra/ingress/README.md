# infra/ingress

EKS 외부 노출(AWS ALB Ingress, aws-load-balancer-controller).

## dev — Gateway 패턴 (`dev-ingress.yaml`)
ALB(internet-facing, ACM TLS) → **gateway** service:80 → gateway 파드:8080.
gateway(Spring Cloud Gateway)가 `/api/**`를 경로 라우팅 + Redis rate-limit으로 백엔드
(platform/engagement/knowledge/learning-card)에 전달. 단일 API 진입점.

이 패턴은 B4 prod NetworkPolicy(`apps/*/overlays/prod/netpol.yaml`)와 정합한다 —
백엔드 ingress가 `app.kubernetes.io/name: gateway` 파드만 허용하므로, 트래픽은
ALB→gateway→backend 경로로 흐른다.

## staging — ALB 직결 (`staging-ingress.yaml`)
ALB가 서비스별 호스트(`staging-<svc>.<domain>`)로 각 svc에 **직접** 라우팅(gateway 우회).
직접 테스트 편의용. dev의 gateway 패턴과는 다른 철학.

## 치환 플레이스홀더
- `<ACM_ARN>`: `terraform -chdir=infra/aws/dev output` 의 ACM 인증서 ARN.
- `<domain>`: terraform `var.domain_name`.

## 후속 (prod 구성 시)
- gateway prod/staging 오버레이 신설(현재 `apps/gateway/overlays/dev`만 존재).
- **prod gateway NetworkPolicy**: ALB(target-type ip, VPC ENI)→gateway:8080 ingress 허용 +
  gateway→백엔드(intra-ns) egress. B4 prod netpol은 백엔드 측만 gateway 호출자로 한정했고
  gateway 자체 netpol은 prod 배포 경로 확정(이 문서) 후속으로 남겨둠.
- prod ingress(`prod-ingress.yaml`): dev와 동일 Gateway 패턴 권장.
