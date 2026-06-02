# EKS window 진입 마찰 제거 (#87/#88/#89) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 재apply(EKS window)마다의 수동 작업·차단 3건(#87 bastion kubectl 접근·#89 D-026 SG·#88 브로커 주소)을 terraform 영구 코드화하고 라이브 1회 검증한다.

**Architecture:** #87/#89는 AWS API만 쓰므로 로컬 terraform. #88의 k8s 리소스(ns+ConfigMap)는 EKS 엔드포인트가 private-only(`endpoint_public_access=false`)라 로컬에서 못 닿으므로 **bastion에서 실행**(2026-06-02 kafka-topics와 동일 base64-SSM 패턴). 라이브 검증은 ArgoCD 부트스트랩 없이 **경량 test pod**(bastion `kubectl run`)로 도달성·ConfigMap 전파만 증명.

**Tech Stack:** Terraform(hashicorp/aws ~>5.40, hashicorp/kubernetes ~>2.27), AWS EKS access entries, AWS SSM(bastion), kustomize, MSK(TLS).

**참조 spec:** `docs/superpowers/specs/2026-06-02-eks-window-entry-hardening-design.md`

**브랜치:** `infra/eks-window-entry-hardening` (spec 커밋됨).

**운영 학습(2026-06-02, 재사용):** SSM엔 스크립트를 **base64로 전달**(jq/heredoc은 newline 깨짐). `set -o pipefail`+`cmd|head`는 SIGPIPE(141). 토픽 RF≤브로커수(dev=2).

---

## File Structure

| 파일 | 책임 | 변경 |
|---|---|---|
| `infra/aws/dev/eks.tf` | cluster `access_config` + access entry/association | Modify |
| `infra/aws/dev/bastion.tf` | bastion IAM에 kafka read 추가 | Modify |
| `infra/aws/dev/vpc.tf` | 4개 인프라 SG에 cluster SG ingress | Modify |
| `apps/<svc>/base/deployment.yaml` | KAFKA_BROKERS env valueFrom(configMapKeyRef) | Modify ×5 |
| `apps/<svc>/overlays/<env>/kustomization.yaml` | KAFKA_BROKERS 하드코딩 patch 제거 | Modify ×15 |
| `infra/aws/dev/k8s-kafka-config/` | ns ×3 + kafka-brokers ConfigMap ×3 (bastion 실행) | Create |

---

## Phase 0 — 오프라인 작성 (무과금)

### Task 1: #87 — bastion EKS access entry + kafka read IAM

**Files:**
- Modify: `infra/aws/dev/eks.tf` (cluster block + 신규 access entry)
- Modify: `infra/aws/dev/bastion.tf` (IAM policy)

- [ ] **Step 1: 클러스터에 access_config 추가**

`eks.tf`의 `resource "aws_eks_cluster" "main"` `vpc_config` 블록 **다음 줄**(vpc_config 닫는 `}` 뒤)에 추가:
```hcl
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
```

- [ ] **Step 2: bastion access entry + policy association 추가 (eks.tf 끝에)**

`eks.tf` 파일 끝에 추가:
```hcl
# ─── bastion access entry (#87) ─────────────────────────────────────────────
resource "aws_eks_access_entry" "bastion" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.bastion.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "bastion_admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.bastion.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.bastion]
}
```

- [ ] **Step 3: bastion IAM에 kafka read 추가**

`bastion.tf`의 `aws_iam_role_policy.bastion_eks` `policy` jsonencode `Statement` 배열에 항목 추가(기존 eks/sts 항목 뒤):
```hcl
      {
        Effect = "Allow"
        Action = [
          "kafka:ListClustersV2",
          "kafka:GetBootstrapBrokers",
          "kafka:DescribeClusterV2"
        ]
        Resource = "*"
      },
```
(기존 마지막 항목 끝 콤마 정합 확인.)

- [ ] **Step 4: fmt + validate**

