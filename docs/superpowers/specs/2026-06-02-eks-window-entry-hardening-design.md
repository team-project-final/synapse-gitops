# Design: EKS window 진입 마찰 제거 (#87 / #88 / #89)

> **작성**: 2026-06-02 · **owner**: @VelkaressiaBlutkrone (gitops)
> **대상 이슈**: #87(P0 bastion EKS 접근) · #88(P1 브로커 주소 자동화) · #89(P1 D-026 SG 코드화)
> **선행**: 2026-06-02 MSK 토픽 terraform 편입(D-044, PR #86) — 동일 인프라 컨텍스트
> **관련**: shared `docs/runbooks/W4_DAY1_POST_APPLY.md`, `docs/superpowers/W5-scoping.md`

---

## 1. 배경 & 목표

세 OPEN 이슈는 모두 **재apply(EKS window)마다 발생하는 수동 작업·차단**을 terraform 영구 코드화로 제거하는 한 묶음이다. 모두 `infra/aws/dev/` 소관이라 단일 spec 3 컴포넌트로 처리하고, **1회 유료 라이브 window로 end-to-end 검증**한다.

- **#87 (P0)**: EKS 프라이빗 엔드포인트 + bastion 역할 미매핑 → `kubectl 401`로 배포 검증(`verify-argocd-deploy.sh`)·image-updater E2E 차단.
- **#88 (P1)**: MSK 재apply마다 브로커 DNS 변동(`…dchj3l→4ki14g…`) → 15개 overlay 수동 수정.
- **#89 (P1)**: EKS 자동생성 cluster SG가 terraform `eks_nodes` SG와 달라 파드→인프라(RDS/Redis/OpenSearch/MSK) 연결이 막힘(D-026).

**성공 정의**: 재apply 후 **수동 단계 0**으로 bastion `kubectl get nodes` 성공 + 파드가 인프라 도달 + 브로커 주소 자동 전파. 라이브 1회 증명 후 destroy.

## 2. 비목표

- **image-updater E2E 실행** — #87이 풀리면 가능해지나, ArgoCD 부트스트랩 + 앱 배포가 선행. 본 spec은 **접근 차단 해소까지**(E2E 자체는 별도).
- **A안 SASL/IAM** — B(TLS-only, D-044) 유지.
- **staging/prod 도메인·실 도메인 항목** — W1 이월 유지.

## 3. 결정 사항 (브레인스토밍 확정)

| # | 결정 | 비고 |
|---|------|------|
| 검증 | **전용 라이브 검증 window 포함** | 1회 유료 apply→증명→destroy |
| #87 access 메커니즘 | `authentication_mode = "API_AND_CONFIG_MAP"` + `aws_eks_access_entry` | legacy aws-auth ConfigMap 관리보다 terraform-native·견고. 클러스터 on-demand라 새로 세팅 깔끔 |
| #87 bastion scope | **AmazonEKSClusterAdminPolicy (cluster admin)** | bastion=프라이빗 클러스터 유일 진입점, ArgoCD 부트스트랩·검증·트러블슈팅 모두 수행 |
| #88 소싱 | **terraform `kubernetes_config_map`** | 브로커 DNS=인프라 산출물 → terraform 소유가 정합 |
| #88 ns 소유 | **terraform이 `kubernetes_namespace`(synapse-dev/staging/prod) 소유** | ConfigMap 순서 의존 해결. ArgoCD `CreateNamespace=true`는 멱등 no-op. 폴백=단일 공유 base(15→1 수동) |
| #89 수정 | EKS **cluster SG**를 4개 인프라 SG ingress에 추가 | 기존 `eks_nodes` 규칙 유지(additive) |

## 4. 컴포넌트 1 — #87 bastion EKS 접근 (P0)

**파일**: `eks.tf`(수정), `bastion.tf`(IAM 수정)

- `aws_eks_cluster.main`에 `access_config { authentication_mode = "API_AND_CONFIG_MAP" }` 추가.
- 신규 `aws_eks_access_entry`(principal = `aws_iam_role.bastion.arn`, type STANDARD) + `aws_eks_access_policy_association`(policy_arn = `arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy`, access_scope type=cluster).
- `bastion.tf` IAM 정책에 추가: `kafka:ListClustersV2`, `kafka:GetBootstrapBrokers`, `kafka:DescribeClusterV2` (Resource = MSK 클러스터 ARN/`*`). 이슈 acceptance(브로커 직접 fetch) 충족. *#88 적용 후 워크플로상 필수 아님 — durable 편의로 포함.*

**Acceptance (#87)**:
- [ ] bastion 역할이 cluster RBAC에 access entry로 매핑(terraform 영구).
- [ ] bastion 역할에 kafka read(ListClustersV2/GetBootstrapBrokers/DescribeCluster*) 추가.
- [ ] 라이브: bastion SSM에서 `kubectl get nodes` 성공 + `verify-argocd-deploy.sh synapse-dev` 실행 가능.

## 5. 컴포넌트 2 — #89 D-026 SG 코드화 (P1)

**파일**: `vpc.tf`(RDS/Redis/OpenSearch/MSK SG ingress 수정)

- 각 인프라 SG에 **EKS cluster SG**를 ingress source로 추가: `aws_eks_cluster.main.vpc_config[0].cluster_security_group_id`.
  - RDS SG: 5432, Redis SG: 6379, OpenSearch SG: 443, MSK SG: 9094(+9092).
- 기존 `aws_security_group.eks_nodes.id` 규칙은 **유지**(additive — 노드가 두 SG 모두 가질 수 있음).
- 순환참조 주의: cluster SG는 `aws_eks_cluster.main` 산출물이라 SG 정의가 클러스터에 의존. SG가 클러스터 생성 후 ingress 추가 형태이므로 cycle 없음(클러스터는 노드 SG에만 의존, 노드 SG는 cluster SG 미참조).

**Acceptance (#89)**:
- [ ] managed node group(cluster SG) → RDS/Redis/OpenSearch/MSK inbound가 terraform 선언.
- [ ] 라이브: 수동 SG 추가 없이 `verify-argocd-deploy.sh synapse-dev` 5/5 도달.

## 6. 컴포넌트 3 — #88 브로커 주소 ConfigMap 자동화 (P1)

**파일**: 신규 `infra/aws/dev/k8s-kafka-config.tf`, overlay 15개 수정

- 신규 `kubernetes_namespace` ×3: `synapse-dev`, `synapse-staging`, `synapse-prod` (terraform 소유). ArgoCD ApplicationSet `CreateNamespace=true`는 멱등 → 기존 ns 그대로 사용(충돌 없음).
- 신규 `kubernetes_config_map` `kafka-brokers` ×3(각 ns): `data.KAFKA_BROKERS = aws_msk_cluster.main.bootstrap_brokers_tls`(=output과 동일 소스).
- overlay 15개: 현재 per-service ConfigMap `data.KAFKA_BROKERS` 하드코딩 patch → 컨테이너 env `valueFrom.configMapKeyRef`(name=`kafka-brokers`, key=`KAFKA_BROKERS`)로 전환. (정확한 kustomize 배선은 plan에서 — base deployment env에 valueFrom 추가 + overlay 하드코딩 patch 제거.)
- 순서: terraform apply가 ns→ConfigMap 생성(클러스터 access는 #87이 제공). ArgoCD가 그 ns에 앱 배포 시 ConfigMap 이미 존재.

**Acceptance (#88)**:
- [ ] `terraform output` 브로커 주소가 `kafka-brokers` ConfigMap으로 3개 ns에 생성.
- [ ] 5개 service overlay가 ConfigMap 참조(개별 하드코딩 제거).
- [ ] 라이브: 재apply 후 수동 수정 없이 파드 env에 브로커 주소 반영.

**폴백(부담 시)**: terraform ns 소유가 과하면, 단일 공유 base ConfigMap(git, 1곳 수동 편집)으로 다운그레이드 — 자동화는 아니나 15→1.

## 7. 컴포넌트 4 — 라이브 검증 window + 마감

- **오프라인**: 위 변경 작성 → `terraform fmt`·`validate`·`plan`(무과금) 확인.
- **라이브 window(유료 1회)**: `terraform apply` → ① bastion `kubectl get nodes`(=#87) ② 파드/`verify-argocd-deploy.sh` 5/5(=#89) ③ ConfigMap 브로커 전파(=#88) 증명 → 증거 캡처.
- **마감**: 이슈 #87/#88/#89에 결과 코멘트 + close, `terraform destroy` 과금 차단, HISTORY **D-045** 기록, PR.

**리스크**:
- access entry/authMode 전환이 첫 적용 — plan에서 cycle/순서 확인. 실패 시 aws-auth ConfigMap 폴백.
- terraform kubernetes/helm provider가 클러스터 인증 필요(이미 main.tf에 kubernetes provider 존재 — EKS endpoint/token으로 구성). ns/ConfigMap apply가 endpoint=private라 **로컬 terraform이 도달 가능한지** 확인 필요(아니면 ns/ConfigMap만 bastion 경유 또는 별도 처리).

## 8. 미해결/의존

- **terraform kubernetes provider의 private endpoint 도달**: §7 리스크 — 로컬 apply가 private EKS API에 못 닿으면 #88 ns/ConfigMap 적용이 막힘. plan 첫 task에서 검증, 막히면 (a) endpoint public 임시 허용 (b) bastion 경유 (c) #88 폴백.
- image-updater E2E는 본 spec 범위 밖(후속).
