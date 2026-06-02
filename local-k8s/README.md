# local-k8s — minikube로 Synapse MSA 띄우기

EKS용 `apps/`를 로컬용으로 적응한 자립형 kustomize. ArgoCD 동기화 대상이 아니다(ApplicationSet은 dev/staging/prod만 생성).

- 인프라(postgres/redis/zookeeper/kafka/opensearch)를 클러스터에 함께 배포(영속 없음, 단일 replica).
- 앱 5개는 `../apps/<svc>/base`를 재사용 + 로컬 overlay(ExternalSecret 삭제 · 인프라 호스트 인클러스터 DNS · 이미지 `synapse-<svc>:local`).
- 시크릿은 로컬 더미값(`secrets.yaml`) — 실 시크릿 아님. **단, learning-ai의 OpenAI 키만 실제 값을 별도 주입해야 동작**(아래 참조).

## 빠른 시작

```bash
bash scripts/minikube-up.sh
```

`minikube-up.sh`가 ① minikube 기동(8GB/4CPU) ② 형제 레포 이미지 빌드+적재(6개) ③ `kubectl apply -k local-k8s` ④ 롤아웃 대기 ⑤ 접근 안내까지 수행한다. 형제 레포가 `../synapse-*`에 클론돼 있어야 한다.

> **minikube가 없으면**: 관리자 권한 없이도 바이너리로 설치 가능.
> `iwr -useb https://github.com/kubernetes/minikube/releases/latest/download/minikube-windows-amd64.exe -OutFile $env:USERPROFILE\tools\minikube\minikube.exe` 후 해당 폴더를 PATH에 추가. (choco 설치는 관리자 권한 필요)

## learning-ai OpenAI 키 주입 (필수, 1회)

learning-ai는 기동 시 OpenAI 자격증명을 요구한다. `secrets.yaml`의 placeholder(`sk-mock`)로는 뜨지 않으므로 **실제 키를 클러스터에 직접 주입**한다(이 키는 git에 커밋하지 않는다).

```bash
kubectl -n synapse-local create secret generic learning-ai-secret \
  --from-literal=LEARNING_AI_OPENAI_API_KEY=<실제키> \
  --from-literal=LEARNING_AI_ANTHROPIC_API_KEY=sk-mock \
  --from-literal=DATABASE_PASSWORD=synapse_local \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n synapse-local rollout restart deploy/learning-ai
```

> 키 이름에 `LEARNING_AI_` prefix 필수(앱이 pydantic `env_prefix="LEARNING_AI_"` 사용). 키 없이도 나머지 10개 워크로드는 정상 동작하며 learning-ai만 CrashLoop이다.

## 정적 렌더 확인 (클러스터 불필요)

```bash
kubectl kustomize local-k8s    # 38 리소스 렌더
```

## 설계 노트 (왜 이렇게 되어 있나 — 매니페스트/스크립트에 반영됨)

| 항목 | 이유 | 위치 |
|---|---|---|
| **메모리 8GB 권장** | 인프라(opensearch/kafka 등) + JVM 서비스 4개 동시 기동 → 4GB면 liveness가 파드를 죽임 | `scripts/minikube-up.sh` (`--memory=8192`) |
| **서비스별 DB 격리** | 5개 svc가 단일 `synapse` DB+public 스키마를 공유하면 `flyway_schema_history`가 충돌. `postgres-initdb.yaml`이 svc별 DB(`synapse_platform/_engagement/_knowledge/_learning/_learning_ai`)를 자동 생성 | `local-k8s/infra/postgres-initdb.yaml` + 각 overlay `SPRING_DATASOURCE_URL` |
| **postgres = pgvector 이미지** | knowledge/learning-ai가 `CREATE EXTENSION vector` 필요 | `local-k8s/infra/postgres.yaml`(`pgvector/pgvector:pg16`) |
| **`kafka-brokers` ConfigMap** | base deployment가 `configMapKeyRef name=kafka-brokers`를 참조(dev는 terraform이 생성) | `local-k8s/infra/kafka-brokers-config.yaml` |
| **`enableServiceLinks: false`** | k8s가 주입하는 `<SVC>_PORT=tcp://...`(예: `REDIS_PORT`)가 앱 설정과 충돌 → NumberFormatException | 각 app overlay + `infra/kafka.yaml` |
| **engagement·learning-card 프로브 = tcpSocket** | actuator health가 Spring Security로 보호(401)되어 httpGet 프로브가 파드를 죽임 | 두 app overlay |
| **learning-ai 설정 키에 `LEARNING_AI_` prefix** | pydantic `env_prefix` 때문에 prefix 없는 `KAFKA_BROKERS` 등을 무시하고 localhost로 폴백 | `local-k8s/apps/learning-ai/kustomization.yaml` |
| **learning-card 이미지 = 일반 docker build** | paketo `bootBuildImage` 산출물은 containerd import가 "wrong diff id"로 실패 | `scripts/minikube-up.sh`(Dockerfile 빌드) |

> 인프라는 PVC가 없어(영속 X) postgres 파드 재시작 시 `postgres-initdb.yaml`이 DB를 다시 생성한다. `kubectl delete ns synapse-local && kubectl apply -k local-k8s`만으로 learning-ai(키 재주입 필요)를 제외한 전부가 `1/1`로 재현된다.

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

자세한 단계별 절차 / OS 탭 / 트러블슈팅은 **[로컬 MSA 세팅 가이드](../docs/local-msa-setup.html)** §3(k8s) 참조.
