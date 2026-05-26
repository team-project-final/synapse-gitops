# 로컬 k8s(minikube) 실행 경로 설계 스펙 (B)

> **작성일**: 2026-05-26
> **범위**: Synapse MSA 5개 서비스를 minikube 로컬 클러스터에 파드로 기동하는 kustomize 매니페스트 + 기동 스크립트 + HTML 문서
> **산출물**: `synapse-gitops/local-k8s/` (신규), `synapse-gitops/scripts/minikube-up.sh` (신규), `synapse-gitops/docs/local-msa-setup.html` (§9 부록 추가)

---

## 1. 목적

`apps/` 매니페스트는 EKS 전용(ghcr/ECR 이미지, `ExternalSecret`→AWS Secrets Manager, RDS/ElastiCache/MSK 호스트)이라 로컬에서 그대로 안 뜬다. 이를 로컬용으로 적응한 **동작하는 kustomize 구성**을 신설해, 팀원이 minikube에서 MSA 5개 서비스를 파드로 직접 띄워볼 수 있게 한다. 이전 결정대로 사용법 문서(A)와 분리된 별도 작업(B)이다.

## 2. 비목표

- ArgoCD/GitOps 연동(로컬은 `kubectl apply -k` 수동)
- ALB Ingress, 실 AWS 시크릿, 영속 볼륨(PVC)/HA/오토스케일
- Gateway 배포(`apps/`에 매니페스트 없음 — 서비스 직접 접근)
- kind 등 minikube 외 도구 1급 지원(문서에 참고만)

## 3. 산출물 구조

ArgoCD ApplicationSet은 `{service}×{env: dev/staging/prod}` 명시적 list라 `overlays/*`를 글롭하지 않음 → 신규 `local-k8s/`는 ArgoCD가 자동 동기화하지 않음(안전).

```
local-k8s/
├── infra/
│   ├── postgres.yaml          # Deployment+Service (postgres:16-alpine, user/db/pw=synapse/synapse/synapse)
│   ├── redis.yaml             # Deployment+Service (redis:7-alpine, requirepass)
│   ├── zookeeper.yaml         # Deployment+Service (confluentinc/cp-zookeeper:7.7.0)
│   ├── kafka.yaml             # Deployment+Service (cp-kafka:7.7.0, advertised=kafka:9092)
│   ├── opensearch.yaml        # Deployment+Service (opensearchproject/opensearch:2.11.0, single-node)
│   └── kafka-topics-job.yaml  # Job: 토픽 5개 생성 (--if-not-exists)
├── apps/
│   └── <svc>/kustomization.yaml   # 5개: ../../apps/<svc>/base 참조 + 로컬 패치
├── secrets/
│   └── <svc>-secret.yaml      # 평문 Secret (로컬 더미값)
├── kustomization.yaml          # namespace: synapse-local, infra+apps+secrets 집계
└── README.md
scripts/minikube-up.sh          # 기동 자동화
```

- 인프라는 영속 없음(`emptyDir`/볼륨 생략), 단일 replica로 최소화.
- 평문 Secret은 **로컬 더미값**(DB_PASSWORD, JWT_SECRET, AES_SECRET_KEY, JWT 키, STRIPE/OAuth mock 등)이라 커밋 안전.

## 4. 앱 로컬 패치 (서비스 5개 공통 패턴)

각 `local-k8s/apps/<svc>/kustomization.yaml`:
- `resources: [../../../apps/<svc>/base]`, `namespace: synapse-local`
- ExternalSecret 제거: `patches`에 `$patch: delete` (target kind=ExternalSecret)
- ConfigMap 패치 — 인프라 호스트를 인클러스터 DNS로:
  - `DATABASE_HOST=postgres`, `DATABASE_PORT=5432`, `DATABASE_NAME=synapse`,
    `DB_URL=jdbc:postgresql://postgres:5432/synapse`, `DB_USERNAME=synapse`
  - `REDIS_HOST=redis`, `REDIS_PORT=6379`
  - `KAFKA_BROKERS=kafka:9092`
  - learning-ai: `OPENSEARCH_URL=http://opensearch:9200`, `LEARNING_AI_DATABASE_URL` 로컬값
  - knowledge-svc 등 검색 사용 서비스: 검색 호스트 인클러스터 DNS