Run: `cd infra/aws/dev && terraform fmt && terraform validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 5: plan (무과금, 변경 미리보기)**

Run: `cd infra/aws/dev && terraform plan -no-color 2>&1 | grep -E "will be created|will be updated|aws_eks_access|access_config|Plan:"`
Expected: `aws_eks_access_entry.bastion` + `aws_eks_access_policy_association.bastion_admin` will be created, cluster will be updated in-place(access_config), bastion IAM policy update. (apply 아님.)

- [ ] **Step 6: Commit**

```bash
git add infra/aws/dev/eks.tf infra/aws/dev/bastion.tf
git commit -m "feat(infra): #87 bastion EKS access entry(cluster admin)+kafka read — kubectl 401 해소"
```

---

### Task 2: #89 — D-026 cluster SG를 4개 인프라 SG ingress에 코드화

**Files:**
- Modify: `infra/aws/dev/vpc.tf` (RDS/Redis/OpenSearch/MSK SG)

- [ ] **Step 1: cluster SG local 추가 (vpc.tf 또는 eks.tf locals 근처)**

`vpc.tf` 상단(또는 SG 정의 위)에 추가:
```hcl
# EKS 자동생성 cluster SG (managed node group 파드 트래픽 출처) — D-026
locals {
  eks_cluster_sg = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}
```

- [ ] **Step 2: MSK SG에 cluster SG ingress 추가**

`vpc.tf`의 `aws_security_group.msk` 블록, 기존 9094 ingress(EKS nodes) 옆에 추가:
```hcl
  ingress {
    description     = "Kafka TLS from EKS cluster SG (managed node group, D-026)"
    from_port       = 9094
    to_port         = 9094
    protocol        = "tcp"
    security_groups = [local.eks_cluster_sg]
  }
```

- [ ] **Step 3: RDS/Redis/OpenSearch SG에 cluster SG ingress 추가**

각 SG 블록의 기존 eks_nodes ingress 옆에 동일 패턴 추가:
- `aws_security_group.rds` (또는 rds.tf SG): 5432
```hcl
  ingress {
    description     = "Postgres from EKS cluster SG (D-026)"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [local.eks_cluster_sg]
  }
```
- Redis SG: from/to 6379, description `"Redis from EKS cluster SG (D-026)"`.
- OpenSearch SG: from/to 443, description `"HTTPS from EKS cluster SG (D-026)"`.

(SG가 vpc.tf 아닌 rds.tf/redis.tf/opensearch.tf에 있으면 해당 파일에서 수정. `local.eks_cluster_sg`는 전역 참조 가능.)

- [ ] **Step 4: fmt + validate + plan**

Run: `cd infra/aws/dev && terraform fmt && terraform validate && terraform plan -no-color 2>&1 | grep -E "will be updated|ingress|Plan:"`
Expected: validate Success. plan: 4개 SG가 in-place update(ingress 추가). cycle 에러 없음.

- [ ] **Step 5: Commit**

```bash
git add infra/aws/dev/vpc.tf infra/aws/dev/rds.tf infra/aws/dev/redis.tf infra/aws/dev/opensearch.tf
git commit -m "feat(infra): #89 D-026 — EKS cluster SG를 RDS/Redis/OpenSearch/MSK ingress에 코드화"
```
(실제 변경된 파일만 add.)

---

### Task 3: #88-A — overlay 하드코딩 제거 + base deployment valueFrom

**Files:**
- Modify: `apps/<svc>/base/deployment.yaml` ×5
- Modify: `apps/<svc>/overlays/<env>/kustomization.yaml` ×15

- [ ] **Step 1: 5개 base deployment에 KAFKA_BROKERS env valueFrom 추가**

각 `apps/<svc>/base/deployment.yaml`의 컨테이너 spec에서 `envFrom:` **앞**(또는 컨테이너에 `env:` 없으면 신규)에 추가:
```yaml
          env:
            - name: KAFKA_BROKERS
              valueFrom:
                configMapKeyRef:
                  name: kafka-brokers
                  key: KAFKA_BROKERS
```
대상 5개: engagement-svc, knowledge-svc, learning-ai, learning-card, platform-svc. (이미 `env:` 블록이 있으면 그 안에 항목 추가.) 명시 env가 envFrom의 동명 키를 override하므로, 다음 Step에서 service ConfigMap의 KAFKA_BROKERS는 제거.

- [ ] **Step 2: 15개 overlay에서 KAFKA_BROKERS 하드코딩 patch 제거**

각 `apps/<svc>/overlays/<env>/kustomization.yaml`에서 ConfigMap patch의 다음 2줄(JSON6902 add op)을 삭제:
```yaml
      - op: add
        path: /data/KAFKA_BROKERS
        value: "b-1.synapsedevkafka.4ki14g.c2.kafka.ap-northeast-2.amazonaws.com:9094,b-2.synapsedevkafka.4ki14g.c2.kafka.ap-northeast-2.amazonaws.com:9094"
