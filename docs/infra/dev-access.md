# Synapse dev 인프라 접근 정보

이 문서는 dev AWS 환경 접근에 필요한 비밀이 아닌 정보만 기록한다.

네트워크 세부 설계는 [dev-network-design.md](dev-network-design.md)를 기준으로 한다.

## 클러스터

| 항목 | 값 |
| --- | --- |
| 클러스터 이름 | `synapse-dev` |
| 리전 | `ap-northeast-2` |
| Kubernetes namespace 패턴 | `synapse-dev`, `synapse-staging`, `synapse-prod` |
| ArgoCD namespace | `argocd` |

## kubectl 설정

```bash
aws eks update-kubeconfig --name synapse-dev --region ap-northeast-2
kubectl get nodes
kubectl get pods -A
kubectl get applications -n argocd
```

## 내부 endpoint

값은 Terraform apply 후 output을 기준으로 채운다. 실제 비밀번호와 토큰은 이 파일에 기록하지 않는다.

| 서비스 | 플레이스홀더 |
| --- | --- |
| RDS PostgreSQL | `<RDS_ENDPOINT>:5432` |
| MSK Kafka TLS bootstrap | `<MSK_BOOTSTRAP_BROKERS_TLS>` |
| Redis TLS | `<REDIS_ENDPOINT>:6379` |
| OpenSearch HTTPS | `https://<OPENSEARCH_ENDPOINT>` |
| Schema Registry | `<SCHEMA_REGISTRY_INTERNAL_URL>` |

## Smoke Test 명령

데이터 서비스 테스트는 VPC 내부에서 실행한다.

```bash
psql "host=<RDS_ENDPOINT> port=5432 dbname=<DB> user=<USER> sslmode=require"
redis-cli -h <REDIS_ENDPOINT> -p 6379 --tls -a <TOKEN> ping
curl -k https://<OPENSEARCH_ENDPOINT>/_cluster/health
kafka-broker-api-versions.sh --bootstrap-server <MSK_BOOTSTRAP_BROKERS_TLS>
curl <SCHEMA_REGISTRY_INTERNAL_URL>/subjects
```

## IAM 접근 권한

개발자에게는 작업에 필요한 그룹만 부여한다.

| 그룹 | 목적 |
| --- | --- |
| `synapse-dev-readonly` | 클러스터와 로그 읽기 전용 접근 |
| `synapse-dev-deployer` | Application sync와 rollout 지원 |
| `synapse-dev-admin` | 팀장 긴급 관리자 접근 |

## 문제 해결

- `kubectl get nodes`가 실패하면 AWS identity, kubeconfig context, EKS endpoint 접근 CIDR을 확인한다.
- 데이터 서비스에 접근할 수 없으면 호출자가 VPC 내부에 있는지, 데이터 security group이 EKS cluster security group 접근을 허용하는지 확인한다.
- ArgoCD가 Application을 렌더링하지 못하면 ApplicationSet CRD 설치 여부와 `synapse-gitops` repo URL 접근 가능 여부를 확인한다.
