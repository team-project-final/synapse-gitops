# MSK 토픽 terraform 관리 (TLS-only)

MSK 9개 토픽을 선언 관리한다. 기존 `create-kafka-topics.sh`(bastion 수동) 대체.

## 전제
- 인프라(`infra/aws/dev`)가 apply되어 MSK 브로커가 ACTIVE.
- MSK는 private subnet → **bastion에서 실행**(또는 bastion 경유 도달). TLS-only라 IAM/Kafka CLI 불필요, terraform Go 바이너리만 필요(JRE 불필요).

## 절차 (라이브 window)

### 1. 브로커 주소 취득 (로컬, 인프라 디렉터리)
```bash
cd infra/aws/dev
terraform output -raw msk_bootstrap_brokers_tls   # b-1...:9094,b-2...:9094
```

### 2. bastion에 terraform 설치 (SSM, 1회)
```bash
aws ssm send-command --instance-ids <bastion_instance_id> \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["cd /tmp && curl -fsSL https://releases.hashicorp.com/terraform/1.9.8/terraform_1.9.8_linux_amd64.zip -o tf.zip && unzip -o tf.zip && sudo mv terraform /usr/local/bin/ && terraform version"]'
```

### 3. bastion에 토픽 구성 복사 + apply
```bash
# 구성을 bastion으로 (git clone 또는 SSM으로 파일 전송)
# bastion 셸에서:
cd /tmp/kafka-topics
terraform init
terraform apply -var='bootstrap_servers=["b-1...:9094","b-2...:9094"]'
```

### 4. 검증 (9개 토픽)
```bash
terraform state list | grep kafka_topic | wc -l   # 9
```

## 폴백
provider 연결 실패 시 진단: SG(9094 inbound) 확인 → `infra/aws/dev` SG 수동 추가(D-026). 그래도 실패 시 기존 `create-kafka-topics.sh`는 bastion에 JRE+kafka CLI가 없어 사용 불가 → terraform provider 경로가 유일 실용 경로(spec §3.3).