```
(svc×env 15곳. value 문자열은 동일.)

- [ ] **Step 3: kustomize 렌더 검증 (KAFKA_BROKERS가 valueFrom로 나오는지)**

Run:
```bash
for svc in engagement-svc knowledge-svc learning-ai learning-card platform-svc; do
  kubectl kustomize apps/$svc/overlays/dev > /tmp/r.yaml 2>/tmp/r.err && \
  grep -q "configMapKeyRef" /tmp/r.yaml && ! grep -q "synapsedevkafka.4ki14g" /tmp/r.yaml && \
  echo "$svc: OK" || { echo "$svc: FAIL"; tail -3 /tmp/r.err; grep -n "KAFKA_BROKERS" /tmp/r.yaml; }
done
```
Expected: 5개 `OK` (configMapKeyRef 존재 + 하드코딩 DNS 부재).

- [ ] **Step 4: Commit**

```bash
git add apps/
git commit -m "refactor(overlays): #88 KAFKA_BROKERS를 공유 kafka-brokers ConfigMap 참조로 전환 (하드코딩 15곳 제거)"
```

---

### Task 4: #88-B — bastion 실행용 k8s-kafka-config terraform 모듈

**Files:**
- Create: `infra/aws/dev/k8s-kafka-config/versions.tf`
- Create: `infra/aws/dev/k8s-kafka-config/variables.tf`
- Create: `infra/aws/dev/k8s-kafka-config/main.tf`
- Create: `infra/aws/dev/k8s-kafka-config/README.md`

- [ ] **Step 1: versions.tf**

`infra/aws/dev/k8s-kafka-config/versions.tf`:
```hcl
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
  }
}

# bastion 내부 실행 전제: kubeconfig는 user_data에서 update-kubeconfig 완료(bastion.tf).
provider "kubernetes" {
  config_path = "~/.kube/config"
}
```

- [ ] **Step 2: variables.tf**

`infra/aws/dev/k8s-kafka-config/variables.tf`:
```hcl
variable "kafka_brokers" {
  description = "MSK TLS bootstrap brokers (terraform output msk_bootstrap_brokers_tls)."
  type        = string
}

variable "namespaces" {
  description = "서비스가 도는 네임스페이스."
  type        = list(string)
  default     = ["synapse-dev", "synapse-staging", "synapse-prod"]
}
```

- [ ] **Step 3: main.tf (ns ×3 + ConfigMap ×3)**

`infra/aws/dev/k8s-kafka-config/main.tf`:
```hcl
resource "kubernetes_namespace" "app" {
  for_each = toset(var.namespaces)
  metadata {
    name = each.value
  }
  lifecycle {
    # ArgoCD CreateNamespace=true와 공존 — 라벨/주석 드리프트 무시
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }
}

resource "kubernetes_config_map" "kafka_brokers" {
  for_each = kubernetes_namespace.app
  metadata {
    name      = "kafka-brokers"
    namespace = each.value.metadata[0].name
  }
  data = {
    KAFKA_BROKERS = var.kafka_brokers
  }
}
```

- [ ] **Step 4: README.md (bastion 실행 절차)**

`infra/aws/dev/k8s-kafka-config/README.md`:
```markdown
# kafka-brokers ConfigMap (bastion 실행)

EKS 엔드포인트가 private-only → **bastion에서 실행**(로컬 terraform 도달 불가).
#87(access entry) 적용 + bastion `update-kubeconfig` 완료가 전제.

## 절차
1. 로컬: `cd infra/aws/dev && terraform output -raw msk_bootstrap_brokers_tls`
2. bastion(SSM)에 terraform 설치 + 이 디렉터리 전송(base64) — 2026-06-02 kafka-topics 패턴.
3. bastion: `terraform init && terraform apply -var="kafka_brokers=<brokers>"`
4. 검증: `kubectl get configmap kafka-brokers -n synapse-dev -o jsonpath='{.data.KAFKA_BROKERS}'`

## 폴백
private endpoint·bastion 경로가 막히면 spec §6 폴백(단일 공유 base ConfigMap, git 1곳 수동).
```

- [ ] **Step 5: fmt + validate (offline)**

Run: `cd infra/aws/dev/k8s-kafka-config && terraform fmt -check && terraform init -backend=false && terraform validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 6: Commit**

