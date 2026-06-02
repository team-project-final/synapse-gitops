# Kafka 토픽 선언 (단일 출처: shared EVENT_CONTRACT_STANDARD §2 / create-kafka-topics.sh TOPICS)
# 기존 bastion 수동 스크립트(create-kafka-topics.sh)를 terraform 선언으로 대체.
# partitions=3 (aws_msk_configuration num.partitions=3 정합).

locals {
  topics = [
    "platform.auth.user-registered-v1",
    "knowledge.note.note-created-v1",
    "knowledge.note.note-updated-v1",
    "learning.card.review-completed-v1",
    "learning.card.review-due-v1",
    "engagement.gamification.level-up-v1",
    "engagement.gamification.badge-earned-v1",
    "platform.notification.notification-send-v1",
    "learning.ai.cards-generated-v1", # deprecated(D-001 HTTP 전환) — 호환 위해 토픽만 존속, 제거는 W5 백로그 추적
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
