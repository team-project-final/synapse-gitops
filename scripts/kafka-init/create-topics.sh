#!/usr/bin/env bash
# scripts/kafka-init/create-topics.sh
# Auto-create Kafka topics for local development.
# Called by docker-compose kafka-init service.
set -euo pipefail

BROKER="${KAFKA_BROKER:-kafka:9092}"
TOPICS=(
  "platform.auth.user-registered-v1"
  "knowledge.note.note-created-v1"
  "knowledge.note.note-updated-v1"
  "learning.card.review-completed-v1"
  "learning.ai.cards-generated-v1"
)

echo "Waiting for Kafka to be ready..."
cub kafka-ready -b "$BROKER" 1 60

for topic in "${TOPICS[@]}"; do
  echo "Creating topic: $topic"
  kafka-topics --bootstrap-server "$BROKER" \
    --create --if-not-exists \
    --topic "$topic" \
    --partitions 3 \
    --replication-factor 1 \
    --config retention.ms=604800000 \
    --config cleanup.policy=delete
done

echo "All topics created:"
kafka-topics --bootstrap-server "$BROKER" --list
