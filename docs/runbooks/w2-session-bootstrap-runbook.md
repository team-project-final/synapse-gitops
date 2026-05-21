# Runbook: W2 세션 인프라 기동 (매 세션 반복)

> **목적**: terraform destroy 후 다음 세션에서 인프라를 재기동하고 서비스 배포까지 완료하는 전체 절차
> **소요 시간**: 약 30~40분 (terraform apply ~25분 + 설정 ~10분)
> **사전 조건**: AWS 자격증명 설정 완료, terraform.tfvars 존재
> **비용**: 시간당 ~$0.41. 작업 완료 후 반드시 `terraform destroy`

---

## 전체 흐름

```
1. terraform apply (인프라 프로비저닝)
    ↓
2. EKS 인증 모드 변경 (CONFIG_MAP → API_AND_CONFIG_MAP)
    ↓
3. Bastion access entry 추가 (EKS API 접근 권한)
    ↓
4. SG 수정 (EKS cluster SG → RDS/Redis/MSK/OpenSearch)
    ↓
5. Bastion SSM 접속 + kubeconfig 설정
    ↓
6. ArgoCD 설치 (--server-side 필수)
    ↓
7. ESO 설치 + IRSA annotation
    ↓
8. OIDC Provider ID 확인 + ESO role trust policy 업데이트
    ↓
9. ClusterSecretStore + AppProject + ApplicationSet 적용
    ↓
10. 서비스 상태 확인
```

---

## Step 1. terraform apply

```bash
cd infra/aws/dev
terraform init   # 최초 또는 provider 변경 시
terraform apply -auto-approve
# 소요: ~25분 (MSK가 가장 오래 걸림 ~24분)
```

**예상 결과**: 45~46개 리소스 생성. `helm_release.argocd`는 EKS private endpoint로 인해 실패하지만, 이는 정상입니다 (Step 6에서 Bastion 경유 설치).

**에러 무시 가능**:
```
Error: Kubernetes cluster unreachable
  with helm_release.argocd
```
→ EKS가 private endpoint only이므로 로컬에서 Helm 설치 불가. Bastion에서 수동 설치.

---

## Step 2. EKS 인증 모드 변경

```bash
aws eks update-cluster-config \
  --name synapse-dev \
  --region ap-northeast-2 \
  --access-config authenticationMode=API_AND_CONFIG_MAP
```

**완료 확인** (3~5분 소요):
```bash
aws eks wait cluster-active --name synapse-dev --region ap-northeast-2
```

또는 update-id로 직접 확인:
```bash
aws eks describe-update --name synapse-dev --region ap-northeast-2 \
  --update-id <update-id> --query 'update.status' --output text
# Expected: Successful
```

---

## Step 3. Bastion access entry 추가

