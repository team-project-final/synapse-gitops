# Synapse dev AWS 인프라

이 디렉터리는 Synapse W1 P0 기준의 dev AWS 인프라 베이스라인을 정의한다.

## 범위

- 관리형 노드 3개를 가진 EKS dev 클러스터
- private 접근만 허용하는 RDS PostgreSQL 16
- TLS broker 통신을 사용하는 MSK Kafka 3.x 3 broker
- EKS 내부 private 클러스터 네트워크에서 실행되는 Schema Registry
- AUTH와 in-transit encryption을 사용하는 ElastiCache Redis 7
- private 접근만 허용하는 OpenSearch 8 호환 dev 도메인
- 배포 대상 5개 서비스용 ECR repository
- 5개 서비스 x 3개 환경 ApplicationSet을 포함한 ArgoCD

## 적용

```bash
terraform init
terraform plan \
  -var='database_password=<RDS_ADMIN_PASSWORD>' \
  -var='redis_auth_token=<REDIS_AUTH_TOKEN>'
terraform apply \
  -var='database_password=<RDS_ADMIN_PASSWORD>' \
  -var='redis_auth_token=<REDIS_AUTH_TOKEN>'
```

`*.tfvars`, state 파일, 비밀번호, Redis 토큰, kubeconfig, 생성된 ArgoCD admin password는 커밋하지 않는다.

## Smoke Test

```bash
aws eks update-kubeconfig --name synapse-dev --region ap-northeast-2
kubectl get nodes
kubectl get pods -A
kubectl get applications -n argocd
```

데이터 서비스 접속 확인은 EKS debug pod, SSM session, VPN, bastion host처럼 VPC 내부 경로에서 실행한다.

`admin_cidr_blocks`가 비어 있으면 EKS API endpoint는 private only로 생성된다. 이 경우 Terraform은 VPC 내부 네트워크 경로에서 실행하거나, 승인된 임시 관리자 CIDR을 좁게 지정한다.

## 비용 주의

TASK 기준은 EKS 노드 3개와 MSK 3 broker를 요구한다. 이는 통합 개발을 위한 최소 토폴로지지만, region, 실행 시간, NAT 사용량에 따라 월 dev 예산을 초과할 수 있다. 유휴 dev 환경은 제거하고, 스케일 다운은 팀장 승인 후 진행한다.
