# local-k8s — minikube로 Synapse MSA 띄우기

EKS용 `apps/`를 로컬용으로 적응한 자립형 kustomize. ArgoCD 동기화 대상이 아니다(ApplicationSet은 dev/staging/prod만 생성).

- 인프라(postgres/redis/zookeeper/kafka/opensearch)를 클러스터에 함께 배포(영속 없음, 단일 replica).
- 앱 5개는 `../apps/<svc>/base`를 재사용 + 로컬 overlay(ExternalSecret 삭제 · 인프라 호스트 인클러스터 DNS · 이미지 `synapse-<svc>:local`).
- 시크릿은 로컬 더미값(`secrets.yaml`) — 실 시크릿 아님.

## 빠른 시작

```bash
bash scripts/minikube-up.sh
```

## 정적 렌더 확인 (클러스터 불필요)

```bash
kubectl kustomize local-k8s
```

자세한 절차 / 접속 / 트러블슈팅은 `docs/local-msa-setup.html` §9 참조.
