# 2026-06-03 리포트 후속 4종 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `docs/reports/2026-06-03-...md` §2.5의 미해결 후속 4종(gateway non-root 이미지·engagement Kafka 런타임·staging/prod Kafka SSL·prod 선행조건)을 코드화해 다음 EKS 프로비저닝 윈도에서 prod 경로까지 검증 가능한 상태로 만든다.

**Architecture:** 4개 독립 워크스트림으로 분해한다. **WS3(Kafka TLS-readiness)는 2026-06-04 조사로 gitops 단독이 아니라 cross-repo(4개 앱 PR + gitops + EKS 검증) 작업으로 정정됨** — 아래 "WS3 (REVISED)" 섹션이 권위. WS1·WS2는 서비스 레포 CI가 새 이미지를 ECR에 올린 뒤 gitops가 태그를 가리키는 2-레포 작업. WS4(prod 선행조건)는 terraform + bring-up.sh 인프라 작업으로 **클러스터 없이 지금 완결 가능**. 라이브 런타임 검증은 비용 절감 패턴(provision→verify→destroy)에 따라 다음 EKS 윈도로 이월하고, 그 전까지는 `kubectl kustomize` 렌더 + `python -m yamllint`로 회귀 차단.

**Tech Stack:** Kustomize overlays, ArgoCD ApplicationSet, AWS MSK(TLS-only, 9094), EKS VPC CNI NetworkPolicy 컨트롤러, metrics-server, Terraform(`infra/aws/dev`), Bash(`scripts/bring-up.sh`), yamllint.

**환경:** `C:/workspace/team-project-final/synapse-gitops`. 클러스터 부재 시 렌더/lint만(라이브는 EKS 윈도). yamllint은 CRLF 줄바꿈 에러를 피하려 LF로 정규화 후 실행: `tr -d '\r' < <file> > /tmp/lf.yaml && yamllint -c .yamllint /tmp/lf.yaml`. 서비스 레포 경로: `C:/workspace/team-project-final/synapse-gateway`, `.../synapse-engagement-svc`.

