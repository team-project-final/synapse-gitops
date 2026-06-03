# local-k8s — minikube로 Synapse MSA 띄우기

EKS용 `apps/`를 로컬용으로 적응한 자립형 kustomize. ArgoCD 동기화 대상이 아니다(ApplicationSet은 dev/staging/prod만 생성).

- 인프라(postgres/redis/zookeeper/kafka/**schema-registry**/opensearch)를 클러스터에 함께 배포(영속 없음, 단일 replica, readiness/liveness 프로브 + 리소스 limit 부여).
- 앱 6개(gateway + platform/engagement/knowledge/learning-card/learning-ai)는 `../apps/<svc>/base`를 재사용 + 로컬 overlay(ExternalSecret 삭제 · 인프라 호스트 인클러스터 DNS · 이미지 `synapse-<svc>:local`).
- 시크릿은 로컬 더미값(`secrets.yaml`) — 실 시크릿 아님. **단, learning-ai의 OpenAI 키만 실제 값을 별도 주입**(아래 참조).

## 빠른 시작

```bash
bash scripts/minikube-up.sh
```

`minikube-up.sh`가 ① minikube 기동(8GB/4CPU) ② 형제 레포 이미지 빌드+적재(6개) ③ `kubectl apply -k local-k8s` ④ learning-ai OpenAI 키 자동주입(있으면) ⑤ 롤아웃 대기까지 수행한다. 형제 레포가 `../synapse-*`에 클론돼 있어야 한다.

`kubectl delete ns synapse-local && bash scripts/minikube-up.sh` 단독으로 인프라+앱 전부 `1/1`로 재현된다(learning-ai는 키 주입 시).

> **minikube가 없으면**: 관리자 권한 없이도 바이너리로 설치 가능.
> `iwr -useb https://github.com/kubernetes/minikube/releases/latest/download/minikube-windows-amd64.exe -OutFile $env:USERPROFILE\tools\minikube\minikube.exe` 후 해당 폴더를 PATH에 추가. (choco 설치는 관리자 권한 필요)

## learning-ai OpenAI 키 주입 (선택, minikube-up.sh가 자동 처리)

`minikube-up.sh`는 다음이 있으면 learning-ai 시크릿에 키를 **자동 주입**한다(없으면 learning-ai만 CrashLoop, 나머지는 정상):

- 환경변수 `LEARNING_AI_OPENAI_API_KEY`, 또는
- 파일 `../.learning-ai-key` (레포 밖, git 미커밋)

수동 주입(merge-patch — 다른 시크릿 키는 보존):

```bash
kubectl -n synapse-local patch secret learning-ai-secret --type=merge \
  -p '{"stringData":{"LEARNING_AI_OPENAI_API_KEY":"<real-key>"}}'
kubectl -n synapse-local rollout restart deploy/learning-ai
```

> 키 이름에 `LEARNING_AI_` prefix 필수(앱이 pydantic `env_prefix="LEARNING_AI_"` 사용). 키 없이도 나머지 워크로드는 정상 동작하며 learning-ai만 CrashLoop이다.

## 정적 렌더 확인 (클러스터 불필요)

```bash
kubectl kustomize local-k8s    # 40 리소스 렌더(Deployment 12 = 인프라 6 + 앱 6)
```

## 설계 노트 (왜 이렇게 되어 있나 — 매니페스트/스크립트에 반영됨)

