# gateway·engagement·learning-ai 비-root 컨테이너 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** gateway·engagement·learning-ai 이미지를 비-root(uid 101)로 구동하도록 Dockerfile을 수정하고, gitops base 3개에 `runAsNonRoot`를 활성화한 뒤 minikube에서 비-root 기동을 런타임 검증한다.

**Architecture:** 4개 레포에 걸침 — 앱 레포 3개(synapse-gateway, synapse-engagement-svc, synapse-learning-svc)는 각자 Dockerfile에 uid/gid 101 사용자 추가 후 `USER app`. gitops 레포는 `apps/{gateway,engagement-svc,learning-ai}/base/deployment.yaml`의 securityContext를 기존 비-root 3개와 동일한 풀 블록(runAsNonRoot/runAsUser:101/runAsGroup:101)으로 교체. minikube에서 3개 이미지 재빌드·재배포로 uid 101 기동 검증.

**Tech Stack:** Docker(멀티스테이지), eclipse-temurin alpine(gateway/engagement), python:3.12-slim(learning-ai), Kubernetes/Kustomize, minikube.

**환경:** 형제 레포 루트 `D:/workspace/final-project-syn`(이하 SIB). local 이미지 태그 `synapse-gateway:local`, `synapse-engagement-svc:local`, `synapse-learning-ai:local`. minikube ns `synapse-local`. gitops 작업 브랜치 `feat/nonroot-containers`(spec 커밋 `2ce24aa` 포함).

**PR 구조:** 앱 3 PR + gitops 1 PR = 4 PR. **머지 순서: 앱 3 PR 먼저(이미지에 USER 반영) → gitops PR**(runAsNonRoot가 USER 포함 이미지 전제).

**기존 패턴 참조:** `SIB/synapse-platform-svc/Dockerfile`(jammy: `addgroup --system app && adduser --system --ingroup app app` → uid 101, `chown app:app app.jar`, `USER app`). gitops `apps/platform-svc/base/deployment.yaml:85-93`(풀 securityContext 블록).

---

## File Structure

수정:
- `SIB/synapse-gateway/Dockerfile` — runtime stage에 uid 101 user + USER
- `SIB/synapse-engagement-svc/Dockerfile` — 동일(alpine)
- `SIB/synapse-learning-svc/learning-ai/Dockerfile` — uid 101 user + chown /app + USER(debian-slim)
- `synapse-gitops/apps/gateway/base/deployment.yaml` — securityContext 풀 블록
- `synapse-gitops/apps/engagement-svc/base/deployment.yaml` — securityContext 풀 블록
- `synapse-gitops/apps/learning-ai/base/deployment.yaml` — securityContext 풀 블록

learning-ai 레포 추가(해당 레포 CLAUDE.md 규칙):
- `SIB/synapse-learning-svc/learning-ai/REPORT.md` 및 `docs/project-management/HISTORY` 등에 변경 기록(간단).

---

## Task 1: synapse-gateway Dockerfile 비-root화

**Files:**
- Modify: `D:/workspace/final-project-syn/synapse-gateway/Dockerfile`

