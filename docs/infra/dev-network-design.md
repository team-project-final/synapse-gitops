# Synapse dev 네트워크 설계표

이 문서는 W1 AWS 인프라 프로비저닝 Step의 VPC, subnet, route table, security group 설계를 기록한다. 실제 값은 Terraform apply 후 output과 AWS 콘솔 값을 기준으로 갱신한다.

## 1. 설계 원칙

| 원칙 | 적용 방식 |
| --- | --- |
| 데이터 계층 private only | RDS, MSK, Redis, OpenSearch는 private subnet에 배치한다. |
| EKS 중심 접근 | 데이터 계층 inbound는 EKS cluster security group에서만 허용한다. |
| 공개 진입점 최소화 | dev 기준 ArgoCD와 내부 서비스는 ClusterIP를 기본값으로 둔다. |
| 관리자 접근 제한 | EKS API public endpoint는 `admin_cidr_blocks`가 있을 때만 제한적으로 연다. 기본은 private endpoint다. |
| 비밀 정보 비공개 | endpoint, password, token, kubeconfig, ArgoCD admin password는 문서에 실제 값으로 기록하지 않는다. |

## 2. VPC 설계

| 항목 | 값 | 설명 |
| --- | --- | --- |
| VPC 이름 | `synapse-dev` | `project-environment` 규칙 |
| CIDR | `10.42.0.0/16` | dev 전용 주소 대역 |
| 리전 | `ap-northeast-2` | 서울 리전 |
| AZ | `ap-northeast-2a`, `ap-northeast-2c`, `ap-northeast-2d` | 3개 AZ 분산 |
| DNS hostnames | enabled | EKS, RDS, MSK 내부 DNS 사용 |
| DNS support | enabled | VPC 내부 name resolution |
| Internet Gateway | 1개 | public subnet outbound/inbound 경로 |
| NAT Gateway | 1개 | private subnet outbound 경로. 비용 영향이 커서 apply 전 재확인 필요 |

## 3. Subnet 설계

| Subnet | AZ | CIDR 산정 | 용도 | Public IP 자동 할당 | 주요 태그 |
| --- | --- | --- | --- | --- | --- |
| `synapse-dev-public-ap-northeast-2a` | `ap-northeast-2a` | `10.42.0.0/24` | NAT Gateway, public load balancer 후보 | true | `kubernetes.io/role/elb=1` |
| `synapse-dev-public-ap-northeast-2c` | `ap-northeast-2c` | `10.42.1.0/24` | public load balancer 후보 | true | `kubernetes.io/role/elb=1` |
| `synapse-dev-public-ap-northeast-2d` | `ap-northeast-2d` | `10.42.2.0/24` | public load balancer 후보 | true | `kubernetes.io/role/elb=1` |
| `synapse-dev-private-ap-northeast-2a` | `ap-northeast-2a` | `10.42.10.0/24` | EKS node, RDS, MSK, Redis, OpenSearch | false | `kubernetes.io/role/internal-elb=1` |
| `synapse-dev-private-ap-northeast-2c` | `ap-northeast-2c` | `10.42.11.0/24` | EKS node, RDS, MSK, Redis | false | `kubernetes.io/role/internal-elb=1` |
| `synapse-dev-private-ap-northeast-2d` | `ap-northeast-2d` | `10.42.12.0/24` | EKS node, RDS, MSK, Redis | false | `kubernetes.io/role/internal-elb=1` |

> CIDR은 Terraform `cidrsubnet(var.vpc_cidr, 8, index)`와 `cidrsubnet(var.vpc_cidr, 8, index + 10)` 기준이다.

## 4. Route Table 설계

| Route Table | 연결 Subnet | Destination | Target | 목적 |
| --- | --- | --- | --- | --- |
| `synapse-dev-public` | public subnet 3개 | `0.0.0.0/0` | Internet Gateway | NAT Gateway 및 public LB 인터넷 경로 |
| `synapse-dev-private` | private subnet 3개 | `0.0.0.0/0` | NAT Gateway | EKS node 이미지 pull, 패키지 다운로드 등 outbound |

## 5. Security Group 설계

### 5.1 데이터 계층 Security Group

| SG 이름 | 방향 | Protocol | Port | Source/Destination | 용도 |
| --- | --- | --- | --- | --- | --- |
| `synapse-dev-data` | inbound | TCP | 5432 | EKS cluster security group | RDS PostgreSQL |
| `synapse-dev-data` | inbound | TCP | 6379 | EKS cluster security group | Redis TLS |
| `synapse-dev-data` | inbound | TCP | 9094 | EKS cluster security group | MSK TLS broker |
| `synapse-dev-data` | inbound | TCP | 443 | EKS cluster security group | OpenSearch HTTPS |
| `synapse-dev-data` | outbound | all | all | `0.0.0.0/0` | 관리형 서비스 outbound 기본값 |

### 5.2 EKS Cluster Security Group

| SG | 생성 주체 | 용도 | 비고 |
| --- | --- | --- | --- |
| EKS cluster security group | AWS EKS | control plane과 node 통신, 데이터 계층 접근 source | 실제 SG ID는 Terraform apply 후 확인 |

### 5.3 관리자 접근

| 접근 대상 | 기본 정책 | 허용 조건 |
| --- | --- | --- |
| EKS API endpoint | private endpoint | `admin_cidr_blocks`가 지정된 경우에만 public endpoint를 제한적으로 활성화 |
| RDS / Redis / MSK / OpenSearch | public 접근 금지 | EKS debug pod, SSM, VPN, bastion 등 VPC 내부 경로만 사용 |
| ArgoCD dashboard | ClusterIP | port-forward, VPN, 내부 ingress 중 승인된 방식 사용 |

## 6. 리소스 배치표

| 리소스 | Subnet | Security Group | 공개 여부 | 접속 확인 |
| --- | --- | --- | --- | --- |
| EKS node group | private subnet 3개 | EKS cluster/node SG | private | `kubectl get nodes` |
| RDS PostgreSQL 16 | private DB subnet group | `synapse-dev-data` | private | `psql ... sslmode=require` |
| MSK Kafka 3.x | private subnet 3개 | `synapse-dev-data` | private | `kafka-broker-api-versions.sh` |
| ElastiCache Redis 7 | private subnet group | `synapse-dev-data` | private | `redis-cli --tls ping` |
| OpenSearch 8 호환 | private subnet 1개 | `synapse-dev-data` | private | `GET /_cluster/health` |
| Schema Registry | EKS 내부 `synapse-infra` namespace | ClusterIP | private | `GET /subjects` |
| ArgoCD | EKS 내부 `argocd` namespace | ClusterIP | private | dashboard 로그인, ApplicationSet 렌더링 |

## 7. Apply 전 확인 사항

- [ ] 월 비용이 dev 예산에 맞는지 확인한다. 특히 NAT Gateway와 MSK 3 broker 비용을 확인한다.
- [ ] `admin_cidr_blocks`를 비워 private endpoint로 운영할지, 임시 관리자 CIDR을 둘지 결정한다.
- [ ] AWS 자격 증명과 Terraform state 저장 위치를 결정한다.
- [ ] RDS password와 Redis AUTH token은 환경 변수 또는 승인된 secret manager로 주입한다.
- [ ] apply 후 실제 subnet ID, SG ID, endpoint는 비밀이 아닌 범위에서 접근 문서에 갱신한다.
