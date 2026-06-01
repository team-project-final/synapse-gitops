# local-k8s — minikube로 Synapse MSA 띄우기

EKS용 `apps/`를 로컬용으로 적응한 자립형 kustomize. ArgoCD 동기화 대상이 아니다(ApplicationSet은 dev/staging/prod만 생성).

- 인프라(postgres/redis/zookeeper/kafka/opensearch)를 클러스터에 함께 배포(영속 없음, 단일 replica).
- 앱 5개는 `../apps/<svc>/base`를 재사용 + 로컬 overlay(ExternalSecret 삭제 · 인프라 호스트 인클러스터 DNS · 이미지 `synapse-<svc>:local`).
- 시크릿은 로컬 더미값(`secrets.yaml`) — 실 시크릿 아님.

## 빠른 시작

```bash
bash scripts/minikube-up.sh
```

`minikube-up.sh`가 ① minikube 기동(8GB/4CPU) ② 형제 레포 이미지 빌드+적재 ③ `kubectl apply -k local-k8s` ④ 롤아웃 대기 ⑤ 접근 안내까지 수행한다. 형제 레포가 `../synapse-*`에 클론돼 있어야 한다.

## 정적 렌더 확인 (클러스터 불필요)

```bash
kubectl kustomize local-k8s    # 36 리소스 렌더
```

## 알려진 gotcha (모두 매니페스트/스크립트에 반영됨)

| 항목 | 이유 | 위치 |
|---|---|---|
| **메모리 8GB 권장** | 인프라(opensearch/kafka 등) + JVM 서비스 4개 동시 기동 → 4GB면 liveness가 파드를 죽임 | `scripts/minikube-up.sh` (`--memory=8192`) |
| **kafka `enableServiceLinks: false`** | k8s가 주입하는 `KAFKA_*` 서비스 env가 cp-kafka 설정과 충돌 | `local-k8s/infra/kafka.yaml` |
| **platform-svc Redis = `spring.data.redis.*`** | 앱이 relaxed-binding 키만 읽음 → `SPRING_DATA_REDIS_HOST/PORT`로 줘야 적용(`REDIS_HOST`는 무시되어 localhost 폴백) | `local-k8s/apps/platform-svc/kustomization.yaml` |
| **learning-ai 이미지 빌드 실패** | 업스트림 Dockerfile이 `app/` 복사 전에 `pip install .` 실행 | `minikube-up.sh`가 실패 허용 — 해당 파드만 ImagePullBackOff, 나머지 정상 |
| **learning-card Dockerfile 부재** | Spring Boot `bootBuildImage`로 대체 빌드 | `minikube-up.sh` (gradlew bootBuildImage) |

> learning-ai/learning-card 이미지가 없으면 두 파드만 ImagePullBackOff이고 나머지 인프라+서비스는 정상 동작한다. 앱 레포 이미지 수정 후 재빌드하면 그린.

## 접근 (별도 터미널 port-forward)

```bash
kubectl -n synapse-local port-forward svc/gateway     8080:80   # 메인 진입점
kubectl -n synapse-local port-forward svc/learning-ai 8000:80
# 상태: kubectl -n synapse-local get pods
```

Gateway 경유 예: `curl http://localhost:8080/api/platform/actuator/health` · learning-ai 문서: `http://localhost:8000/docs`

자세한 단계별 절차 / OS 탭 / 트러블슈팅은 **[로컬 MSA 세팅 가이드](../docs/local-msa-setup.html)** §K8s 참조.