```bash
# Bastion role ARN 확인
BASTION_ROLE_ARN=$(aws iam get-role --role-name synapse-dev-bastion-role \
  --query 'Role.Arn' --output text)

# Access entry 생성
aws eks create-access-entry \
  --cluster-name synapse-dev \
  --region ap-northeast-2 \
  --principal-arn $BASTION_ROLE_ARN \
  --type STANDARD

# ClusterAdmin 정책 연결
aws eks associate-access-policy \
  --cluster-name synapse-dev \
  --region ap-northeast-2 \
  --principal-arn $BASTION_ROLE_ARN \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

---

## Step 4. SG 수정 (D-026)

매 terraform apply 후 EKS managed node group이 자체 SG(`eks-cluster-sg-*`)를 사용하므로, 이 SG를 인프라 서비스 SG에 수동 추가해야 합니다.

```bash
# EKS cluster SG 확인
EKS_SG=$(aws eks describe-cluster --name synapse-dev --region ap-northeast-2 \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
echo "EKS Cluster SG: $EKS_SG"

# 인프라 SG 확인 (이번 apply에서 생성된 것 — Name 태그 기준)
aws ec2 describe-security-groups --region ap-northeast-2 \
  --filters "Name=tag:Name,Values=*synapse*" \
  --query 'SecurityGroups[*].[GroupId,Tags[?Key==`Name`].Value|[0]]' --output text

# 위 결과에서 이번 apply의 SG ID를 확인 후 아래 실행
# RDS (port 5432)
aws ec2 authorize-security-group-ingress --region ap-northeast-2 \
  --group-id <RDS_SG_ID> --protocol tcp --port 5432 --source-group $EKS_SG

# Redis (port 6379)
aws ec2 authorize-security-group-ingress --region ap-northeast-2 \
  --group-id <REDIS_SG_ID> --protocol tcp --port 6379 --source-group $EKS_SG

# MSK (port 9094, TLS)
aws ec2 authorize-security-group-ingress --region ap-northeast-2 \
  --group-id <MSK_SG_ID> --protocol tcp --port 9094 --source-group $EKS_SG

# OpenSearch (port 443)
aws ec2 authorize-security-group-ingress --region ap-northeast-2 \
  --group-id <OPENSEARCH_SG_ID> --protocol tcp --port 443 --source-group $EKS_SG
```

> **SG 식별 팁**: 이번 apply에서 생성된 SG는 Name 태그에 최신 타임스탬프가 포함됩니다. 이전 apply의 잔여 SG(terraform state에서 빠진 것)가 있을 수 있으니 타임스탬프로 구분하세요.

---

## Step 5. Bastion SSM 접속

```powershell
# Windows PowerShell에서
$env:PATH += ";C:\Program Files\Amazon\SessionManagerPlugin\bin"

# Bastion instance ID 확인
terraform output bastion_instance_id
# 또는
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=synapse-dev-bastion" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" --output text --region ap-northeast-2

# SSM 접속
aws ssm start-session --target <BASTION_INSTANCE_ID> --region ap-northeast-2
```

Bastion 내부에서:
```bash
aws eks update-kubeconfig --name synapse-dev --region ap-northeast-2
kubectl get nodes
# Expected: 2개 노드 Ready
```

---

## Step 6. ArgoCD 설치

**반드시 `--server-side` 사용** (ApplicationSet CRD가 262KB 이상이라 client-side apply 시 annotation 크기 제한 초과):

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

HTTP 접근을 위한 `--insecure` 플래그 추가:
```bash
kubectl -n argocd patch deploy argocd-server --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--insecure"}]'
```

확인:
```bash
kubectl -n argocd get pods
# Expected: 모든 pod Running (7개)
```

> **주의**: `--server-side` 없이 설치하면 ApplicationSet CRD 생성 시 `metadata.annotations: Too long` 에러 발생. 이 경우 `kubectl apply --server-side --force-conflicts`로 재적용.

---

## Step 7. ESO 설치 + IRSA

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace

# IRSA annotation
kubectl -n external-secrets annotate sa external-secrets \
  eks.amazonaws.com/role-arn=arn:aws:iam::963773969059:role/synapse-dev-eso-role \
  --overwrite

# IRSA 반영을 위해 pod 재시작
kubectl -n external-secrets rollout restart deploy external-secrets
```

---

## Step 8. OIDC Provider ID 확인 + ESO role trust policy 업데이트

**매 terraform apply 후 EKS 클러스터가 재생성되면 OIDC Provider ID가 변경됩니다.** ESO role의 trust policy에 이전 OIDC ID가 남아 있으면 `InvalidProviderConfig` 에러가 발생합니다.

```bash
# 현재 EKS OIDC ID 확인
OIDC_URL=$(aws eks describe-cluster --name synapse-dev --region ap-northeast-2 \
  --query 'cluster.identity.oidc.issuer' --output text)
OIDC_ID=$(echo $OIDC_URL | awk -F'/' '{print $NF}')
echo "Current OIDC ID: $OIDC_ID"

# ESO role trust policy의 OIDC ID 확인
aws iam get-role --role-name synapse-dev-eso-role \
  --query 'Role.AssumeRolePolicyDocument' --output json
# → "Federated" 값의 OIDC ID가 위와 다르면 업데이트 필요
```

**불일치 시 업데이트**:
```bash
# OIDC_ID 변수에 현재 값이 들어있는 상태에서
aws iam update-assume-role-policy --role-name synapse-dev-eso-role \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Federated":"arn:aws:iam::963773969059:oidc-provider/oidc.eks.ap-northeast-2.amazonaws.com/id/'$OIDC_ID'"},"Action":"sts:AssumeRoleWithWebIdentity","Condition":{"StringEquals":{"oidc.eks.ap-northeast-2.amazonaws.com/id/'$OIDC_ID':aud":"sts.amazonaws.com","oidc.eks.ap-northeast-2.amazonaws.com/id/'$OIDC_ID':sub":"system:serviceaccount:external-secrets:external-secrets"}}}]}'

# ESO pod 재시작
kubectl -n external-secrets rollout restart deploy external-secrets
```

---

## Step 9. K8s 리소스 적용

Bastion에 git이 설치되어 있지 않으므로 `curl`로 GitHub raw 파일을 직접 적용합니다:

```bash
# ClusterSecretStore
curl -sL https://raw.githubusercontent.com/team-project-final/synapse-gitops/main/infra/external-secrets/cluster-secret-store.yaml | kubectl apply -f -

# AppProject
curl -sL https://raw.githubusercontent.com/team-project-final/synapse-gitops/main/argocd/projects.yaml | kubectl apply -f -

# ApplicationSet (dev — 자동 sync)
curl -sL https://raw.githubusercontent.com/team-project-final/synapse-gitops/main/argocd/applicationset.yaml | kubectl apply -f -

# ApplicationSet (staging — manual sync)
curl -sL https://raw.githubusercontent.com/team-project-final/synapse-gitops/main/argocd/applicationset-staging.yaml | kubectl apply -f -
```

> **참고**: Bastion에서 heredoc(`<<EOF`)을 사용한 멀티라인 YAML 입력은 SSM 세션에서 동작하지 않습니다. `curl | kubectl apply -f -` 패턴을 사용하세요.

---

## Step 10. 상태 확인

```bash
# ClusterSecretStore
kubectl get clustersecretstore
# Expected: Valid / Ready: True

# ExternalSecret
kubectl -n synapse-dev get externalsecret
# Expected: 5/5 SecretSynced

# ArgoCD Apps
kubectl -n argocd get apps
# Expected: 5개 dev (Synced) + 5개 staging (OutOfSync — manual sync 대기)

# Pod 상태
kubectl -n synapse-dev get pods
```

---

## Step 11. staging sync (선택)

dev 5/5 Healthy 확인 후 staging sync를 진행할 수 있습니다.

```bash
# synapse-staging 네임스페이스 생성 (최초 1회)
kubectl create namespace synapse-staging

# 각 서비스 manual sync (한 줄씩 실행)
kubectl -n argocd patch app synapse-platform-svc-staging --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD","syncOptions":["CreateNamespace=true"]}}}'
kubectl -n argocd patch app synapse-engagement-svc-staging --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD","syncOptions":["CreateNamespace=true"]}}}'
kubectl -n argocd patch app synapse-knowledge-svc-staging --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD","syncOptions":["CreateNamespace=true"]}}}'
kubectl -n argocd patch app synapse-learning-card-staging --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD","syncOptions":["CreateNamespace=true"]}}}'
kubectl -n argocd patch app synapse-learning-ai-staging --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD","syncOptions":["CreateNamespace=true"]}}}'
```

> **참고**: ArgoCD CLI(`/tmp/argocd app sync`)는 port-forward 문제가 발생할 수 있으므로 `kubectl patch` 방식을 권장합니다 (T-071 참조).

확인:
```bash
kubectl -n argocd get apps | grep staging
kubectl -n synapse-staging get pods
```

---

## Step 12. MSK 토픽 생성 (선택)

```bash
# Java 설치
sudo dnf install -y java-17-amazon-corretto-headless

# Kafka CLI 설치
curl -sL https://archive.apache.org/dist/kafka/3.7.0/kafka_2.13-3.7.0.tgz | tar xz -C /tmp
export PATH=$PATH:/tmp/kafka_2.13-3.7.0/bin

# TLS 설정
cat > /tmp/client.properties << 'PROPS'
security.protocol=SSL
PROPS

# 브로커 주소 확인 (매 apply 후 변경됨)
# 로컬에서: aws kafka get-bootstrap-brokers 명령으로 확인 후 설정
KAFKA_BROKERS="<현재_MSK_브로커_주소>"

# 연결 확인
kafka-broker-api-versions.sh --bootstrap-server "$KAFKA_BROKERS" --command-config /tmp/client.properties --timeout 10000

# 토픽 생성 (5개, replication-factor=2 — 브로커 2대)
for topic in platform.auth.user-registered-v1 knowledge.note.note-created-v1 knowledge.note.note-updated-v1 learning.card.review-completed-v1 learning.ai.cards-generated-v1; do kafka-topics.sh --bootstrap-server "$KAFKA_BROKERS" --create --topic "$topic" --partitions 3 --replication-factor 2 --config retention.ms=604800000 --config cleanup.policy=delete --command-config /tmp/client.properties; done

# 토픽 목록 확인
kafka-topics.sh --bootstrap-server "$KAFKA_BROKERS" --list --command-config /tmp/client.properties
```

> **주의**: replication-factor는 브로커 수 이하여야 함. dev 환경은 브로커 2대이므로 max 2. (T-082 참조)

---

## ArgoCD UI 접속 (선택)

별도 PowerShell 터미널에서:
```powershell
aws ssm start-session --target <BASTION_INSTANCE_ID> --region ap-northeast-2 \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["localhost"],"portNumber":["8080"],"localPortNumber":["9090"]}'
```

→ `http://localhost:9090` 접속

ArgoCD 초기 비밀번호:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

---

## 작업 종료 — 비용 차단

```bash
cd infra/aws/dev
terraform destroy -auto-approve
# 소요: ~30분
```

S3 state bucket + DynamoDB lock table은 유지 (다음 apply에 필요).
