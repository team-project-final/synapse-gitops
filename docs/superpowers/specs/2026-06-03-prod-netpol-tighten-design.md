# prod NetworkPolicy 조이기 — 설계 (2026-06-03)

## 배경

핸드오프 후속 finding B4. #101이 prod 5개 svc에 per-svc NetworkPolicy를 도입했으나
모든 정책이 동일한 cookie-cutter다:
- **ingress**: `from: [podSelector: {}]` — 같은 ns의 **아무 파드나** 허용(gateway 한정 아님).
- **egress**: DNS + intra-ns(`podSelector: {}`) + VPC 데이터스토어(5432/6379/9092/9094/443) +
  외부 `0.0.0.0/0:443`(전 서비스 동일).

B4는 (1) ingress를 실제 호출자로 한정, (2) 외부 443을 실제 필요 서비스로 한정한다.

## 호출 그래프 (소스 분석 결과, k8s 기준)

> k8s 보정: 앱 `server.port`(8081~8084)는 ConfigMap `SERVER_PORT=8080`으로 오버라이드 →
> 모든 Java svc 파드는 **8080**, learning-ai는 **8090**. inter-svc URL의 localhost:80xx도 env로
> k8s 서비스 DNS 오버라이드.

- **gateway** → platform·engagement·knowledge·learning-card (HTTP 8080). gateway는 learning-ai 직접 호출 없음.
- **knowledge-svc** → learning-ai (8090, 시맨틱 검색, RestClient).
- **learning-ai** → platform-svc(8080, 노트 조회) + learning-card(8080, 카드 저장).
- 그 외 svc↔svc HTTP 없음(나머지 통신은 Kafka 이벤트).
- **외부 443**: platform(Stripe/OAuth2 Google·GitHub·Apple/AWS SES), learning-ai(OpenAI/Anthropic)만.
  engagement·knowledge·learning-card는 외부 인터넷 egress 미사용.

## 목표 / 비목표

**목표**
- prod 5개 netpol의 ingress `from`을 실제 호출자 파드 라벨로 한정.
- 외부 443 egress를 platform·learning-ai만 유지, 나머지 3개에서 제거.

**비목표(보수적 — 사용자 결정)**
- intra-ns egress(`podSelector: {}`) 유지: inter-svc 호출 + **prod 미배포 schema-registry**(B5는 dev만)
  대비. 좁히면 SR 배포 시 깨질 위험.
- VPC 데이터스토어 egress 포트 현행 유지: Redis 사용 여부 불확실(engagement) 등 리스크 회피.
- gateway netpol 신설: gateway가 prod 미배포(B1) → 배포 경로 확정 후 별도.

## 결정 사항

- **egress 강도**: 보수적. ingress 한정 + 외부 443 차등만. intra-ns·데이터스토어 포트는 현행 유지.
- **gateway 의존성**: ingress가 `app.kubernetes.io/name: gateway` 라벨을 참조 → gateway가 prod에
  배포되기 전(B1)까진 해당 from이 매칭하는 파드가 없어 공개 경로는 비활성. 라벨 기반이라 gateway
  배포 시 자동 실현(무중단). prod 미존재 클러스터라 지금은 git-only.

## 변경 설계 (서비스별 ingress `from` + 외부 443)

ingress는 같은 ns의 호출자 파드를 `podSelector matchLabels app.kubernetes.io/name: <caller>`로 한정.

| 서비스 | ingress from (포트) | 외부 0.0.0.0/0:443 |
|--------|------|------|
| platform-svc | gateway, learning-ai (8080) | **유지** |
| engagement-svc | gateway (8080) | **제거** |
| knowledge-svc | gateway (8080) | **제거** |
| learning-card | gateway, learning-ai (8080) | **제거** |
| learning-ai | knowledge-svc (8090) | **유지** |

egress 공통(현행 유지): DNS(kube-dns), intra-ns(`podSelector: {}`), VPC 데이터스토어 ipBlock
10.0.0.0/16 (5432/6379/9092/9094/443). 외부 443 블록만 위 표대로 차등.

ingress 예시(platform-svc):
```yaml
  ingress:
    # gateway(공개 경로) + learning-ai(노트 조회)만 허용
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: gateway
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: learning-ai
      ports:
        - {protocol: TCP, port: 8080}
```

> 스타일: 기존 netpol의 flow 표기(`{protocol: TCP, port: 8080}`, `[Ingress, Egress]`)는 브레이스
> 안쪽 공백이 없어 yamllint 통과 → 동일 스타일 유지.

## 리스크 / 미검증 항목 (Runbook 갱신)

- **gateway 미배포(B1)**: ingress가 gateway 라벨 의존 → gateway 배포 전 공개 API 경로 차단됨(의도).
  B1에서 gateway가 prod에 배포되면 자동 허용. EKS 프로비저닝 시 gateway 파드 라벨이
  `app.kubernetes.io/name: gateway`인지 확인.
- **외부 443 제거(engagement/knowledge/learning-card)**: 향후 이들이 AWS SDK(CloudWatch/S3/SQS) 등
  외부 호출을 추가하면 egress 차단됨 → 외부 443 재추가 또는 VPC 엔드포인트 사용 필요. 현재 소스엔 없음.
- **VPC CNI 정책 컨트롤러**: EKS는 NetworkPolicy 기본 미강제 — 컨트롤러 활성 선행(기존
  `docs/runbooks/networkpolicy-validation.md` 참조).
- **kubelet 프로브**: host(노드) 출발이라 podSelector ingress와 무관(#101에서 이미 검증된 동작 유지).

## 검증 계획

| 항목 | 방법 | 시점 |
|------|------|------|
| 렌더 정합성 | `kubectl kustomize apps/<svc>/overlays/prod` 5개 | 이번 작업 |
| ingress from/외부443 차등 확인 | 렌더 grep | 이번 작업 |
| yamllint CI | gitops `validate` | PR |
| Calico minikube enforcement(선택) | `docs/runbooks/networkpolicy-validation.md` 절차 | 선택/이연 |
| EKS 런타임 | VPC CNI 컨트롤러 + gateway 배포 후 | 태스크 A / B1 |

## 영향 범위 / PR

- **synapse-gitops** (1 PR): `apps/{platform-svc,engagement-svc,knowledge-svc,learning-card,learning-ai}/overlays/prod/netpol.yaml` 5개 + `docs/runbooks/networkpolicy-validation.md` 보강.
- 앱 레포 변경 없음. dev/staging netpol 없음(prod만 대상).