현재 runtime stage:
```dockerfile
# Stage 2: Runtime
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=builder /app/build/libs/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

- [ ] **Step 1: 브랜치 생성**

```bash
cd D:/workspace/final-project-syn/synapse-gateway
git checkout main && git pull --ff-only
git checkout -b feat/nonroot-container
```

- [ ] **Step 2: runtime stage 수정**

runtime stage를 다음으로 교체:
```dockerfile
# Stage 2: Runtime
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
RUN addgroup -g 101 -S app && adduser -u 101 -S -G app app
COPY --from=builder /app/build/libs/*.jar app.jar
RUN chown app:app app.jar
USER app
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

- [ ] **Step 3: 빌드 + 비-root 확인**

Run:
```bash
docker build -t synapse-gateway:local D:/workspace/final-project-syn/synapse-gateway
docker run --rm --entrypoint id synapse-gateway:local
```
Expected: 빌드 성공. `id` 출력이 `uid=101(app) gid=101(app) groups=101(app)`.
- 만약 `adduser: uid '101' in use` 류 에러로 빌드 실패 → 베이스에 uid 101 선점. 미사용 uid(예 1001)로 변경하고 이 plan의 gitops Task 4 gateway runAsUser/runAsGroup도 동일 값으로 동기화(보고 후 진행).

- [ ] **Step 4: 커밋 + 푸시**

```bash
cd D:/workspace/final-project-syn/synapse-gateway
git add Dockerfile
git commit -m "build: 비-root(uid 101)로 컨테이너 실행 (runAsNonRoot 대응)"
git push -u origin feat/nonroot-container
```

- [ ] **Step 5: PR 생성**

```bash
gh pr create --base main --head feat/nonroot-container \
  --title "build: 컨테이너 비-root 실행(uid 101)" \
  --body "gitops base의 runAsNonRoot 활성화(B2) 대응. eclipse-temurin alpine runtime을 uid/gid 101 app 유저로 실행. platform/knowledge/learning-card와 동일 패턴.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```
Expected: PR URL. (repo가 PR 템플릿/CI 있으면 통과 확인.)

---

## Task 2: synapse-engagement-svc Dockerfile 비-root화

**Files:**
- Modify: `D:/workspace/final-project-syn/synapse-engagement-svc/Dockerfile`

현재 runtime stage:
```dockerfile
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=builder /app/build/libs/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

- [ ] **Step 1: 브랜치 생성**

```bash
cd D:/workspace/final-project-syn/synapse-engagement-svc
git checkout main && git pull --ff-only
git checkout -b feat/nonroot-container
```

- [ ] **Step 2: runtime stage 수정**

```dockerfile
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
RUN addgroup -g 101 -S app && adduser -u 101 -S -G app app
COPY --from=builder /app/build/libs/*.jar app.jar
RUN chown app:app app.jar
USER app
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

- [ ] **Step 3: 빌드 + 비-root 확인**

Run:
```bash
docker build -t synapse-engagement-svc:local D:/workspace/final-project-syn/synapse-engagement-svc
docker run --rm --entrypoint id synapse-engagement-svc:local
```
Expected: 빌드 성공. `uid=101(app) gid=101(app)`. (uid 충돌 시 Task 1 Step 3와 동일 대응.)

- [ ] **Step 4: 커밋 + 푸시**

```bash
cd D:/workspace/final-project-syn/synapse-engagement-svc
git add Dockerfile
git commit -m "build: 비-root(uid 101)로 컨테이너 실행 (runAsNonRoot 대응)"
git push -u origin feat/nonroot-container
```

- [ ] **Step 5: PR 생성**

```bash
gh pr create --base main --head feat/nonroot-container \
  --title "build: 컨테이너 비-root 실행(uid 101)" \
  --body "gitops base의 runAsNonRoot 활성화(B2) 대응. alpine runtime을 uid/gid 101 app 유저로 실행.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```
참고: engagement 레포는 merge commit 금지(squash/rebase만) — 머지 시 적용.

---

## Task 3: synapse-learning-svc/learning-ai Dockerfile 비-root화

**Files:**
- Modify: `D:/workspace/final-project-syn/synapse-learning-svc/learning-ai/Dockerfile`
- Modify(레포 CLAUDE.md 규칙): `SIB/synapse-learning-svc/learning-ai/REPORT.md`

> **learning-ai 레포 CLAUDE.md 주의:** "모든 코드 수정 전 초안(Draft)을 사용자에게 보여주고 승인". 본 plan의 Dockerfile diff가 그 초안이며 spec 단계에서 승인됨. 작업 후 REPORT.md에 변경 기록(작업일자 포함). docs/project-management 갱신은 인프라(Dockerfile) 변경이라 해당 섹션 있으면만 반영(없으면 생략 가능, 과도 갱신 금지).

현재 runtime stage:
```dockerfile
# Stage 2: Runtime
FROM python:3.12-slim
WORKDIR /app
COPY --from=builder /install /usr/local
COPY . .
ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1
EXPOSE 8090
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8090"]
```

- [ ] **Step 1: 브랜치 생성**

```bash
cd D:/workspace/final-project-syn/synapse-learning-svc
git checkout main && git pull --ff-only
git checkout -b feat/nonroot-container-learning-ai
```

- [ ] **Step 2: runtime stage 수정** (uid 101 + chown /app + USER, ENV 앞에)

```dockerfile
# Stage 2: Runtime
FROM python:3.12-slim
WORKDIR /app
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

- [ ] **Step 3: 빌드 + 비-root 확인**

Run:
```bash
docker build -t synapse-learning-ai:local D:/workspace/final-project-syn/synapse-learning-svc/learning-ai
docker run --rm synapse-learning-ai:local id
```
Expected: 빌드 성공. CMD override로 `id` 실행 → `uid=101(app) gid=101(app)`.
(debian-slim에 uid 101 선점 시 Task 1 Step 3와 동일 대응.)

- [ ] **Step 4: REPORT.md 기록**

`SIB/synapse-learning-svc/learning-ai/REPORT.md` 상단(또는 적절 위치)에 추가:
```markdown
## 2026-06-03 — 컨테이너 비-root 실행
- Dockerfile runtime stage에 uid/gid 101 `app` 유저 생성 + `/app` chown + `USER app` 추가.
- 근거: gitops base의 `runAsNonRoot:true`(B2 보안 하드닝) 대응. uvicorn은 비-root로
  /app(읽기) + /usr/local(읽기) 만 사용 → 권한 문제 없음.
- 이전: root 실행(USER 미지정).
```

- [ ] **Step 5: 커밋 + 푸시**

```bash
cd D:/workspace/final-project-syn/synapse-learning-svc
git add learning-ai/Dockerfile learning-ai/REPORT.md
git commit -m "build(learning-ai): 비-root(uid 101)로 컨테이너 실행 (runAsNonRoot 대응)"
git push -u origin feat/nonroot-container-learning-ai
```

- [ ] **Step 6: PR 생성**

```bash
gh pr create --base main --head feat/nonroot-container-learning-ai \
  --title "build(learning-ai): 컨테이너 비-root 실행(uid 101)" \
  --body "gitops base의 runAsNonRoot 활성화(B2) 대응. python:3.12-slim runtime을 uid/gid 101 app 유저로 실행. /app chown으로 uvicorn 비-root 구동.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

---

## Task 4: gitops base securityContext 3개 활성화

**Files:**
- Modify: `apps/gateway/base/deployment.yaml` (securityContext 현재 68-73행)
- Modify: `apps/engagement-svc/base/deployment.yaml` (securityContext 현재 73-78행)
- Modify: `apps/learning-ai/base/deployment.yaml` (securityContext 현재 80-85행)

작업 위치: `D:/workspace/final-project-syn/synapse-gitops` (브랜치 `feat/nonroot-containers`, 이미 체크아웃).

각 파일의 securityContext 블록은 현재(주석 포함):
```yaml
          # 이미지가 USER 미지정(root)이라 runAsNonRoot는 적용 불가(앱 레포 Dockerfile에 USER 추가 후 활성화 권장).
          # 그 전까지 안전한 항목만: 권한상승 차단 + 모든 capability drop + seccomp 기본.
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            seccompProfile:
              type: RuntimeDefault
```
(주석 문구는 파일마다 약간 다를 수 있음 — `securityContext:` 위의 1~2줄 주석.)

- [ ] **Step 1: gateway securityContext 교체**

`apps/gateway/base/deployment.yaml`에서 위 블록(주석 2줄 포함)을 다음으로 교체:
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

- [ ] **Step 2: engagement-svc securityContext 교체**

`apps/engagement-svc/base/deployment.yaml`에서 동일 교체(위 Step 1과 동일한 풀 블록).

- [ ] **Step 3: learning-ai securityContext 교체**

`apps/learning-ai/base/deployment.yaml`에서 동일 교체(위 Step 1과 동일한 풀 블록).

- [ ] **Step 4: 렌더 검증**

Run:
```bash
cd D:/workspace/final-project-syn/synapse-gitops
for s in gateway engagement-svc learning-ai; do
  echo "--- $s ---"
  kubectl kustomize "apps/$s/overlays/dev" 2>/dev/null | grep -A6 "securityContext:" | head -8
done
```
Expected: 각 서비스 렌더에 `runAsNonRoot: true` + `runAsUser: 101` + `runAsGroup: 101`이 보임.
(gateway는 overlays/dev만 존재.)

- [ ] **Step 5: yamllint(LF) 확인**

Run:
```bash
PY="C:/Users/deepe/AppData/Local/Python/pythoncore-3.14-64/python.exe"
cd D:/workspace/final-project-syn/synapse-gitops
for f in apps/gateway/base/deployment.yaml apps/engagement-svc/base/deployment.yaml apps/learning-ai/base/deployment.yaml; do
  tr -d '\r' < "$f" > /tmp/lf.yaml; "$PY" -m yamllint -c .yamllint /tmp/lf.yaml && echo "clean: $f"
done
```
Expected: 3개 모두 `clean`. (로컬 CRLF의 new-lines 에러는 무시 — CI는 LF.)

- [ ] **Step 6: 커밋**

```bash
cd D:/workspace/final-project-syn/synapse-gitops
git add apps/gateway/base/deployment.yaml apps/engagement-svc/base/deployment.yaml apps/learning-ai/base/deployment.yaml
git commit -m "feat(security): gateway·engagement·learning-ai base runAsNonRoot 활성화 (#100 완성, B2)"
```

---

## Task 5: minikube 런타임 검증

**사전조건:** Task 1~3 이미지가 로컬에 빌드됨(`:local` 태그). minikube `minikube` 프로파일 Running. Task 4 gitops 변경이 `feat/nonroot-containers`에 커밋됨.

- [ ] **Step 1: 새 이미지 3개 minikube 적재**

Run:
```bash
for img in synapse-gateway synapse-engagement-svc synapse-learning-ai; do
  minikube image load "$img:local"
done
```
Expected: 3개 모두 에러 없이 적재.

- [ ] **Step 2: learning-ai 시크릿(OPENAI 키) 존재 확인**

learning-ai는 OPENAI_API_KEY 없으면 CrashLoop(비-root와 무관). 재배포 전 확인:
```bash
kubectl --context minikube -n synapse-local get secret learning-ai-secret -o jsonpath='{.data.LEARNING_AI_OPENAI_API_KEY}' 2>/dev/null | head -c 5; echo " (값 길이 확인)"
```
Expected: 비어있지 않으면 OK. 비어있으면(placeholder) 재주입:
```bash
# env LEARNING_AI_OPENAI_API_KEY 또는 SIB/.learning-ai-key 파일에서
KEY="${LEARNING_AI_OPENAI_API_KEY:-$(cat D:/workspace/final-project-syn/.learning-ai-key 2>/dev/null)}"
[ -n "$KEY" ] && kubectl --context minikube -n synapse-local patch secret learning-ai-secret --type=merge -p "{\"stringData\":{\"LEARNING_AI_OPENAI_API_KEY\":\"$KEY\"}}"
```
(키 소스가 없으면 learning-ai는 비-root 검증에서 CrashLoop일 수 있음 — gateway/engagement만으로도 비-root 패턴은 입증되며 learning-ai는 "이미지 비-root"는 Task 3 Step 3 `docker run id`로 이미 입증됨.)

- [ ] **Step 3: gitops 변경 적용 + 재배포**

local-k8s는 `apps/*/base`를 참조하므로 Task 4 변경이 자동 반영됨.
```bash
kubectl --context minikube apply -k D:/workspace/final-project-syn/synapse-gitops/local-k8s
for d in gateway engagement-svc learning-ai; do
  kubectl --context minikube -n synapse-local rollout restart deploy/$d
