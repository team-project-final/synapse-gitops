# kafka-brokers ConfigMap (bastion 실행)

EKS 엔드포인트가 private-only → **bastion에서 실행**(로컬 terraform 도달 불가).
#87(access entry) 적용 + bastion `update-kubeconfig` 완료가 전제.

## 비고

- provider `config_path = ~/.kube/config` → **bastion 사용자(SSM 기본 ec2-user)로 실행**. user_data의 `update-kubeconfig`로 채워짐.
- 네임스페이스는 terraform 소유(순서 보장) + `prevent_destroy` → 이 모듈 단독 `terraform destroy`는 ns 보호로 차단됨(정리는 클러스터(main) destroy로).

## 절차

1. 로컬에서 브로커 주소 확보:

   ```bash
   cd infra/aws/dev && terraform output -raw msk_bootstrap_brokers_tls
   ```

2. bastion(SSM)에 terraform 설치 + 이 디렉터리 전송(base64) — 2026-06-02 kafka-topics 패턴.

3. bastion에서 apply:

   ```bash
   terraform init && terraform apply -var="kafka_brokers=<brokers>"
   ```

4. 검증:

   ```bash
   kubectl get configmap kafka-brokers -n synapse-dev -o jsonpath='{.data.KAFKA_BROKERS}'
   ```

## 폴백
private endpoint·bastion 경로가 막히면 spec §6 폴백(단일 공유 base ConfigMap, git 1곳 수동).
