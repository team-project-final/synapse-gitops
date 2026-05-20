# Bastion SSM 접근 가이드

## 사전 요구사항

1. **AWS CLI v2** 설치
2. **Session Manager Plugin** 설치:
   - Windows: `choco install session-manager-plugin`
   - macOS: `brew install --cask session-manager-plugin`
   - 확인: `session-manager-plugin --version`
3. **AWS 자격증명** 설정: `aws sts get-caller-identity` 정상 응답 확인

## 접속

### 1. Bastion Instance ID 확인

```bash
# terraform output으로 확인
cd infra/aws/dev
terraform output bastion_instance_id

# 또는 AWS CLI로 확인
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=synapse-dev-bastion" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text --region ap-northeast-2
```

### 2. SSM 세션 시작

```bash
aws ssm start-session --target <instance-id> --region ap-northeast-2
```

### 3. kubectl 사용

```bash
# kubeconfig는 User Data에서 자동 설정됨
kubectl get nodes
kubectl get pods -n synapse-dev
kubectl get configmap -n synapse-dev -o yaml | grep DATABASE_HOST
```

### 4. helm 확인

```bash
helm list -n argocd
helm list -n synapse-dev
```

## 트러블슈팅

### SSM 연결 실패

1. **Instance 상태 확인**: `aws ec2 describe-instance-status --instance-ids <id>`
   - running 상태인지 확인
2. **SSM Agent 상태 확인**: EC2 콘솔 → Fleet Manager → Managed Instances에서 bastion 확인
3. **IAM 권한 확인**: Instance Profile에 `AmazonSSMManagedInstanceCore` 정책 연결 확인
4. **네트워크 확인**: Public subnet에 Internet Gateway 연결 + Egress 443 허용 확인

### kubectl 인증 실패

1. **aws-auth ConfigMap 확인**:
   ```bash
   kubectl get configmap aws-auth -n kube-system -o yaml
   ```
2. Bastion IAM Role ARN이 `mapRoles`에 등록되어 있는지 확인
3. 없으면 등록:
   ```bash
   kubectl edit configmap aws-auth -n kube-system
   ```
   `mapRoles` 하위에 추가:
   ```yaml
   - rolearn: arn:aws:iam::963773969059:role/synapse-dev-bastion-role
     username: bastion
     groups:
       - system:masters
   ```

### User Data 실행 실패 (kubectl/helm 미설치)

SSM 접속 후 수동 설치:
```bash
# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kubeconfig
aws eks update-kubeconfig --name synapse-dev --region ap-northeast-2
```
