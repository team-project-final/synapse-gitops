# SSM Bastion Host 설계 스펙

> **작성일**: 2026-05-20
> **범위**: EKS private endpoint 접근을 위한 SSM Bastion EC2 구성 + EKS public endpoint 비활성화
> **브랜치**: `feat/w2-ssm-bastion`

---

## 1. 목적

EKS public endpoint를 비활성화하고, Public Subnet에 SSM Session Manager 전용 Bastion EC2를 배치하여 보안 강화된 EKS 접근 경로를 구성한다. SSH 키 없이 IAM 인증만으로 접근하며, staging/prod 환경에서도 재사용 가능한 패턴을 확립한다.

---

## 2. 배경

- 핸드오프 D-017: EKS private endpoint로 인해 로컬에서 `helm list`, `kubectl` 접근 불가
- 기존 EKS public endpoint가 `0.0.0.0/0`으로 열려 있으나, 보안 정책상 비활성화 결정
- SSH 대신 SSM Session Manager 사용 → 22번 포트 불필요, 키 관리 불필요

---

## 3. 아키텍처

```
개발자 로컬
  │
  ├─ aws ssm start-session (HTTPS 443)
  │
  ▼
┌──────────────────────────────────────┐
│  Public Subnet (10.0.1.0/24)         │
│  ┌──────────────────────────────┐    │
│  │ EC2 Bastion (t3.micro)       │    │
│  │ - Amazon Linux 2023          │    │
│  │ - SSM Agent (기본 내장)       │    │
│  │ - kubectl, helm, aws cli     │    │
│  │ - No SSH key, No port 22     │    │
│  │ - IAM Role: EKS 최소 권한    │    │
│  └───────────┬──────────────────┘    │
└──────────────┼───────────────────────┘
               │ VPC 내부 통신
               ▼
┌──────────────────────────────────────┐
│  Private Subnet (10.0.10.0/24)       │
│  ┌──────────────────────────────┐    │
│  │ EKS Control Plane            │    │
│  │ (Private Endpoint Only)      │    │
│  └──────────────────────────────┘    │
└──────────────────────────────────────┘
```

---

## 4. 리소스 스펙

| 리소스 | 스펙 | 비용 |
|---|---|---|
| EC2 Instance | `t3.micro`, Amazon Linux 2023, 상시 운영 | ~$8/mo |
| EBS Volume | 8GB gp3 (기본) | ~$0.64/mo |
| IAM Role + Instance Profile | EKS 최소 권한 + SSM 관리형 정책 | 무료 |
| Security Group | Ingress 없음, Egress HTTPS only | 무료 |
| **예상 추가 비용** | | **~$9/mo** |

---

## 5. Terraform 리소스 목록

### 5.1 신규 파일: `infra/aws/dev/bastion.tf`

| 리소스 | 타입 | 설명 |
|---|---|---|
| `aws_iam_role.bastion` | IAM Role | Bastion EC2용 역할 |
| `aws_iam_role_policy.bastion_eks` | IAM Inline Policy | `eks:DescribeCluster`, `sts:GetCallerIdentity` |
| `aws_iam_role_policy_attachment.bastion_ssm` | Policy Attachment | `AmazonSSMManagedInstanceCore` 관리형 정책 |
| `aws_iam_instance_profile.bastion` | Instance Profile | EC2에 역할 연결 |
| `aws_security_group.bastion` | Security Group | Ingress 0, Egress 443 only |
| `aws_instance.bastion` | EC2 Instance | t3.micro, User Data로 도구 설치 |

### 5.2 기존 파일 수정: `infra/aws/dev/eks.tf`

| 변경 | 내용 |
|---|---|
| `endpoint_public_access` | `true` → `false` |
| EKS 보안그룹 Ingress | Bastion SG에서 443 허용 추가 |

### 5.3 기존 파일 수정: `infra/aws/dev/outputs.tf`

| 출력 | 내용 |
|---|---|
| `bastion_instance_id` | SSM 접속용 인스턴스 ID |

---

## 6. 보안 설계

### 6.1 Security Group

```
Bastion SG:
  Ingress: (없음)
  Egress:
    - 443/tcp → 0.0.0.0/0   (SSM endpoint + EKS API + HTTPS 패키지 다운로드)
```

### 6.2 IAM Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:ListClusters"
      ],
      "Resource": "arn:aws:eks:ap-northeast-2:963773969059:cluster/synapse-dev"
    },
    {
      "Effect": "Allow",
      "Action": "sts:GetCallerIdentity",
      "Resource": "*"
    }
  ]
}
```

SSM 접근은 `AmazonSSMManagedInstanceCore` 관리형 정책으로 처리.

### 6.3 보안 포인트

- SSH 키 없음, 22번 포트 없음
- Ingress 규칙 0개 — SSM은 EC2에서 아웃바운드 HTTPS로 SSM 서비스에 연결
- IAM 최소 권한 (EKS describe + STS only)
- CloudTrail에 SSM 세션 로그 자동 기록
- EKS public endpoint 비활성화 → VPC 내부에서만 API 접근 가능

---

## 7. User Data 스크립트

```bash
#!/bin/bash
set -euo pipefail

# kubectl 설치
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# helm 설치
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kubeconfig 설정
su - ssm-user -c "aws eks update-kubeconfig --name synapse-dev --region ap-northeast-2"
```

---

## 8. 접근 흐름

```bash
# 1. SSM으로 bastion 접속
aws ssm start-session --target <instance-id> --region ap-northeast-2

# 2. bastion 내에서 kubectl 사용
kubectl get pods -n synapse-dev
kubectl get configmap -n synapse-dev -o yaml | grep DATABASE_HOST

# 3. helm 확인
helm list -n argocd
```

---

## 9. EKS aws-auth ConfigMap

Bastion의 IAM Role을 EKS `aws-auth` ConfigMap에 등록해야 kubectl 인증이 동작한다.

```yaml
mapRoles:
  - rolearn: arn:aws:iam::963773969059:role/synapse-dev-bastion-role
    username: bastion
    groups:
      - system:masters
```

> 주의: dev 환경이므로 `system:masters`를 사용하나, staging/prod에서는 RBAC으로 세분화할 것.

---

## 10. 런북 문서

`docs/runbooks/bastion-ssm-access.md`에 접근 절차 가이드를 작성한다.

내용:
- 사전 요구사항 (AWS CLI, Session Manager plugin 설치)
- SSM 접속 명령
- kubectl/helm 사용법
- 트러블슈팅 (SSM 연결 실패 시 체크리스트)
