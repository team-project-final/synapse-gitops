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