**선행 사실(2026-06-04 조사):**
- gateway dev 오버레이 `newName=.../synapse/gateway`(슬래시)는 gateway 레포 `deploy.yml ecr_repository: synapse/gateway`와 **이미 일치**. 리포트가 본 `synapse-gateway`(하이픈) latest/1.0.0 이미지는 표준화 이전 stale 산출물 → WS1은 "경로 수정"이 아니라 **non-root 이미지 재빌드 + 오버레이 태그 정합** 문제로 축소된다.
- engagement dev 오버레이는 이미 `KAFKA_ENABLED=true` + `SPRING_KAFKA_SECURITY_PROTOCOL=SSL` 패치 보유(#108). 미해결은 **deploy 이미지 `newTag: 1.0.0`이 #21(kafka 배선) 이전**이라는 점뿐.
- dev에서 Kafka SSL은 **engagement-svc·schema-registry 오버레이에만** 적용됨. staging/prod 오버레이는 존재하나 SSL 미적용. schema-registry는 **dev 오버레이만 존재**(staging/prod 없음).
- prod 선행조건(VPC CNI netpol 컨트롤러·metrics-server)은 terraform/bring-up 어디에도 없음.

---

## ⚠️ 착수 전 확정 필요 결정 (2건)

이 플랜은 아래 기본값으로 작성됨. 다르면 해당 Task만 조정.

- **D-A. Kafka SSL 적용 대상 범위.** 기본값: MSK가 TLS-only(9094)이므로 **MSK에 연결하는 모든 클라이언트**(engagement-svc, schema-registry, 그리고 knowledge-svc[#32 producer]·learning-card·learning-ai 중 Kafka 사용분)에 `SECURITY_PROTOCOL=SSL`을 dev/staging/prod 일관 적용한다. WS3 Task 1이 먼저 클라이언트 인벤토리를 확정한다. (대안: engagement+SR만 — dev 현황과 동일하나, 타 서비스 Kafka 활성 시 동일 장애 재발하므로 비권장.)
- **D-B. 라이브 검증 시점.** 기본값: 렌더/lint로 머지하고 **라이브 런타임 검증은 다음 EKS 윈도로 이월**(provision→verify→destroy, 리포트 §4 비용 패턴). 각 WS의 "라이브 검증" Task는 EKS 윈도 체크리스트로 남긴다. (대안: 지금 EKS 프로비저닝 — 시간당 ~$0.5, 검증 후 destroy.)

---

## File Structure

**WS1 — gateway non-root 이미지** (synapse-gateway 레포 + gitops)
- Verify: `synapse-gateway/Dockerfile`(non-root USER), `synapse-gateway/.github/workflows/deploy.yml`(ecr_repository)
- Modify(필요 시): `apps/gateway/overlays/dev/kustomization.yaml`(newTag 정합)

**WS2 — engagement Kafka 런타임 이미지** (synapse-engagement-svc 레포 + gitops)
- Verify: `synapse-engagement-svc`(main에 #21 포함)
- Modify: `apps/engagement-svc/overlays/dev/kustomization.yaml`(newTag 1.0.0 → 신규 semver)

**WS3 — Kafka TLS-readiness** (cross-repo, REVISED 2026-06-04 — 아래 "WS3 (REVISED)" 섹션 참조)
- 앱 PR: `synapse-platform-svc`·`synapse-knowledge-svc`·`synapse-learning-svc/learning-card`(KafkaConfig `security.protocol` 배선), `synapse-learning-svc/learning-ai`(Python `security_protocol`)
- gitops: `apps/{platform-svc,knowledge-svc,learning-card,learning-ai}/overlays/dev`(KAFKA 활성화) → 검증 후 staging/prod
- Create: `apps/schema-registry/overlays/{staging,prod}/`, Modify: `argocd/applicationset*.yaml`

**WS4 — prod 선행조건** (terraform + bring-up)
- Modify: `infra/aws/dev/eks.tf`(vpc-cni addon `enableNetworkPolicy`)
- Create: `infra/k8s-addons/metrics-server.yaml` (또는 helm 참조)
- Modify: `scripts/bring-up.sh`(phase_metrics_server 추가)
- Create: `docs/runbooks/prod-prereqs-netpol-metrics.md`

---

## WS3 (REVISED 2026-06-04): Kafka TLS-readiness — cross-repo (앱 PR 선행 → gitops → E2E)

> **정정 사유:** 초안 WS3는 "오버레이에 SSL env만 추가하면 됨"을 전제했으나 2026-06-04 조사로 전제가 틀렸음이 확인됨:
> - MSK 연결 Spring 서비스들이 **커스텀 `KafkaConfig`로 producer/consumer 팩토리를 수동 구성**(`props.put(...)`)하며 **`security.protocol`을 넣는 코드가 없음** → `SPRING_KAFKA_SECURITY_PROTOCOL=SSL` env를 줘도 팩토리가 읽지 않아 PLAINTEXT 기본→TLS MSK 연결 실패.
> - **learning-ai(Python)**는 `Settings`에 `security_protocol` 필드 부재, aiokafka에 `bootstrap_servers`만 전달.
> - dev에서 Kafka는 **engagement-svc만** 활성(KAFKA_ENABLED). 나머지 4개는 어느 환경에도 미활성.
> - TLS MSK 위 E2E는 **미검증**(engagement 검증 로그는 minikube PLAINTEXT 기준).
>
> 따라서 WS3는 gitops 단독이 아니라 **4개 앱 레포 PR + gitops + EKS 검증**의 cross-repo 작업이다. 근거: 메모리 `kafka-tls-msk-app-readiness-gap`, `docs/runbooks/engagement-kafka-enablement.md`(SSL 매트릭스), EVENT_FLOW_MATRIX(synapse-shared, D-001 — 5개 서비스 Kafka 참여).

**근거 파일(2026-06-04 실측):**
- `synapse-platform-svc/.../global/kafka/KafkaProducerConfig.java` — 수동 props, `security.protocol` 없음.
- `synapse-knowledge-svc/.../global/config/KafkaConfig.java`, `synapse-learning-svc/learning-card/.../config/KafkaConfig.java` — 동일 패턴(schema.registry.url만 주입).
- `synapse-learning-svc/learning-ai/app/core/config.py` — `kafka_bootstrap_servers`만(env_prefix `LEARNING_AI_`).

**권장 순서:** dev 갭부터(사용자 결정) → 서비스별 앱 PR(WS3-A/B) → gitops dev 활성화(WS3-C) → EKS 윈도 E2E(WS3-D) → 검증된 서비스만 staging/prod 복제(WS3-E).

> ⚠️ 각 앱 PR의 정확한 변경은 해당 레포 컨벤션·테스트 패턴에 맞춰 per-repo로 확정해야 한다(아래는 패턴·앵커 제시). 이 WS3는 "altitude plan" — 레포별 실착수 시 각 레포에서 TDD로 구체화.

### WS3-A: Spring 서비스 `security.protocol` 배선 (앱 레포 3건)

대상: `synapse-platform-svc`, `synapse-knowledge-svc`, `synapse-learning-svc/learning-card`. 각 레포 동일 패턴, 레포별 1 PR(브랜치→dev PR, 메모리 git-pr-workflow).

per-service 작업(예: platform-svc `KafkaProducerConfig.java` + `KafkaConsumerConfig.java`):

- [ ] **Step 1: 실패 테스트** — securityProtocol=SSL 주입 시 factory config에 `security.protocol=SSL` 포함을 단언하는 단위 테스트.
- [ ] **Step 2: @Value + props 주입 추가**
```java
@Value("${spring.kafka.security.protocol:PLAINTEXT}")
private String securityProtocol;
// ...팩토리 props 구성부에:
if (!"PLAINTEXT".equalsIgnoreCase(securityProtocol)) {
    props.put(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, securityProtocol);
}
```
producer·consumer 팩토리 양쪽에 적용. (MSK 인증서=Amazon Trust Services → JDK 기본 truststore로 충분, truststore 설정 불요.)
- [ ] **Step 3: application.yml 명시 바인딩** — `spring.kafka.security.protocol: ${SPRING_KAFKA_SECURITY_PROTOCOL:PLAINTEXT}` 추가(relaxed-binding 암묵 의존 대신 명시).
- [ ] **Step 4: 테스트 green + 커밋 + dev PR**

knowledge-svc·learning-card도 동일(KafkaConfig 경로만 상이). learning-card는 producer+consumer 모두.

### WS3-B: learning-ai `security_protocol` (Python 앱 PR)

**Files:** `synapse-learning-svc/learning-ai/app/core/config.py`, `app/kafka/consumer.py`, `app/kafka/notification_producer.py`

- [ ] **Step 1: 실패 테스트** — Settings가 `LEARNING_AI_KAFKA_SECURITY_PROTOCOL` env를 읽어 `kafka_security_protocol`에 반영하는지.
- [ ] **Step 2: Settings 필드 추가** — `kafka_security_protocol: str = "PLAINTEXT"`.
- [ ] **Step 3: aiokafka 생성자에 전달** — `AIOKafkaConsumer(..., security_protocol=settings.kafka_security_protocol)`, producer도 동일. SSL이면 aiokafka 기본 ssl context(시스템 CA = Amazon Trust 포함).
- [ ] **Step 4: 테스트 green + 커밋 + dev PR**

### WS3-C: gitops dev Kafka 활성화 (WS3-A/B 머지 + 이미지 빌드 후)

**Files:** Modify `apps/{platform-svc,knowledge-svc,learning-card,learning-ai}/overlays/dev/kustomization.yaml`

- [ ] **Step 1: 각 dev 오버레이에 engagement/dev 동형 패치 추가** — ConfigMap `/data`에 `KAFKA_ENABLED`(앱 게이트 키에 맞춤), `SPRING_KAFKA_SECURITY_PROTOCOL=SSL`(learning-ai는 `LEARNING_AI_KAFKA_SECURITY_PROTOCOL=SSL`), `SCHEMA_REGISTRY_URL=http://schema-registry:8081`. 참조: `apps/engagement-svc/overlays/dev/kustomization.yaml`.
- [ ] **Step 2: 이미지 태그가 보안배선 포함분인지 확인** — WS3-A/B 머지 후 CI가 올린 새 이미지로 각 dev 오버레이 newTag 정합(또는 image-updater 자동). dev-latest가 mutable이면 재빌드로 반영.
- [ ] **Step 3: render/lint + 커밋**
```bash
for d in apps/platform-svc apps/knowledge-svc apps/learning-card apps/learning-ai; do kubectl kustomize "$d/overlays/dev" >/dev/null && echo "OK $d"; done
# yamllint: python -m yamllint -c .yamllint (CRLF 정규화 후)
```

### WS3-D: EKS 윈도 E2E 검증 (D-B 이월)

- [ ] **Step 1: runbook 확장** — `docs/runbooks/engagement-kafka-enablement.md` 절차를 4개 서비스로 확장. 각 서비스 파드 로그에서 TLS MSK(9094) bootstrap·consumer group join·Avro produce/consume 무에러. EVENT_FLOW 체인(가입→프로필, 노트→AI카드, 복습→XP) E2E.

### WS3-E: staging/prod 복제 (dev E2E 통과 서비스만)

**Files:** Create `apps/schema-registry/overlays/{staging,prod}/`, Modify `apps/<svc>/overlays/{staging,prod}/kustomization.yaml`, `argocd/applicationset*.yaml`

- [ ] **Step 1: schema-registry staging/prod 오버레이 신설** — dev 오버레이 복제(namespace synapse-staging/synapse-prod, ns별 kafka-brokers ConfigMap 참조, SSL 동일). prod replica/affinity는 후속.
- [ ] **Step 2: dev에서 검증된 각 서비스의 staging/prod 오버레이에 WS3-C 동형 패치 적용.**
- [ ] **Step 3: applicationset(staging/prod)에 schema-registry 등록.**
- [ ] **Step 4: 전체 오버레이 render 회귀 + lint + PR.**

## WS2: engagement Kafka 런타임 이미지 (서비스 레포 릴리스 + gitops 태그)

브랜치(gitops): `chore/engagement-image-bump`

### Task 1: engagement-svc 신규 이미지 릴리스 (synapse-engagement-svc 레포)

**Files:** Verify `C:/workspace/team-project-final/synapse-engagement-svc`

- [ ] **Step 1: main이 #21(kafka 배선) 포함인지 확인**

Run:
```bash
cd C:/workspace/team-project-final/synapse-engagement-svc
git log --oneline -10 | grep -i 'kafka\|#21\|bootstrap'
grep -rn 'spring.kafka.bootstrap-servers\|KAFKA_BOOTSTRAP_SERVERS' src/main/resources/
```
Expected: kafka 배선 커밋/설정 존재(현재 main = f3d5ef7, 2026-06-04 최신화 완료분).

- [ ] **Step 2: 릴리스 트리거(새 semver 태그/푸시)**

deploy.yml은 `ecr_repository: synapse/engagement-svc`로 푸시. 레포 릴리스 규칙(태그 or main 머지 시 CI)에 따라 새 버전(예: `1.1.0`) 산출. 릴리스 방식이 불명확하면 `.github/workflows/{ci-java,deploy}.yml` 트리거 조건 확인 후 그 방식으로 새 이미지 빌드:
```bash
grep -n 'on:\|tags:\|branches:\|push:' .github/workflows/ci-java.yml .github/workflows/deploy.yml
```
Expected: 트리거 조건. 그에 맞춰 릴리스(태그 push 등) 실행 → ECR `synapse/engagement-svc:<new>` 생성.

- [ ] **Step 3: ECR에 새 이미지 도착 확인**

(EKS 윈도/AWS 크레덴셜 있을 때)
```bash
aws ecr describe-images --repository-name synapse/engagement-svc --region ap-northeast-2 \
  --query 'sort_by(imageDetails,&imagePushedAt)[-3:].imageTags' --output table
```
Expected: 신규 태그가 최신. 크레덴셜 없으면 이 Step은 EKS 윈도 체크리스트로 이월(D-B).

### Task 2: gitops dev 오버레이 태그 정합

**Files:** Modify `apps/engagement-svc/overlays/dev/kustomization.yaml:74`

- [ ] **Step 1: image-updater 자동화 여부 확인**

Run:
```bash
cd C:/workspace/team-project-final/synapse-gitops
grep -rn 'image-updater\|argocd-image-updater' argocd/ apps/engagement-svc/
```
Expected: image-updater 어노테이션이 engagement에 걸려 있으면 ECR semver를 자동 PR로 bump → **수동 변경 불필요**(Task 2 종료, image-updater PR 머지로 대체). 없으면 Step 2.

- [ ] **Step 2: newTag 수동 bump (image-updater 미적용 시)**

`apps/engagement-svc/overlays/dev/kustomization.yaml`의 `newTag: 1.0.0`을 Task 1의 신규 버전으로 변경:
```yaml
    newTag: "1.1.0"   # #21 kafka 배선 포함 이미지
```

- [ ] **Step 3: 렌더 확인 + 커밋**

```bash
kubectl kustomize apps/engagement-svc/overlays/dev | grep 'image:.*engagement-svc'
git add apps/engagement-svc/overlays/dev/kustomization.yaml
git commit -m "chore(engagement): dev 이미지 태그 → #21 kafka 배선 포함본 (WS2)"
git push -u origin chore/engagement-image-bump
gh pr create --repo team-project-final/synapse-gitops --base main --head chore/engagement-image-bump \
  --title "chore(engagement): dev 이미지 태그 bump (#21 kafka 런타임)" \
  --body "리포트 §2.5: 배포 이미지 1.0.0이 #21 이전이라 KAFKA_ENABLED여도 미초기화. #21 포함 신규 이미지로 태그 정합."
```
Expected: 렌더 image가 신규 태그, PR URL.

### Task 3: 라이브 런타임 검증 (EKS 윈도 — D-B 이월)

**Files:** 검증만. 절차 = `docs/runbooks/engagement-kafka-enablement.md` "검증 순서" 1~4

- [ ] **Step 1: 런북 절차 실행** — SR Synced/Healthy → SR→MSK 연결 → `/subjects` 200 → engagement 파드 로그에 `bootstrap.servers=[<MSK>]`, `Discovered group coordinator`, `Successfully joined group`, Avro ERROR 없음. (minikube에서 동일 절차 검증 완료 로그가 런북에 있음 — EKS는 MSK TLS 경로만 추가 확인.)

---

## WS1: gateway non-root 이미지 (서비스 레포 재빌드 + gitops 태그)

브랜치(gateway 레포): `fix/nonroot-image`(필요 시)

### Task 1: gateway 이미지 non-root 상태 점검 (synapse-gateway 레포)

**Files:** Verify `C:/workspace/team-project-final/synapse-gateway/Dockerfile`, `.github/workflows/deploy.yml`

- [ ] **Step 1: Dockerfile non-root USER 확인**

Run:
```bash
cd C:/workspace/team-project-final/synapse-gateway
grep -n 'USER\|adduser\|useradd\|101' Dockerfile
cat .github/workflows/deploy.yml | grep -n 'ecr_repository'
```
Expected: `USER 101`(또는 non-root uid)이 있으면 이미 non-root → 재빌드만 필요. 없으면 Step 2에서 추가. `ecr_repository: synapse/gateway` 확인(오버레이 newName과 일치).

- [ ] **Step 2: (USER 없을 때만) non-root USER 추가**

다른 서비스 Dockerfile의 non-root 패턴(#100 — uid 101 `app`)과 동일하게 `synapse-gateway/Dockerfile`에 적용. 참조:
```bash
grep -n 'USER\|101' C:/workspace/team-project-final/synapse-engagement-svc/Dockerfile
```
동일 표기(`USER 101:101` 등)를 gateway Dockerfile final 스테이지에 추가.

- [ ] **Step 3: 릴리스(새 이미지 ECR 푸시)**

WS2 Task 1 Step 2와 동일 방식(레포 트리거 규칙)으로 `synapse/gateway:<new semver>` 빌드·푸시. 커밋(USER 추가 시):
```bash
git add Dockerfile
git commit -m "fix(docker): non-root USER 101 (B2, EKS securityContext 정합)"
git push
```

### Task 2: gitops gateway dev 오버레이 태그 정합

**Files:** Modify `apps/gateway/overlays/dev/kustomization.yaml:47`

- [ ] **Step 1: image-updater 여부 확인 후 태그 정합**

WS2 Task 2와 동일 절차. 현재 `newTag: dev-latest`. image-updater가 ECR semver를 관리하면 자동, 아니면 신규 non-root 이미지 태그로 변경. `dev-latest`가 ECR의 최신을 가리키면 재빌드만으로 반영될 수 있음 — ECR 태그 정책 확인:
```bash
cd C:/workspace/team-project-final/synapse-gitops
grep -n 'newTag' apps/gateway/overlays/dev/kustomization.yaml
```
Expected: `dev-latest`가 mutable 태그면 재푸시로 자동 반영(태그 변경 불필요), immutable semver면 newTag bump 필요.

- [ ] **Step 2: 변경 시 커밋 + PR**(태그 bump 필요할 때만)

```bash
git add apps/gateway/overlays/dev/kustomization.yaml
git commit -m "chore(gateway): dev 이미지 태그 → non-root 빌드 (WS1)"
```

### Task 3: 라이브 검증 (EKS 윈도 — D-B 이월)

- [ ] **Step 1: gateway 배포·기동 확인** — `kubectl -n synapse-dev get deploy gateway`, 파드 `uid=101` 기동(CreateContainerConfigError 없음), ArgoCD `synapse-gateway-dev` Synced/Healthy. (gateway-deploy-path 플랜의 ALB Ingress 경로와 함께 ALB→gateway:80→백엔드 도달.)

---

## WS4: prod 선행조건 — VPC CNI NetworkPolicy 컨트롤러 + metrics-server

브랜치: `feat/prod-prereqs-netpol-metrics`

### Task 1: VPC CNI NetworkPolicy 컨트롤러 활성화 (terraform)

**Files:** Modify `infra/aws/dev/eks.tf`

- [ ] **Step 1: 현재 vpc-cni addon 설정 확인**

Run:
```bash
cd C:/workspace/team-project-final/synapse-gitops
grep -n 'vpc-cni\|aws_eks_addon\|coredns\|kube-proxy' infra/aws/dev/eks.tf
```
Expected: vpc-cni addon 블록 위치(없으면 신규 addon 리소스 추가). EKS에서 표준 NetworkPolicy 집행은 VPC CNI의 `enableNetworkPolicy=true` 필요.

- [ ] **Step 2: enableNetworkPolicy 설정 추가**

`infra/aws/dev/eks.tf`의 vpc-cni `aws_eks_addon`에 `configuration_values` 추가(없으면 addon 리소스 신설):
```hcl
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.this.name   # 실제 cluster 리소스명에 맞춤
  addon_name   = "vpc-cni"
  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })
}
```
(기존 addon 리소스가 있으면 `configuration_values`만 병합. cluster 참조명은 파일 내 실제 리소스명 사용.)

- [ ] **Step 3: terraform 검증**

Run:
```bash
cd infra/aws/dev && terraform fmt && terraform validate
```
Expected: `Success! The configuration is valid.` (init 필요 시 `terraform init -backend=false`로 plugin만.)

- [ ] **Step 4: 커밋**

```bash
cd C:/workspace/team-project-final/synapse-gitops
git add infra/aws/dev/eks.tf
git commit -m "feat(eks): vpc-cni NetworkPolicy 컨트롤러 활성화 (prod netpol 집행 선행, WS4-1)"
```

### Task 2: metrics-server를 bring-up에 추가 (HPA 선행)

**Files:** Create `infra/k8s-addons/metrics-server.yaml`, Modify `scripts/bring-up.sh`

- [ ] **Step 1: metrics-server 매니페스트 고정**

`infra/k8s-addons/metrics-server.yaml` — 공식 릴리스 매니페스트를 버전 고정으로 vendored(재현성; bring-up이 외부 URL 대신 repo 파일 적용). 헤더에 출처/버전 주석:
```yaml
# metrics-server v0.7.2 (vendored, https://github.com/kubernetes-sigs/metrics-server/releases)
# HPA(prod overlays/*/hpa.yaml) 선행. EKS에서 --kubelet-insecure-tls 불필요(서명 kubelet).
```
(공식 `components.yaml` 내용을 그대로 넣되, EKS 환경에 맞는 args 확인.)

- [ ] **Step 2: bring-up.sh에 phase 추가**

`scripts/bring-up.sh`의 phase 목록(`--from` 도움말 28행)과 함수부에 `metrics-server` 추가. `phase_manifests` 직전 또는 직후에:
```bash
phase_metrics_server() {
  run "kubectl apply -f infra/k8s-addons/metrics-server.yaml"
  run "kubectl -n kube-system rollout status deploy/metrics-server --timeout=120s"
}
```
phase 디스패치 case문과 `--from`/`--to` 순서 배열에도 `metrics-server`를 manifests 인접 위치로 등록(`--from` 도움말 문자열 28행도 갱신).

- [ ] **Step 3: 구문 검증**

Run:
```bash
bash -n scripts/bring-up.sh && echo "syntax OK"
tr -d '\r' < infra/k8s-addons/metrics-server.yaml > /tmp/lf.yaml && yamllint -c .yamllint /tmp/lf.yaml && echo clean
```
Expected: `syntax OK`, `clean`(yamllint 룰 위반 시 .yamllint 예외 패턴 확인).

- [ ] **Step 4: 커밋**

```bash
git add infra/k8s-addons/metrics-server.yaml scripts/bring-up.sh
git commit -m "feat(bring-up): metrics-server phase 추가(vendored, HPA 선행, WS4-2)"
```

### Task 3: prod 선행조건 런북 작성

**Files:** Create `docs/runbooks/prod-prereqs-netpol-metrics.md`

- [ ] **Step 1: 런북 작성**

`docs/runbooks/prod-prereqs-netpol-metrics.md` — prod ApplicationSet 활성화 전 체크리스트:
```markdown
# Runbook — prod 선행조건 (NetworkPolicy 집행 + HPA)

## 왜
prod 오버레이는 `netpol.yaml`(표준 k8s NetworkPolicy)·`hpa.yaml`(HPA)을 포함한다.
- NetworkPolicy는 **VPC CNI NetworkPolicy 컨트롤러**가 활성화돼야 집행된다(미활성 시 무시 — 보안 무효).
- HPA는 **metrics-server**가 있어야 동작(없으면 `unknown` 메트릭으로 스케일 불가).

## 검증 순서 (prod 윈도)
1. `kubectl -n kube-system get ds aws-node -o yaml | grep -i NETWORK_POLICY` → `ENABLE_NETWORK_POLICY=true`.
   아니면 terraform vpc-cni addon `enableNetworkPolicy` 재적용(WS4-1).
2. `kubectl -n kube-system get deploy metrics-server` Ready 1/1. 아니면 bring-up `--from metrics-server`(WS4-2).
3. netpol 집행 스모크: 임시 파드에서 차단 대상(예: gateway 라벨 없는 파드 → engagement:8080) 연결 실패 확인.
4. HPA 동작: `kubectl -n synapse-prod get hpa` 가 `TARGETS`에 실 메트릭(예: `cpu: 12%/70%`) 표시(`<unknown>` 아님).

## 비고
- dev/staging은 netpol/HPA prod 전용 → 미대상(리포트 §2.2).
- 이 선행조건 충족 후에만 prod ApplicationSet(Manual sync) 활성화.
```

- [ ] **Step 2: 커밋 + PR**

```bash
git add docs/runbooks/prod-prereqs-netpol-metrics.md
git commit -m "docs(runbook): prod 선행조건(netpol 집행+metrics-server) 체크리스트 (WS4-3)"
git push -u origin feat/prod-prereqs-netpol-metrics
gh pr create --repo team-project-final/synapse-gitops --base main --head feat/prod-prereqs-netpol-metrics \
  --title "feat: prod 선행조건 — vpc-cni netpol 컨트롤러 + metrics-server (WS4)" \
  --body "리포트 §2.5: prod 적용 시 VPC CNI NetworkPolicy 컨트롤러 + metrics-server 선행 필요. terraform addon enableNetworkPolicy + bring-up metrics-server phase + 검증 런북. 라이브 집행 검증은 prod 윈도."
```
Expected: PR URL, CI 통과.

---

## 의존성 / 권장 순서

```
WS3 (staging/prod Kafka SSL)  ── 클러스터 불필요, 즉시 머지 가능 ◀ 1순위
WS4 (prod 선행조건)            ── 클러스터 불필요(terraform validate+bash -n), 즉시 머지 ◀ 2순위
WS2 (engagement 이미지)        ── 서비스 레포 릴리스 → gitops 태그. 라이브 검증은 EKS 윈도
WS1 (gateway 이미지)           ── 서비스 레포 재빌드 → gitops 태그. 라이브 검증은 EKS 윈도
                                  (gateway 배포 경로는 기존 gateway-deploy-path 플랜과 정합)
라이브 검증(WS1·WS2·WS3·WS4)   ── 다음 EKS provision→verify→destroy 윈도에 일괄 (D-B)
```

- WS3·WS4는 렌더/lint/validate만으로 머지 가능(코드 회귀 차단). 라이브 런타임·집행 검증은 비용 패턴상 EKS 윈도로 묶는다.
- WS1·WS2의 gitops 태그 변경은 각 서비스 레포 CI가 새 이미지를 ECR에 올린 뒤 진행(또는 image-updater 자동 PR).
- gateway는 staging/prod 오버레이 자체가 없음 → 본 플랜은 dev 한정. gateway staging/prod 오버레이 + prod gateway netpol은 `infra/ingress/README.md`가 명시한 별도 후속.

## Self-Review (작성자 체크)

**Spec(리포트 §2.5) 커버리지:** ① gateway 이미지 경로+재빌드 → WS1(경로는 이미 정합 확인, 재빌드 Task) ✓. ② engagement Kafka 런타임(이미지 1.0.0<#21) → WS2 ✓. ③ staging/prod Kafka SSL → WS3 ✓. ④ prod netpol 컨트롤러+metrics-server → WS4 ✓.

**플레이스홀더 스캔:** `<new semver>`·cluster 리소스명·metrics-server 버전 등은 라이브/레포 실값 의존 토큰으로, 각 Step에 "실제 값 확인" 명령을 동반(코드 placeholder 아님 — 기존 gateway-deploy-path 플랜의 `<ACM_ARN>` 동일 관례). `terraform validate`·`bash -n`·`kubectl kustomize`로 각 산출물 검증 명령 명시.

**일관성:** SSL env 이름은 dev 실제값과 동일(`SPRING_KAFKA_SECURITY_PROTOCOL`, `SCHEMA_REGISTRY_KAFKASTORE_SECURITY_PROTOCOL`). 이미지 newName/ecr_repository = `synapse/<svc>`(슬래시) 통일. namespace synapse-{dev,staging,prod} 패턴 일관. phase 이름 `metrics-server`를 도움말·case·함수에 동일 적용.

**미해결 결정:** D-A(SSL 적용 범위)·D-B(라이브 시점)는 상단에 명시, 기본값으로 진행하되 Task 1(WS3)이 D-A를 데이터로 확정.
