# Resource request/limit 적정성 리뷰 (W5 Step 12)

> 작성: 2026-06-08 (W5 Day1) · 범위: `apps/*/base/deployment.yaml` 정적 리뷰
> 성격: **정적 1회 리뷰**(비용 0). 실제 P95 기반 튜닝은 메트릭 필요 → 윈도우 2(Grafana/Prometheus 가동 후) 위임.

## 현황 스냅샷

| 서비스 | req cpu | req mem | lim cpu | lim mem | lim/req(mem) | 런타임 |
|---|---|---|---|---|---|---|
| platform-svc | 100m | 256Mi | 500m | 512Mi | 2.0x | Java(Spring) |
| engagement-svc | 100m | 256Mi | 500m | 512Mi | 2.0x | Java(Spring) |
| knowledge-svc | 100m | 256Mi | 500m | 512Mi | 2.0x | Java(Spring) |
| learning-card | 100m | 256Mi | 500m | 512Mi | 2.0x | Java(Spring) |
| gateway | 100m | 256Mi | 500m | 512Mi | 2.0x | Java(Spring Cloud GW) |
| learning-ai | 100m | 256Mi | 500m | 512Mi | 2.0x | Python(FastAPI/asyncpg) |
| schema-registry | 100m | 256Mi | 500m | 768Mi | 3.0x | JVM(Confluent) |
| frontend | 25m | 32Mi | 200m | 128Mi | 4.0x | nginx(Flutter web) |

> base 기준. overlay는 replicas만 차등(dev=1/staging=2), 리소스는 base 그대로 상속.

## 발견 (정적)

1. **Java 서비스 5종 limit 균일·tight (512Mi)** — Spring Boot + Kafka + JPA + Redis 풀스택에 512Mi는 빠듯. JVM 힙 외(metaspace/direct buffer) 포함 시 OOM 리스크. `incidents/oom-killed.md`의 우려·W4 학습과 정합. **가장 우선 확인 대상**(P95).
2. **서비스별 차등 부재** — platform-svc(Stripe+audit+다중 Consumer, 최중량)와 경량 서비스가 동일 256Mi/512Mi. 부하 프로파일이 다른데 동일 사이징.
3. **learning-ai 미차등** — Python+pgvector/임베딩 워크로드인데 Java와 동일. 실제 풋프린트는 별개(더 크거나 작을 수 있음) → 별도 측정 필요.
4. **환경별 차등 없음** — dev/staging/prod 리소스 동일(prod는 HPA로 스케일아웃 보완). dev는 더 낮춰 비용 절감 여지(db.t3.small 동시연결 한계 맥락).
5. **양호** — frontend(nginx) 32/128Mi 적절, schema-registry 768Mi 상향 적절.

## 권고 (P95 측정 후 = 윈도우 2)

| 우선 | 대상 | 조치 |
|---|---|---|
| P1 | Java 5종 limit | Grafana P95×1.3 측정 → 512Mi가 부족하면 768Mi~1Gi 상향(특히 platform-svc) |
| P2 | dev 환경 | dev overlay에 리소스 축소 patch(비용 절감) — 동시연결/메모리 압박 완화 |
| P3 | learning-ai | Python 실측 풋프린트로 Java 디폴트와 분리 |
| P3 | request 현실화 | request 100m/256Mi가 실제 idle보다 높으면 하향(빈패킹 개선) |

## 결론

- **정적 리뷰 1회 완료** — 균일 사이징·Java limit tight·서비스/환경 미차등이 핵심 갭.
- 매니페스트 변경은 **하지 않음**(P95 데이터 없이 추정 조정은 OOM/낭비 양방향 리스크). 윈도우 2에서 Grafana 메트릭으로 측정 후 overlay patch.
- 연계: `incidents/oom-killed.md`(조치 절차), `W5_WINDOW_2.md`(메트릭 가동), TASK Step 12.