```bash
git add infra/aws/dev/k8s-kafka-config/
git commit -m "feat(infra): #88 kafka-brokers ConfigMap terraform 모듈(bastion 실행, ns 소유)"
```

---

## Phase 1 — 라이브 검증 window (유료 1회)

### Task 5: 인프라 apply (#87 access entry + #89 SG)

- [ ] **Step 1: apply**

Run: `cd infra/aws/dev && terraform init && terraform apply -no-color > apply.log 2>&1; grep -E "Apply complete|Error:" apply.log | tail`
Expected: `Apply complete!` (~60+ 리소스, access entry·SG 포함).

- [ ] **Step 2: output 확보**

Run:
```bash
cd infra/aws/dev
terraform output -raw msk_bootstrap_brokers_tls
terraform output -raw bastion_instance_id
aws eks describe-cluster --name synapse-dev --query 'cluster.accessConfig.authenticationMode' --output text
```
Expected: 브로커·bastion id, authMode = `API_AND_CONFIG_MAP`.

---

### Task 6: #87 검증 — bastion kubectl 접근

- [ ] **Step 1: bastion에서 kubectl get nodes (base64-SSM)**

로컬에서 검증 스크립트를 작성→base64→SSM send-command(2026-06-02 패턴). 스크립트 내용:
```bash
export PATH=$PATH:/usr/local/bin
aws eks update-kubeconfig --name synapse-dev --region ap-northeast-2
kubectl get nodes -o wide
kubectl auth can-i '*' '*' --all-namespaces && echo "ADMIN_OK"
```
전송: `B64=$(base64 -w0 verify87.sh); aws ssm send-command --instance-ids <bastion> --document-name AWS-RunShellScript --parameters commands="[\"echo $B64 | base64 -d > /tmp/v.sh && bash /tmp/v.sh\"]"` → `aws ssm wait command-executed` → `get-command-invocation`.
Expected: 노드 목록 출력 + `ADMIN_OK` (=#87 access entry 동작, kubectl 401 해소).

---

### Task 7: #89 검증 — 파드→인프라 도달 (경량 test pod)

- [ ] **Step 1: bastion에서 test pod로 인프라 포트 도달 확인**

스크립트(base64-SSM):
```bash
export PATH=$PATH:/usr/local/bin
BROKERS="<msk_bootstrap_brokers_tls 첫 브로커 host>"
kubectl run nettest --rm -i --restart=Never --image=busybox:1.36 -n synapse-dev -- sh -c "
  nc -z -w5 $BROKERS 9094 && echo MSK_OK || echo MSK_FAIL
"
```
(RDS/Redis/OpenSearch도 동일하게 host:port nc 확인 — 각 terraform output endpoint 사용. test pod는 managed node group=cluster SG에서 기동되므로 #89 검증.)
Expected: `MSK_OK`(+ RDS/Redis/OpenSearch OK). 수동 SG 추가 없이 도달 = #89 충족.

> 비고: `verify-argocd-deploy.sh 5/5`(이슈 acceptance 원문)는 ArgoCD 부트스트랩+앱 배포 선행이라 본 window 범위 밖. SG 도달성은 test pod로 동등 증명, 5/5는 ArgoCD bootstrap 후속에서.

---

### Task 8: #88 검증 — bastion에서 ConfigMap apply + 전파

- [ ] **Step 1: k8s-kafka-config를 bastion에서 apply**

`k8s-kafka-config/README.md` 절차: terraform 설치(이미 있으면 skip)+모듈 전송(base64)+`terraform apply -var="kafka_brokers=<brokers>"`. (SSM, 2026-06-02 패턴.)
Expected: `Apply complete!` — ns ×3(기존이면 no-op/adopt) + ConfigMap ×3 created.

- [ ] **Step 2: ConfigMap 값 검증**

bastion 스크립트:
```bash
for ns in synapse-dev synapse-staging synapse-prod; do
  echo "$ns: $(kubectl get configmap kafka-brokers -n $ns -o jsonpath='{.data.KAFKA_BROKERS}')"
done
```
Expected: 3개 ns 모두 신규 브로커 주소.

- [ ] **Step 2b: test pod가 configMapKeyRef로 env 수신**

```bash
kubectl run envtest --rm -i --restart=Never --image=busybox:1.36 -n synapse-dev \
  --overrides='{"spec":{"containers":[{"name":"envtest","image":"busybox:1.36","command":["sh","-c","echo KAFKA_BROKERS=$KAFKA_BROKERS"],"env":[{"name":"KAFKA_BROKERS","valueFrom":{"configMapKeyRef":{"name":"kafka-brokers","key":"KAFKA_BROKERS"}}}]}]}}'
```
Expected: `KAFKA_BROKERS=b-1...:9094,...` (=#88 전파 동작).

---

### Task 9: 마감 — 이슈 클로즈 + destroy + HISTORY + PR

- [ ] **Step 1: 이슈 결과 코멘트 + close**

Run (검증 증거 인용):
```bash
gh issue comment 87 --body "라이브 검증: access entry(API_AND_CONFIG_MAP, cluster admin)로 bastion kubectl get nodes 성공·ADMIN_OK. kafka read IAM 추가. PR <#>."
gh issue comment 89 --body "라이브 검증: EKS cluster SG를 4 인프라 SG ingress 코드화 → test pod에서 MSK/RDS/Redis/OpenSearch 도달(수동 SG 0). PR <#>."
gh issue comment 88 --body "라이브 검증: terraform kubernetes_config_map(bastion 실행)으로 kafka-brokers ConfigMap 3 ns 생성·test pod env 전파. 하드코딩 15곳 제거. PR <#>."
gh issue close 87 89 88
```
(PR 번호는 Step 4 후 채움 — 또는 close는 PR 머지 시 자동.)

- [ ] **Step 2: destroy (과금 차단)**

Run: `cd infra/aws/dev && terraform destroy -no-color -auto-approve > destroy.log 2>&1; grep -E "Destroy complete|Error:" destroy.log | tail; aws kafka list-clusters --query 'length(ClusterInfoList)' --output text`
Expected: `Destroy complete!`, MSK count 0. (k8s-kafka-config state는 bastion 소멸과 함께 stale 허용.)

- [ ] **Step 3: HISTORY D-045 + 마감 문서**

`docs/project-management/history/HISTORY_gitops.md`에 2026-06-02 항목 추가(D-045): #87 access entry·#89 SG·#88 ConfigMap 라이브 검증 결과, private endpoint→bastion 실행 결정. Commit:
```bash
git add docs/project-management/history/HISTORY_gitops.md
git commit -m "docs(infra): #87/#88/#89 라이브 검증 마감 — HISTORY D-045"
```

- [ ] **Step 4: push + PR**

```bash
git push -u origin infra/eks-window-entry-hardening
gh pr create --base main --title "feat(infra): EKS window 진입 마찰 제거 (#87/#88/#89)" --body "spec/plan 참조. #87 access entry·#89 D-026 SG·#88 브로커 ConfigMap. 라이브 검증 후 destroy. Closes #87 #88 #89"
```

---

## Self-Review (작성자 점검)

**Spec coverage:**
- §4 #87(access_config+access entry+kafka IAM) → Task 1·6 ✅
- §5 #89(cluster SG 4 인프라 SG) → Task 2·7 ✅
- §6 #88(kubernetes_config_map+ns 소유+overlay valueFrom) → Task 3·4·8 ✅
- §7 라이브 window(apply/검증/destroy/PR) → Task 5~9 ✅
- §8 private endpoint 리스크 → #88을 bastion 실행으로 해소(Task 4·8), 폴백 README 명시 ✅

**Placeholder scan:** TBD/TODO 없음. 모든 코드 스텝 실제 HCL/YAML/명령 포함. (Task 9 PR번호는 실행시점 확정 — 정상.)

**Type consistency:** `local.eks_cluster_sg`(Task 2 정의·사용 일치), ConfigMap 이름 `kafka-brokers`·키 `KAFKA_BROKERS`(Task 3 valueFrom ↔ Task 4 ConfigMap ↔ Task 8 검증 일치), `var.kafka_brokers`(Task 4 변수·apply 일치). access entry 리소스명 `aws_eks_access_entry.bastion`·association `bastion_admin`(Task 1·plan 일치).

**리스크(spec §8):** #88 bastion 실행 경로는 #87 적용+bastion update-kubeconfig 성공 의존 → Task 6에서 kubectl 동작 확인 후 Task 8 진행(순서 보장). 막히면 폴백(단일 base).