done
for d in gateway engagement-svc learning-ai; do
  kubectl --context minikube -n synapse-local rollout status deploy/$d --timeout=300s
done
```
Expected: 3개 deploy 롤아웃 성공. CreateContainerConfigError 없음.
- `container has runAsNonRoot and image will run as root` 이벤트가 보이면 이미지에 USER 미반영 → Task 1~3 재빌드/적재 확인.

- [ ] **Step 4: 파드가 uid 101로 구동 확인 (핵심 검증)**

```bash
for d in gateway engagement-svc; do
  echo "--- $d ---"
  kubectl --context minikube -n synapse-local exec deploy/$d -- id 2>&1
done
# learning-ai는 키가 있고 Running이면:
kubectl --context minikube -n synapse-local exec deploy/learning-ai -- id 2>&1 || echo "learning-ai exec 실패(키 부재 CrashLoop 가능 — Task3 docker id로 대체 입증)"
```
Expected: gateway·engagement `uid=101(app) gid=101(app)`. learning-ai도 가능하면 동일.

- [ ] **Step 5: 전체 회귀 확인**

```bash
kubectl --context minikube -n synapse-local get pods
```
Expected: gateway·engagement·learning-ai 새 파드 1/1 Running(learning-ai는 키 있을 때). 나머지 워크로드 영향 없음.

---

## Task 6: gitops PR 생성

- [ ] **Step 1: 푸시**

```bash
cd D:/workspace/final-project-syn/synapse-gitops
git push -u origin feat/nonroot-containers
```

- [ ] **Step 2: PR 생성**

```bash
gh pr create --repo team-project-final/synapse-gitops \
  --base main --head feat/nonroot-containers \
  --title "feat(security): gateway·engagement·learning-ai 비-root 활성화 (B2)" \
  --body "$(cat <<'EOF'