| 항목 | 이유 | 위치 |
|---|---|---|
| **메모리 8GB 권장** | 인프라 + JVM 서비스 동시 기동 → 4GB면 liveness가 파드를 죽임 | `scripts/minikube-up.sh` (`--memory=8192`) |
| **서비스별 DB 격리** | 5개 svc가 단일 `synapse` DB 공유 시 `flyway_schema_history` 충돌 → svc별 DB 자동 생성 | `infra/postgres-initdb.yaml` + 각 overlay `SPRING_DATASOURCE_URL` |
| **postgres = pgvector 이미지** | knowledge/learning-ai가 `CREATE EXTENSION vector` 필요 | `infra/postgres.yaml`(`pgvector/pgvector:pg16`) |
| **`kafka-brokers` ConfigMap** | base deployment가 `configMapKeyRef name=kafka-brokers` 참조(dev는 terraform 생성) | `infra/kafka-brokers-config.yaml` |
| **`enableServiceLinks: false`** | k8s가 주입하는 `<SVC>_PORT=tcp://...`가 앱/cp 이미지 설정과 충돌(NumberFormatException 등) | 각 app overlay + `infra/kafka.yaml`·`infra/schema-registry.yaml` |
| **engagement·learning-card 프로브 = tcpSocket** | actuator health가 Spring Security로 보호(401)되어 httpGet 프로브가 파드를 죽임 | 두 app overlay |
| **learning-ai 설정 키에 `LEARNING_AI_` prefix** | pydantic `env_prefix` 때문에 prefix 없는 `KAFKA_BROKERS` 등을 무시하고 localhost로 폴백 | `apps/learning-ai/kustomization.yaml` |
| **schema-registry 배포 + 배선** | 전 Java svc·learning-ai가 Avro 직렬화에 Schema Registry 필요(없으면 localhost:8086 폴백 실패) | `infra/schema-registry.yaml` + 각 svc `SCHEMA_REGISTRY_URL=http://schema-registry:8081` |
| **`KAFKA_BOOTSTRAP_SERVERS` 주입** | 앱은 `spring.kafka.bootstrap-servers=${KAFKA_BOOTSTRAP_SERVERS:localhost:9092}` 를 읽음. `KAFKA_BROKERS`만 주면 localhost 폴백 → Kafka 단절 | platform/knowledge/learning-card overlay |
| **platform-svc DDL = validate** | Flyway(V1~V32)가 스키마 소유. 앱 기본 프로파일·prod와 일치 | `apps/platform-svc/kustomization.yaml` |
| **인프라 프로브 + 리소스** | 앱 기동 레이스 완화 + 8GB 노드 스케줄 안정(opensearch 1Gi, zookeeper 384Mi 등) | `infra/*.yaml` |
| **무중단 배포(base)** | `strategy{maxUnavailable:0,maxSurge:1}`+`preStop`+`minReadySeconds:10`+`grace:40` → 롤아웃 무손실(로컬 replica=1에선 surge로 신규 Ready 후 구 종료) | `apps/*/base/deployment.yaml`(전 환경 공유) |
| **learning-ai 키 자동주입** | 매 재설치마다 수동 주입 마찰 제거 | `scripts/minikube-up.sh` 3.5단계 |

> 인프라는 PVC가 없어(영속 X) postgres 재시작 시 `postgres-initdb.yaml`이 DB를 재생성한다.

## 무중단 배포 검증 (로컬)

```bash
kubectl -n synapse-local port-forward svc/gateway 8080:80 &   # 별도 터미널
# 부하 루프(레이트리밋 회피 위해 간격 ~1.3s) 중 롤아웃:
kubectl -n synapse-local rollout restart deploy/platform-svc
# gateway 경유 연속 curl이 5xx/연결끊김 0건이면 무중단 성공
```

> prod overlay(replicas=3)는 추가로 `PodDisruptionBudget(minAvailable:1)` + pod anti-affinity 적용(local/dev/staging은 replicas=1이라 PDB 미적용 — node drain 데드락 회피).

## 접근 (별도 터미널 port-forward)

```bash
kubectl -n synapse-local port-forward svc/gateway     8080:80   # 메인 진입점
kubectl -n synapse-local port-forward svc/learning-ai 8000:80
# 상태: kubectl -n synapse-local get pods
```

Gateway 경유 예: `curl http://localhost:8080/api/platform/actuator/health` · learning-ai 문서: `http://localhost:8000/docs`

## 대시보드 / 리소스 사용량

```bash
minikube dashboard --url                 # 웹 UI URL 출력 (프록시 유지)
minikube addons enable metrics-server    # CPU/메모리 그래프 + kubectl top 활성화
kubectl top nodes
kubectl -n synapse-local top pods
```

## 알려진 미해결(후속 finding)

- **engagement-svc Kafka**: 앱 `application.yml`에 `spring.kafka.bootstrap-servers` 플레이스홀더가 없고 `kafka.enabled=false` 기본 → 로컬 Kafka 흐름을 켜려면 **앱 레포 수정** 필요(env만으론 안 됨).
- **EKS(dev/staging/prod) Kafka bootstrap**: base가 `KAFKA_BROKERS`만 제공 → MSK 연결 방식 확인 후 별도 처리.
- **앱 graceful shutdown**(`server.shutdown: graceful`)이 서비스 레포에 부재 → 완전 무중단엔 앱 설정 필요(현재 `preStop`이 엔드포인트 드레인으로 부분 보완).

자세한 단계별 절차 / OS 탭 / 트러블슈팅은 **[로컬 MSA 세팅 가이드](../docs/local-msa-setup.html)** §3(k8s) 참조.