- `images:` → 로컬 빌드 태그(`synapse-<svc>:local`, `imagePullPolicy: IfNotPresent`)
- 로컬 평문 Secret을 `secretGenerator` 또는 `secrets/<svc>-secret.yaml`로 제공(deployment의 `secretRef`는 `optional:true`).

> **계획 단계 검증**: 각 서비스 `base/configmap.yaml`·`overlays/dev/kustomization.yaml`의 정확한 키 집합과 `base/externalsecret.yaml`의 secretKey 목록을 1:1 확인해 ConfigMap/Secret 키를 채운다(서비스마다 다름 — 특히 learning-ai는 Python·OpenSearch).

## 5. 인프라 매니페스트 (인클러스터)

단일 replica Deployment + ClusterIP Service. 서비스 DNS로 앱이 연결:
- `postgres:5432`(POSTGRES_USER/DB/PASSWORD=synapse/synapse/synapse)
- `redis:6379`(requirepass=로컬값)
- `zookeeper:2181` → `kafka:9092`(KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://kafka:9092 → advertised-listener 함정 없음)
- `opensearch:9200`(discovery.type=single-node, security 비활성)
- `kafka-topics-job`: `platform.auth.user-registered-v1`, `knowledge.note.note-created-v1`, `knowledge.note.note-updated-v1`, `learning.card.review-completed-v1`, `learning.ai.cards-generated-v1`

## 6. 기동 스크립트 `scripts/minikube-up.sh`

순서: ① `minikube start`(docker 드라이버) → ② 5개 서비스 이미지 빌드(`docker build`) + `minikube image load synapse-<svc>:local` → ③ `kubectl apply -k local-k8s` → ④ `kubectl -n synapse-local rollout status` → ⑤ port-forward 안내 출력. 멱등(재실행 안전), 실패 시 메시지.

## 7. 접근 / 사용

- `kubectl port-forward -n synapse-local svc/<svc> <local>:80` (서비스 포트 80→컨테이너 8080). 예: platform `8080:80`, learning-ai `8000:80`.
- 확인: 각 `/actuator/health`, learning-ai `/docs`. (Gateway 없음 → 서비스 직접)
- `kubectl get pods -n synapse-local`, `kubectl logs`, (선택) `minikube dashboard`.

## 8. 문서화 — §9 부록

`local-msa-setup.html`에 새 **§9 "(고급) 로컬 k8s(minikube)로 띄우기"** 부록 섹션 추가(맨 끝, 기존 선형 흐름 유지). §0 두 경로 비교 부근 또는 §8에 "k8s로 띄우려면 §9" 포인터 1줄. 내용: 선행 도구(minikube/kubectl), `scripts/minikube-up.sh` 사용, 수동 절차, port-forward 접근, 트러블슈팅(이미지 load 안 됨/`ImagePullBackOff`, OOM, kafka 준비 대기), compose 경로와의 차이(인프라 인클러스터). 기존 패턴(번호 단계·복사 블록·`<details>` 심화) 재사용.

## 9. 검증

- **정적(이번 세션 가능)**: `kubectl kustomize local-k8s` 렌더 성공(에러 0), 가능 시 `kubeconform`으로 스키마 검증. 5개 서비스 Deployment/Service/ConfigMap/Secret + 인프라가 `synapse-local` 네임스페이스로 렌더되는지 확인.
- **런타임(후속, 사용자 또는 데몬 가용 시 시도)**: `scripts/minikube-up.sh` → 모든 파드 Ready → port-forward로 헬스 OK. 본 스펙은 정적 검증을 완료 기준으로 하고, 런타임은 best-effort.

## 10. 범위 밖 (재확인)

- ArgoCD 연동, Ingress/TLS, 실 시크릿/SecretStore, PVC/HA
- Gateway k8s 배포, kind 1급 지원
- compose 경로(①②)·사용법(A) 변경 — 본 작업은 추가만
