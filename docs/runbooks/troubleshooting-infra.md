# Troubleshooting: 인프라 문제 해결 가이드

> **목적**: terraform apply 후 인프라 기동 과정에서 발생하는 알려진 문제와 해결 방법
> **대상**: 인프라 담당자, 세션 기동 시 참조
> **관련 문서**: [w2-session-bootstrap-runbook.md](./w2-session-bootstrap-runbook.md)

---

## 목차

1. [terraform apply 에러](#1-terraform-apply-에러)
2. [EKS 접근 관련](#2-eks-접근-관련)
3. [ArgoCD 설치 관련](#3-argocd-설치-관련)
4. [ESO / ClusterSecretStore 관련](#4-eso--clustersecretstore-관련)
5. [SG (Security Group) 관련](#5-sg-security-group-관련)
6. [서비스 Pod 관련](#6-서비스-pod-관련)
7. [SSM Bastion 관련](#7-ssm-bastion-관련)

---

## 1. terraform apply 에러

### T-001: `helm_release.argocd` — Kubernetes cluster unreachable

```
Error: Kubernetes cluster unreachable: dial tcp 10.0.x.x:443: connectex: ...
  with helm_release.argocd
```

**원인**: EKS 클러스터가 private endpoint only로 설정되어 로컬에서 Helm 설치 불가.

**해결**: 이 에러는 무시 가능. ArgoCD는 Bastion SSM 접속 후 수동 설치 (Step 6).

**영향**: terraform state에 `helm_release.argocd`가 누락되지만 기능에는 영향 없음. 다음 `terraform apply` 시 동일 에러 반복.

---

### T-002: `Error creating EKS Node Group`

**원인**: AWS 계정 결제수단 verification 미완료.

**해결**: AWS 콘솔 → Billing → Payment methods → verification 완료 후 재시도.

---

### T-003: `Error creating OpenSearch Domain` — service-linked role

**원인**: OpenSearch service-linked role 미생성.

**해결**:
```bash
aws iam create-service-linked-role --aws-service-name opensearchservice.amazonaws.com
terraform apply -auto-approve
```

---

## 2. EKS 접근 관련

### T-010: `Unable to connect to the server: dial tcp ... i/o timeout`

```
Unable to connect to the server: dial tcp 10.0.10.32:443: i/o timeout
```

**원인**: EKS가 private endpoint only. 로컬 kubectl은 EKS API에 직접 접근 불가.

**해결**: 반드시 **Bastion SSM 접속 후** kubectl 사용.
```powershell
aws ssm start-session --target <BASTION_INSTANCE_ID> --region ap-northeast-2
```
```bash
aws eks update-kubeconfig --name synapse-dev --region ap-northeast-2
kubectl get nodes
```

---

### T-011: EKS 인증 모드 변경 후 `InProgress` 상태 지속

**원인**: EKS config 변경은 3~5분 소요.

**해결**: `aws eks wait cluster-active`로 대기하거나, describe-update로 상태 폴링.
```bash
aws eks wait cluster-active --name synapse-dev --region ap-northeast-2
```

---

### T-012: access entry 생성 후에도 kubectl 권한 없음

**원인**: access policy 연결 누락.

**해결**: access entry 생성 후 반드시 policy 연결:
```bash
aws eks associate-access-policy \
  --cluster-name synapse-dev --region ap-northeast-2 \
  --principal-arn <BASTION_ROLE_ARN> \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

---

## 3. ArgoCD 설치 관련

### T-020: `metadata.annotations: Too long` — ApplicationSet CRD

```
The CustomResourceDefinition "applicationsets.argoproj.io" is invalid:
  metadata.annotations: Too long: must have at most 262144 bytes
```

**원인**: ArgoCD CRD가 262KB를 초과하여 client-side apply의 `kubectl.kubernetes.io/last-applied-configuration` annotation 제한에 걸림.

**해결**: `--server-side` 플래그 사용:
```bash
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

이미 client-side로 설치한 경우 `--force-conflicts` 추가:
```bash
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

---

### T-021: `no matches for kind "ApplicationSet"`

```
error: resource mapping not found for name: "synapse-apps" namespace: "argocd"
  no matches for kind "ApplicationSet" in version "argoproj.io/v1alpha1"
```

**원인**: T-020으로 인해 ApplicationSet CRD가 생성되지 않은 상태.

**해결**: T-020 해결 후 ApplicationSet 재적용.

---

### T-022: `--server-side` 적용 시 conflict 에러

```
Apply failed with 1 conflict: conflict with "kubectl-client-side-apply" ...
Apply failed with 1 conflict: conflict with "kubectl-patch" ...
```

**원인**: 이전에 client-side apply 또는 patch로 관리되던 필드가 존재.

**해결**: `--force-conflicts` 추가:
```bash
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

이 conflict는 ArgoCD 기능에 영향 없음 (deployment, networkpolicy 필드 충돌). ApplicationSet CRD + 핵심 리소스는 정상 적용됨.

---

## 4. ESO / ClusterSecretStore 관련

### T-030: ClusterSecretStore `InvalidProviderConfig` / Ready: False

```
NAME                  STATUS                  READY
aws-secrets-manager   InvalidProviderConfig   False
```

**원인**: ESO role의 trust policy에 있는 OIDC Provider ID가 현재 EKS 클러스터의 OIDC ID와 불일치. terraform destroy → apply 시 EKS 클러스터가 재생성되면서 OIDC ID가 매번 변경됨.

**진단**:
```bash
# 현재 EKS OIDC ID
aws eks describe-cluster --name synapse-dev --region ap-northeast-2 \
  --query 'cluster.identity.oidc.issuer' --output text
# → .../id/XXXXXXX

# ESO role trust policy의 OIDC ID
aws iam get-role --role-name synapse-dev-eso-role \
  --query 'Role.AssumeRolePolicyDocument' --output json
# → "Federated" 값에서 OIDC ID 확인
```

**해결**: trust policy 업데이트:
```bash
OIDC_ID=<현재_OIDC_ID>
aws iam update-assume-role-policy --role-name synapse-dev-eso-role \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Federated":"arn:aws:iam::963773969059:oidc-provider/oidc.eks.ap-northeast-2.amazonaws.com/id/'$OIDC_ID'"},"Action":"sts:AssumeRoleWithWebIdentity","Condition":{"StringEquals":{"oidc.eks.ap-northeast-2.amazonaws.com/id/'$OIDC_ID':aud":"sts.amazonaws.com","oidc.eks.ap-northeast-2.amazonaws.com/id/'$OIDC_ID':sub":"system:serviceaccount:external-secrets:external-secrets"}}}]}'

# ESO pod 재시작
kubectl -n external-secrets rollout restart deploy external-secrets
```

**예방**: terraform의 `aws_iam_role.eso`에서 trust policy가 `aws_iam_openid_connect_provider.eks` ARN을 참조하도록 수정하면 자동 갱신됨.

---

### T-031: ExternalSecret `SecretSyncedError`

**원인**: AWS Secrets Manager에 해당 시크릿이 없거나 값이 비어있음.

**진단**:
```bash
kubectl -n synapse-dev describe externalsecret <name>
# Events 섹션에서 구체적 에러 확인

# AWS SM에 시크릿 존재 확인
aws secretsmanager list-secrets --region ap-northeast-2 \
  --query 'SecretList[*].Name' --output table
```

---

## 5. SG (Security Group) 관련

### T-040: 서비스가 RDS/Redis/MSK/OpenSearch에 연결 실패 (D-026)

**원인**: EKS managed node group은 terraform이 생성한 `eks_nodes` SG가 아닌 자체 `eks-cluster-sg-*` SG를 사용. 이 SG가 인프라 서비스 SG의 인바운드에 등록되어 있지 않음.

**진단**:
```bash
# EKS cluster SG 확인
aws eks describe-cluster --name synapse-dev --region ap-northeast-2 \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text

# 인프라 SG의 인바운드 규칙에 위 SG가 있는지 확인
aws ec2 describe-security-groups --group-ids <RDS_SG_ID> \
  --query 'SecurityGroups[0].IpPermissions' --output json
```

**해결**: [w2-session-bootstrap-runbook.md](./w2-session-bootstrap-runbook.md) Step 4 참조.

**예방**: terraform에서 `aws_eks_cluster.main.vpc_config[0].cluster_security_group_id`를 각 인프라 SG의 ingress source로 참조하도록 수정.

---

### T-041: 이전 apply의 잔여 SG 존재

```
aws ec2 describe-security-groups --filters "Name=tag:Name,Values=*synapse*"
# → 동일 이름의 SG가 여러 개 표시됨
```

**원인**: terraform destroy가 완전히 정리되지 않거나, 이전 state에서 누락된 SG.

**해결**: Name 태그의 타임스탬프 접미사로 이번 apply에서 생성된 SG를 식별. 이전 SG는 수동 삭제 가능 (의존성 없는 경우).

---

## 6. 서비스 Pod 관련

### T-050: platform-svc CrashLoopBackOff — `mfa_credentials` 테이블 미존재 (D-024)

**원인**: Flyway migration에 테이블 생성 DDL이 누락되어 있고, `ddl-auto: validate`로 설정되어 있었음.

**해결**: `application-dev.yml`에서 `ddl-auto: update`로 변경 (PR #26 머지 완료). ECR re-push 필요.

---

### T-051: learning-ai CrashLoopBackOff — 포트 불일치

**원인**: gitops의 containerPort/liveness probe가 8000이었으나 앱 Dockerfile은 8090 사용.

**해결**: gitops에서 포트를 8090으로 통일 (PR #38 머지 완료).

---

### T-052: Spring Boot 서비스 liveness probe 실패 (D-028)

**원인**: `initialDelaySeconds: 30s`로는 Spring Boot 4.0 + DB migration 기동 시간(~40-60초) 부족.

**해결**: `initialDelaySeconds`를 90s(Spring Boot) 또는 60s(기타)로 변경 (PR #35 머지 완료).

---

### T-053: Pod `Degraded` but `Synced`

**원인**: ArgoCD가 매니페스트를 정상 sync했지만 Pod 자체가 비정상 (CrashLoop, ImagePullBackOff 등).

**진단**:
```bash
kubectl -n synapse-dev describe pod <pod-name>
kubectl -n synapse-dev logs <pod-name> --tail=50
```

---

## 7. SSM Bastion 관련

### T-060: `TargetNotConnected` — SSM 접속 실패

```
An error occurred (TargetNotConnected) when calling the StartSession operation:
  i-08399527c6f112cee is not connected.
```

**원인**: 이전 terraform apply의 Bastion instance ID를 사용. terraform destroy → apply 시 새 인스턴스 생성.

**해결**: 최신 instance ID 확인:
```bash
terraform output bastion_instance_id
# 또는
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=synapse-dev-bastion" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" --output text --region ap-northeast-2
```

---

### T-061: Bastion에서 `git: command not found`

**원인**: Bastion AMI(Amazon Linux 2023)에 git 미설치.

**해결**: git clone 대신 `curl`로 GitHub raw 파일 직접 사용:
```bash
curl -sL https://raw.githubusercontent.com/team-project-final/synapse-gitops/main/<path> | kubectl apply -f -
```

또는 git 설치:
```bash
sudo dnf install -y git
```

---

### T-062: SSM 세션에서 멀티라인 YAML 붙여넣기 실패

**원인**: SSM 세션은 heredoc(`<<EOF`)를 사용한 멀티라인 입력이 불안정.

**해결**: `curl | kubectl apply -f -` 패턴 사용 (T-061 참조). 또는 로컬에서 파일을 base64 인코딩하여 전달:
```bash
# 로컬에서
base64 -w0 file.yaml | clip

# Bastion에서
echo "<붙여넣기>" | base64 -d | kubectl apply -f -
```

---

## 발견 사항 이력 (Discovery Log)

| ID | 내용 | 상태 | 해결 방법 |
|---|---|:---:|---|
| D-016 | terraform state drift | Open | OIDC, SG 수동 수정 시 terraform import 필요 |
| D-021 | OIDC Provider ID 불일치 | 반복 | 매 apply 후 T-030 절차 수행 |
| D-024 | platform-svc mfa_credentials 테이블 | 해결 | ddl-auto: update (PR #26) |
| D-026 | EKS managed node group SG 불일치 | 반복 | 매 apply 후 T-040 절차 수행 |
| D-027 | EKS 인증 모드 CONFIG_MAP only | 해결 | API_AND_CONFIG_MAP + access entry |
| D-028 | liveness probe delay 부족 | 해결 | initialDelaySeconds 90s (PR #35) |
