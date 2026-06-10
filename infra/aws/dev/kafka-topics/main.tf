# Kafka 토픽 선언 (단일 출처: shared EVENT_CONTRACT_STANDARD §2 / create-kafka-topics.sh TOPICS)
# 기존 bastion 수동 스크립트(create-kafka-topics.sh)를 terraform 선언으로 대체.
# partitions=3 (aws_msk_configuration num.partitions=3 정합).

# 토픽 단일 출처: infra/kafka/topics.txt (terraform + bring-up.sh 공유).
# 기존 인라인 배열 → 파일에서 로드(빈줄·'#' 주석 제거).
locals {
  topics = [
    for line in split("\n", file("${path.module}/../../../kafka/topics.txt")) :
    trimspace(line)
    if trimspace(line) != "" && !startswith(trimspace(line), "#")
  ]
}

resource "kafka_topic" "synapse" {
  for_each           = toset(local.topics)
  name               = each.value
  partitions         = 3
  replication_factor = var.replication_factor

  config = {
    "min.insync.replicas" = var.min_insync_replicas
    "retention.ms"        = "604800000" # 168h (aws_msk_configuration log.retention.hours=168 정합)
  }
}
