# gateway·engagement·learning-ai 비-root 컨테이너 — 설계 (2026-06-03)

## 배경

핸드오프 후속 finding B2. #100 securityContext 하드닝 당시 platform/knowledge/learning-card는
이미지에 `USER app`(uid 101)이 있어 `runAsNonRoot:true + runAsUser:101`을 적용했으나,
**gateway·engagement·learning-ai는 Dockerfile에 USER가 없어(root)** base에 "안전 부분집합"
(`allowPrivilegeEscalation:false` + `drop ALL` + seccomp)만 적용된 상태다.

이 finding은 그 3개 이미지에 비-root USER를 추가하고 gitops base에서 `runAsNonRoot`를 활성화해
#100의 securityContext 스토리를 완성한다.

## 목표 / 비목표

**목표**
- gateway·engagement·learning-ai 이미지가 비-root(uid 101)로 구동되도록 Dockerfile 수정.
- gitops base 3개의 securityContext를 기존 비-root 3개와 동일한 풀 블록으로 통일.
- minikube에서 3개 파드가 uid 101로 정상 기동함을 **런타임 검증**.

**비목표**
- EKS 런타임 검증 (클러스터 부재 → git-only, 프로비저닝 시 A에서 확인).
- platform/knowledge/learning-card 변경 (이미 비-root).
- `readOnlyRootFilesystem` 등 추가 하드닝 (repo 비컨벤션, 별도 finding).

## 결정 사항

- **uid 전략**: 3개 모두 uid/gid **101**로 핀 → gitops securityContext 블록을 기존과 동일하게
  재사용(일관성). alpine은 `adduser -u 101`, debian-slim은 `--uid 101`로 명시.
- **범위**: 3개 서비스 + gitops 한 번에. 앱 3 PR + gitops 1 PR = 4 PR.
- **검증**: minikube 런타임(이미지 재빌드 + 재배포). EKS는 kustomize 렌더만.

## 변경 설계

### 표면 1 — 앱 레포 Dockerfile (각 1 PR)

기존 비-root 패턴(`synapse-platform-svc/Dockerfile`: `addgroup --system app &&
adduser --system --ingroup app app` → uid 101, `chown app:app app.jar`, `USER app`)을
베이스별로 적용.

**synapse-gateway** (`eclipse-temurin:21-jre-alpine`) — runtime stage 끝부분:
```dockerfile
RUN addgroup -g 101 -S app && adduser -u 101 -S -G app app
COPY --from=builder /app/build/libs/*.jar app.jar
RUN chown app:app app.jar
USER app
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

**synapse-engagement-svc** (`eclipse-temurin:21-jre-alpine`) — 동일 패턴. 현재 runtime stage:
```dockerfile
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=builder /app/build/libs/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```
→ COPY 다음에 user 생성 + chown + USER 추가:
```dockerfile
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
RUN addgroup -g 101 -S app && adduser -u 101 -S -G app app
COPY --from=builder /app/build/libs/*.jar app.jar
RUN chown app:app app.jar
USER app
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

**synapse-learning-svc/learning-ai** (`python:3.12-slim`, Debian) — runtime stage.
현재 끝부분이 `COPY . .` / ENV / EXPOSE 8090 / CMD uvicorn. user 생성 + chown + USER 추가:
```dockerfile
COPY --from=builder /install /usr/local
COPY . .
RUN addgroup --system --gid 101 app && adduser --system --uid 101 --ingroup app app \
    && chown -R app:app /app
USER app
ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1
EXPOSE 8090
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8090"]
```

### 표면 2 — gitops base securityContext (1 PR, gitops 레포)

`apps/gateway/base/deployment.yaml`, `apps/engagement-svc/base/deployment.yaml`,
`apps/learning-ai/base/deployment.yaml`의 securityContext를 기존 "안전 부분집합" + 주석에서
다음 풀 블록으로 교체(platform/knowledge/learning-card와 동일):
```yaml
          securityContext:
            runAsNonRoot: true
            runAsUser: 101    # 이미지의 app 유저(adduser → uid 101). runAsNonRoot 검증에 숫자 UID 필요
            runAsGroup: 101
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            seccompProfile:
              type: RuntimeDefault
```

### 표면 3 — minikube 런타임 검증

3개 이미지 재빌드(USER 포함) → `minikube image load` → `kubectl apply -k local-k8s` →
`rollout restart` → 3개 파드 1/1 Running 확인 + `kubectl exec -- id`로 uid=101 확인.
`CreateContainerConfigError`/`container has runAsNonRoot and image will run as root`/
권한 오류(Permission denied) 부재 확인. 12+/N 회귀 없음.

## 리스크 / 미검증 항목

- **순서 의존성(EKS)**: gitops `runAsNonRoot`는 USER 포함 이미지가 전제. EKS는 클러스터 부재라
  git-only — 앱 3 PR 머지 + CI가 ECR/ghcr에 USER 포함 이미지를 푸시한 뒤라야 안전. gitops PR에
  merge-order(앱 3 PR 선행) 명시. minikube는 이 작업에서 로컬 재빌드로 자기완결 검증.
- **alpine uid 101 충돌**: `eclipse-temurin:21-jre-alpine`에 uid 101 미존재 전제 → 빌드 단계에서
  확인(충돌 시 adduser 실패). 충돌하면 미사용 uid로 변경 + gitops runAsUser 동기화.
- **learning-ai 런타임 쓰기**: uvicorn/FastAPI가 /app·cwd에 쓰지 않는다는 전제(stateless).
  런타임에 Permission denied 발생 시 emptyDir 마운트 또는 쓰기 경로 조정.

## 검증 계획

| 항목 | 방법 | 시점 |
|------|------|------|
| 3개 이미지 비-root 빌드 | `docker build` 성공 + `docker run --rm <img> id` = uid 101 | 이번 작업 |
| minikube 비-root 기동 | `kubectl exec -- id` uid=101, 파드 1/1 | 이번 작업 |
| minikube 회귀 | `kubectl get pods` 전체 Running | 이번 작업 |
| EKS 렌더 정합성 | `kustomize build` 3개 overlay | 이번 작업 |
| yamllint CI | gitops `validate` | gitops PR |
| EKS 런타임 비-root | ECR 이미지 기동 확인 | 태스크 A |

## 영향 범위 / PR

- **synapse-gateway** (1 PR): Dockerfile.
- **synapse-engagement-svc** (1 PR): Dockerfile.
- **synapse-learning-svc** (1 PR): learning-ai/Dockerfile.
- **synapse-gitops** (1 PR): apps/{gateway,engagement-svc,learning-ai}/base/deployment.yaml securityContext.