## 요약
#100 securityContext의 "안전 부분집합만" 상태였던 gateway·engagement·learning-ai를
비-root(runAsNonRoot/runAsUser:101)로 완성. B2 후속 finding.

- gitops base 3개 securityContext를 platform/knowledge/learning-card와 동일 풀 블록으로 통일.
- 앱 레포 3개 Dockerfile에 uid/gid 101 USER 추가(별도 PR):
  synapse-gateway, synapse-engagement-svc, synapse-learning-svc(learning-ai).

## ⚠️ 머지 순서
앱 3 PR이 먼저 머지되어 ECR/ghcr 이미지에 USER가 반영된 뒤 이 PR을 머지할 것.
(runAsNonRoot는 USER 포함 이미지 전제 — 안 그러면 CreateContainerConfigError.)

## 검증
- minikube 런타임: gateway·engagement 파드 `id`=uid 101, 1/1 Running, 회귀 없음.
- 이미지 비-root: `docker run --entrypoint id` = uid 101 (3개).
- EKS: kustomize 렌더에 runAsNonRoot/runAsUser:101 확인. 런타임은 프로비저닝(A)으로 이연.

## 설계/계획
- spec: docs/superpowers/specs/2026-06-03-nonroot-containers-design.md
- plan: docs/superpowers/plans/2026-06-03-nonroot-containers.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
Expected: PR URL. CI `validate` 통과 확인.

---

## Self-Review (작성자 체크)

**Spec 커버리지:**
- 표면1 앱 Dockerfile 3개(uid 101) → Task 1,2,3 ✓
- 표면2 gitops base securityContext 3개 → Task 4 ✓
- 표면3 minikube 런타임 검증 → Task 5 ✓
- 리스크: uid 충돌 대응 → Task 1/2/3 Step 3, learning-ai 키 → Task 5 Step 2, 순서 의존성 → Task 6 PR 본문 ✓
- learning-ai CLAUDE.md(초안/문서) → Task 3 주의 + Step 4 REPORT ✓
- PR 4개 → Task 1·2·3 Step 5/6 + Task 6 ✓

**플레이스홀더:** 없음. uid 충돌 시 대체값은 "보고 후 진행"으로 명시(분기 처리).

**일관성:** uid/gid 101 전 태스크 통일. gitops 풀 블록 = platform/knowledge/learning-card와 동일. 이미지 태그 `synapse-{gateway,engagement-svc,learning-ai}:local` 일치. ns `synapse-local`.
