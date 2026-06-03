# gateway EKS 배포 경로 — 설계 (2026-06-03)

## 배경

핸드오프 후속 finding B1. synapse-gateway(Spring Cloud Gateway)는 `apps/gateway/overlays/dev`가
완비(Redis rate-limit, ECR 이미지 `synapse/gateway:dev-latest`, ExternalSecret, 백엔드 URI)돼
있으나 **어느 ApplicationSet에도 없어 ArgoCD가 배포하지 않는다**. EKS 노출 경로도 미확정이었다.

조사 결과 두 노출 철학이 공존:
- `infra/ingress/staging-ingress.yaml`: ALB가 서비스별 호스트로 각 svc에 **직접** 라우팅(gateway 우회).
- gateway: `/api/*` 경로 라우팅 + Redis rate-limit(단일 API 진입).

**결정: Gateway 패턴**(ALB→gateway→services). 백엔드는 gateway 파드에서 트래픽 수신 →
B4(#104) prod netpol(`ingress from gateway`)이 그대로 유효.

## 호출/노출 그래프 (k8s)

ALB(internet-facing, ACM TLS) → gateway service:80 → gateway 파드:8080 →
`/api/platform`→platform-svc, `/api/engagement`→engagement-svc, `/api/knowledge`→knowledge-svc,
`/api/learning`→learning-card (gateway-config의 `*_SVC_URI`, 모두 `http://<svc>:80`).
gateway는 Redis(rate-limit)에 의존. learning-ai는 gateway가 직접 호출하지 않음(knowledge 경유).

## 목표 / 비목표

**목표**
- gateway를 dev ApplicationSet에 추가해 ArgoCD가 synapse-dev에 배포(image-updater ECR semver 포함).
- ALB Ingress 신설: 단일 호스트 → gateway service(`/api/*`는 gateway 내부 라우팅).

**비목표(후속)**
- prod/staging gateway 오버레이 + prod gateway netpol(ALB→gateway 허용): prod 구성 시 후속.
  B4 prod netpol이 이미 gateway를 호출자로 전제함만 문서화.
- staging-ingress(ALB 직결)의 gateway 패턴 통일: staging 정책 결정 사항으로 보류.

## 결정 사항

- **패턴**: Gateway(ALB→gateway→svc). B4와 정합.
- **범위**: dev 한정(dev ApplicationSet + dev ingress). gateway 오버레이는 dev만 존재.
- **노출**: 단일 호스트 `dev.<domain>` → gateway service:80. gateway가 `/api/**` 경로 라우팅.
- dev는 netpol 미적용(prod 전용) → dev gateway netpol 불필요.

## 변경 설계

### 표면 1 — dev ApplicationSet에 gateway 추가
`argocd/applicationset.yaml`의 list 제너레이터 service 목록에 `- service: gateway` 추가.
매트릭스 템플릿이 `apps/gateway/overlays/dev`(path), synapse-dev(ns), image-updater 주석
(`.../synapse/gateway` ECR semver)을 자동 적용. gateway는 ECR semver 이미지라 schema-registry와
달리 매트릭스 포함이 적합.

### 표면 2 — ALB Ingress (ALB → gateway)
`infra/ingress/dev-ingress.yaml` 신설(`staging-ingress.yaml` 패턴 모델):
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: synapse-dev
  namespace: synapse-dev
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    # 라이브 세션에서 ACM 인증서 ARN으로 치환(acm.tf output)
    alb.ingress.kubernetes.io/certificate-arn: <ACM_ARN>
    # gateway는 Spring Boot actuator readiness 노출(SERVER_PORT 8080 → svc:80)
    alb.ingress.kubernetes.io/healthcheck-path: /actuator/health/readiness
spec:
  rules:
    # 단일 진입: gateway가 /api/** 경로 라우팅 + rate-limit
    - host: dev.<domain>
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: gateway
                port:
                  number: 80
```
`<ACM_ARN>`/`<domain>`은 staging-ingress와 동일하게 라이브 치환 플레이스홀더.

### 표면 3 — 문서
`infra/ingress/`에 README 또는 dev-ingress 주석으로:
- gateway 패턴 선택 근거(ALB→gateway→svc, B4 정합).
- prod/staging gateway 오버레이 + prod gateway netpol(ALB→gateway, VPC CIDR egress→backends) 후속.
- staging-ingress(ALB 직결)와의 철학 차이 명시.

## 리스크 / 미검증 항목 (EKS 프로비저닝 시)

- **B2 머지 순서**: gateway dev overlay 이미지는 ECR `synapse/gateway:dev-latest`. B2(synapse-gateway#3)
  머지로 USER(uid 101) 포함 이미지가 ECR에 올라온 뒤라야 gateway 파드가 정상(B2 base는 dev엔
  runAsNonRoot 미적용이나 일관성 위해 동일 이미지 사용).
- **ALB 컨트롤러**: aws-load-balancer-controller 설치 전제(staging-ingress와 동일 의존). addons.tf 확인.
- **ACM/도메인**: `terraform -chdir=infra/aws/dev output` 의 ACM ARN + var.domain_name로 치환.
- **dev ingress 적용 주체**: infra/ingress 매니페스트가 ArgoCD/수동 중 무엇으로 적용되는지(staging-ingress와
  동일 경로) 확인. 클러스터 부재라 지금은 파일 생성만.
- **gateway readiness 경로**: gateway가 `/actuator/health/readiness`를 노출하는지(Spring Boot actuator
  health probes). 미노출 시 `/` 또는 actuator 경로 조정.

## 검증 계획

| 항목 | 방법 | 시점 |
|------|------|------|
| ApplicationSet 렌더(gateway 포함) | `kubectl kustomize apps/gateway/overlays/dev` + AS 파일 yaml 유효성 | 이번 작업 |
| dev-ingress 유효성 | `kubeconform`/yamllint, kind Ingress 스키마 | 이번 작업 |
| yamllint CI | gitops `validate` | PR |
| EKS 런타임(ALB 프로비저닝, gateway Synced/Healthy, /api/* 라우팅) | EKS 프로비저닝 후 | 태스크 A |

## 영향 범위 / PR

- **synapse-gitops** (1 PR): `argocd/applicationset.yaml`(+gateway), `infra/ingress/dev-ingress.yaml`(신규),
  `infra/ingress/README.md`(또는 주석) 문서.
- 앱 레포 변경 없음. gateway 코드/Dockerfile은 B2에서 이미 처리.
