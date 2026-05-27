# Deploy / Mirror 워크플로우 표준화 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 백엔드 서비스들의 `deploy.yml`/`mirror.yml`을 synapse-shared의 reusable workflow + 얇은 caller로 수렴시켜 gitops bump가 실제로 동작하게 하고, gateway를 AWS dev 배포로 온보딩한다.

**Architecture:** synapse-shared에 `workflow_call` 형 reusable 워크플로우 2개(`deploy-service.yml`, `mirror-service.yml`)를 두고, 각 작업 리포는 service→gitops-app→ecr-repo→build-context 매핑만 인자로 넘기는 caller만 보유한다. learning-svc는 모노레포라 caller에서 2회 호출한다. gateway는 synapse-gitops에 overlay를 신설한 뒤 caller를 추가한다.

**Tech Stack:** GitHub Actions (`workflow_call`), AWS ECR + GitHub OIDC(`aws-actions/*`), kustomize + `yq`, rsync, ArgoCD(gitops).

**Spec:** `docs/superpowers/specs/2026-05-27-deploy-mirror-workflow-standardization-design.md`

---

## Prerequisites (외부 선행조건 — 이 계획의 태스크 아님)

구현 시작 전 아래가 충족되어야 최종 활성화/검증이 가능하다. 미충족이어도 Phase 1~3(파일 작업)은 진행 가능하며, 실제 배포 검증(Phase 4)만 블록된다.

- [ ] **`AWS_ROLE_ARN`** — GitHub Actions OIDC deploy role (ECR push 권한). **인프라 워크스트림 소유** (W3 IRSA 작업의 일환). 프로비저닝 후 org 또는 각 서비스 리포 secret으로 등록.
- [ ] **`GITOPS_TOKEN`** — 등록 완료(✅, `contents:write` on synapse-gitops). 변경 불필요.
- [ ] **`MIRROR_TOKEN`** — 등록 완료(✅, `contents:write` on synapse-mirror). 변경 불필요.
- [ ] **ECR 리포지토리** — 기존 svc(`synapse/engagement-svc`, `synapse/knowledge-svc`, `synapse/platform-svc`, `synapse/learning-ai`, `synapse/learning-card`)는 인프라 워크스트림이 소유. 신규 `synapse/gateway`는 Task 6의 선행조건으로 인프라가 생성.
- [ ] **로컬 도구**(파일 검증용): `actionlint`, `kustomize`, `yq`(mikefarah v4). 검증 단계에서 사용.

> 참고: 현재 `ECR_REGISTRY` 시크릿은 미등록(“Phase 3 예정”)이며 OIDC 표준 채택 시 더 이상 필요 없다(`amazon-ecr-login`이 registry를 출력). 기존 caller의 `ECR_REGISTRY` 의존은 본 계획에서 제거된다.

---

## Phase 1 — synapse-shared reusable 워크플로우

**Files:**
- Create: `synapse-shared/.github/workflows/deploy-service.yml`
- Create: `synapse-shared/.github/workflows/mirror-service.yml`

> 작업 브랜치: synapse-shared 기본 브랜치(default, 보통 `main`) 기준 `feat/reusable-deploy-mirror`. reusable 워크플로우는 caller가 `@main`으로 참조하므로 **반드시 기본 브랜치에 머지**되어야 caller가 동작한다.

### Task 1: `deploy-service.yml` (reusable deploy)

**Files:**
- Create: `synapse-shared/.github/workflows/deploy-service.yml`

- [ ] **Step 1: 파일 생성**

```yaml
name: Deploy Service (reusable)

on:
  workflow_call:
    inputs:
      gitops_app:
        description: "gitops apps/<name> (synapse- 접두사 없음). 예: engagement-svc"
        required: true
        type: string
      ecr_repository:
        description: "ECR 리포 경로. 예: synapse/engagement-svc"
        required: true
        type: string
      build_context:
        description: "docker build 컨텍스트 경로"
        required: false
        type: string
        default: "."
      dockerfile:
        description: "Dockerfile 경로(컨텍스트 기준)"
        required: false
        type: string
        default: "Dockerfile"
    secrets:
      AWS_ROLE_ARN:
        required: true
      GITOPS_TOKEN:
        required: true

permissions:
  contents: read
  id-token: write          # OIDC 토큰 발급에 필요

env:
  AWS_REGION: ap-northeast-2

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to Amazon ECR
        id: ecr-login
        uses: aws-actions/amazon-ecr-login@v3

      - name: Build and push image
        id: build
        env:
          REGISTRY: ${{ steps.ecr-login.outputs.registry }}
          REPO: ${{ inputs.ecr_repository }}
          TAG: ${{ github.sha }}
        run: |
          IMAGE="${REGISTRY}/${REPO}:${TAG}"
          docker build -f "${{ inputs.build_context }}/${{ inputs.dockerfile }}" -t "$IMAGE" "${{ inputs.build_context }}"
          docker push "$IMAGE"
          echo "tag=${TAG}" >> "$GITHUB_OUTPUT"

      - name: Bump gitops image tag
        env:
          TAG: ${{ steps.build.outputs.tag }}
        run: |
          git clone --depth 1 \
            "https://x-access-token:${{ secrets.GITOPS_TOKEN }}@github.com/team-project-final/synapse-gitops.git" _gitops
          cd _gitops

          KUSTOMIZATION="apps/${{ inputs.gitops_app }}/overlays/dev/kustomization.yaml"
          if [ ! -f "$KUSTOMIZATION" ]; then
            echo "::error::Kustomization not found: $KUSTOMIZATION (gitops_app 입력 확인)"
            exit 1
          fi

          yq -i '.images[0].newTag = strenv(TAG)' "$KUSTOMIZATION"

          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add -A
          if git diff --cached --quiet; then
            echo "No gitops changes."
            exit 0
          fi
          git commit -m "deploy: bump ${{ inputs.gitops_app }} to ${TAG}"
          git push
```

> 핵심 변경점 vs 기존: (1) `apps/<gitops_app>/...` 입력 기반 경로 → `synapse-` 접두사 버그 제거. (2) 경로 미존재 시 `exit 1`(조용한 no-op 금지). (3) OIDC 인증 추가. (4) `yq strenv(TAG)`로 SHA를 안전히 주입.

- [ ] **Step 2: actionlint 검증**

Run:
```bash
cd /c/workspace/team-project-final/synapse-shared
actionlint .github/workflows/deploy-service.yml
```
Expected: 출력 없음(에러 0). `workflow_call` inputs/secrets 인터페이스가 유효해야 한다.

- [ ] **Step 3: 커밋**

```bash
git add .github/workflows/deploy-service.yml
git commit -m "ci: add reusable deploy-service workflow"
```

### Task 2: `mirror-service.yml` (reusable mirror)

**Files:**
- Create: `synapse-shared/.github/workflows/mirror-service.yml`

- [ ] **Step 1: 파일 생성** (기존 mirror.yml 로직 이식, 서비스명은 caller 리포에서 유도)

```yaml
name: Mirror Service (reusable)

on:
  workflow_call:
    secrets:
      MIRROR_TOKEN:
        required: true

permissions:
  contents: read

jobs:
  mirror:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout source
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Checkout synapse-mirror
        uses: actions/checkout@v4
        with:
          repository: team-project-final/synapse-mirror
          token: ${{ secrets.MIRROR_TOKEN }}
          path: _mirror
          fetch-depth: 0

      - name: Determine service name
        id: meta
        run: echo "service=${GITHUB_REPOSITORY##*/}" >> "$GITHUB_OUTPUT"

      - name: Rsync to mirror
        run: |
          SERVICE_DIR="_mirror/services/${{ steps.meta.outputs.service }}"
          mkdir -p "$SERVICE_DIR"
          rsync -av --delete \
            --exclude='.git' \
            --exclude='_mirror' \
            --exclude='node_modules' \
            --exclude='build' \
            --exclude='target' \
            --exclude='.gradle' \
            --exclude='__pycache__' \
            --exclude='.venv' \
            --exclude='.env*' \
            --exclude='*.key' \
            --exclude='*.pem' \
            ./ "$SERVICE_DIR/"

      - name: Commit and push if changes
        working-directory: _mirror
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add -A
          if git diff --cached --quiet; then
            echo "No changes to mirror."
            exit 0
          fi
          git commit -m "mirror: sync ${{ steps.meta.outputs.service }} @ ${GITHUB_SHA::8}"
          git push
```

> `github.repository`는 `workflow_call`에서 **caller 리포**를 가리키므로 서비스명 유도가 그대로 정확하다(deploy와 달리 mirror는 경로 매핑 버그 없음).

- [ ] **Step 2: actionlint 검증**

Run:
```bash
cd /c/workspace/team-project-final/synapse-shared
actionlint .github/workflows/mirror-service.yml
```
Expected: 출력 없음(에러 0).

- [ ] **Step 3: 커밋**

```bash
git add .github/workflows/mirror-service.yml
git commit -m "ci: add reusable mirror-service workflow"
```

### Task 3: synapse-shared PR → 기본 브랜치 머지

- [ ] **Step 1: 푸시 + PR**

```bash
git push -u origin feat/reusable-deploy-mirror
gh pr create --repo team-project-final/synapse-shared \
  --base main \
  --title "ci: reusable deploy/mirror 워크플로우 추가" \
  --body "deploy.yml/mirror.yml 표준화. caller가 @main으로 참조하므로 머지 필요."
```
Expected: PR URL 출력.

- [ ] **Step 2: 머지 확인(검증 게이트)**

Run:
```bash
gh pr view --repo team-project-final/synapse-shared --json state,mergedAt
```
Expected: `"state": "MERGED"`. **머지 전에는 Phase 3 caller가 동작하지 않는다.**

---

## Phase 2 — synapse-gitops gateway 온보딩

**Files (synapse-gitops, base=`main`, 브랜치 `feat/gateway-dev-overlay`):**
- Create: `apps/gateway/base/deployment.yaml`
- Create: `apps/gateway/base/service.yaml`
- Create: `apps/gateway/base/configmap.yaml`
- Create: `apps/gateway/base/externalsecret.yaml`
- Create: `apps/gateway/base/kustomization.yaml`
- Create: `apps/gateway/overlays/dev/kustomization.yaml`

> 기존 `apps/engagement-svc/base` 패턴을 그대로 따른다. gateway env는 `local-k8s/gateway.yaml`에서 가져온다. **인프라/게이트웨이 오너가 redis 시크릿 경로·route URI·헬스 그룹을 검증**해야 한다(아래 값은 기존 패턴 기반 초안이며 자리표시자가 아님).

### Task 4: gateway base 매니페스트

- [ ] **Step 1: `apps/gateway/base/deployment.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gateway
  labels:
    app.kubernetes.io/name: gateway
    app.kubernetes.io/part-of: synapse
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: gateway
  template:
    metadata:
      labels:
        app.kubernetes.io/name: gateway
        app.kubernetes.io/part-of: synapse
    spec:
      containers:
        - name: gateway
          image: ghcr.io/team-project-final/synapse-gateway:latest
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: gateway-config
            - secretRef:
                name: gateway-secret
                optional: true
          livenessProbe:
            httpGet:
              path: /actuator/health
              port: 8080
            initialDelaySeconds: 90
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /actuator/health
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
```

- [ ] **Step 2: `apps/gateway/base/service.yaml`**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: gateway
  labels:
    app.kubernetes.io/name: gateway
    app.kubernetes.io/part-of: synapse
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
      name: http
  selector:
    app.kubernetes.io/name: gateway
```

- [ ] **Step 3: `apps/gateway/base/configmap.yaml`** (route URI는 클러스터 내부 DNS, base에 고정)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: gateway-config
  labels:
    app.kubernetes.io/name: gateway
    app.kubernetes.io/part-of: synapse
data:
  LOG_LEVEL: "INFO"
  SERVER_PORT: "8080"
  SPRING_PROFILES_ACTIVE: "default"
  PLATFORM_SVC_URI: "http://platform-svc:80"
  ENGAGEMENT_SVC_URI: "http://engagement-svc:80"
  KNOWLEDGE_SVC_URI: "http://knowledge-svc:80"
  LEARNING_SVC_URI: "http://learning-card:80"
```

- [ ] **Step 4: `apps/gateway/base/externalsecret.yaml`** (Redis 비밀번호; secretStoreRef는 overlay에서 패치)

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: gateway-external-secret
  labels:
    app.kubernetes.io/name: gateway
    app.kubernetes.io/part-of: synapse
spec:
  refreshInterval: 5m
  secretStoreRef:
    name: TO_BE_PATCHED
    kind: ClusterSecretStore
  target:
    name: gateway-secret
    creationPolicy: Owner
  data:
    - secretKey: SPRING_DATA_REDIS_PASSWORD
      remoteRef:
        key: synapse/dev/gateway/redis-password
```

- [ ] **Step 5: `apps/gateway/base/kustomization.yaml`**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
  - configmap.yaml
  - externalsecret.yaml

commonLabels:
  app.kubernetes.io/managed-by: kustomize
```

- [ ] **Step 6: 커밋**

```bash
cd /c/workspace/team-project-final/synapse-gitops
git add apps/gateway/base
git commit -m "gitops: add gateway base manifests"
```

### Task 5: gateway dev overlay

- [ ] **Step 1: `apps/gateway/overlays/dev/kustomization.yaml`** (platform-svc dev 패턴 기반: redis TLS)

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: synapse-dev

patches:
  - target:
      kind: Deployment
      name: gateway
    patch: |
      - op: replace
        path: /spec/replicas
        value: 1
  - target:
      kind: ConfigMap
      name: gateway-config
    patch: |
      - op: replace
        path: /data/LOG_LEVEL
        value: "DEBUG"
      - op: replace
        path: /data/SPRING_PROFILES_ACTIVE
        value: "dev"
      - op: add
        path: /data/SPRING_DATA_REDIS_HOST
        value: "master.synapse-dev-redis.v6lpdh.apn2.cache.amazonaws.com"
      - op: add
        path: /data/SPRING_DATA_REDIS_PORT
        value: "6379"
      - op: add
        path: /data/SPRING_DATA_REDIS_SSL_ENABLED
        value: "true"
  - target:
      kind: ExternalSecret
      name: gateway-external-secret
    patch: |
      - op: replace
        path: /spec/secretStoreRef/name
        value: aws-secrets-manager

images:
  - name: ghcr.io/team-project-final/synapse-gateway
    newName: 963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/gateway
    newTag: dev-latest
```

- [ ] **Step 2: 커밋**

```bash
git add apps/gateway/overlays/dev
git commit -m "gitops: add gateway dev overlay"
```

### Task 6: gateway overlay 검증 + PR

- [ ] **Step 1: kustomize build 검증**

Run:
```bash
cd /c/workspace/team-project-final/synapse-gitops
kustomize build apps/gateway/overlays/dev
```
Expected: 에러 없이 Deployment/Service/ConfigMap/ExternalSecret 렌더링. 이미지가 `963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/gateway:dev-latest`로 치환됨.

- [ ] **Step 2: `yq` bump 표현식 검증**(deploy 워크플로우가 쓸 경로/표현식이 동작하는지)

Run:
```bash
TAG=testsha123 yq '.images[0].newTag = strenv(TAG)' apps/gateway/overlays/dev/kustomization.yaml | grep newTag
```
Expected: `    newTag: testsha123` 출력(파일 미수정, 표현식만 확인).

- [ ] **Step 3: 푸시 + PR** (선행: 인프라가 ECR 리포 `synapse/gateway` 생성)

```bash
git push -u origin feat/gateway-dev-overlay
gh pr create --repo team-project-final/synapse-gitops \
  --base main \
  --title "gitops: gateway AWS dev 온보딩(base + dev overlay)" \
  --body "gateway를 AWS dev로 온보딩. 선행: ECR 리포 synapse/gateway 생성(인프라). redis 시크릿 경로/route URI 오너 검증 필요."
```
Expected: PR URL 출력. 머지 후 gateway deploy caller(Task 11)가 bump 대상 경로를 갖게 된다.

---

## Phase 3 — 리포별 caller 교체

> 공통 규칙: 각 리포에서 컨벤션대로 통합 브랜치(`dev` 존재 시 dev, 없으면 default) 기준 `feat/deploy-mirror-caller` 브랜치 생성 → 커밋 → 푸시 → PR. **Phase 1(Task 3) 머지 완료가 선행조건.**

### Task 7: engagement-svc deploy caller

**Files:**
- Modify(replace): `synapse-engagement-svc/.github/workflows/deploy.yml`

- [ ] **Step 1: 파일 전체 교체**

```yaml
name: Deploy

on:
  push:
    branches: [main]

permissions:
  contents: read
  id-token: write

jobs:
  deploy:
    uses: team-project-final/synapse-shared/.github/workflows/deploy-service.yml@main
    secrets: inherit
    with:
      gitops_app: engagement-svc
      ecr_repository: synapse/engagement-svc
```

- [ ] **Step 2: actionlint 검증**

Run: `actionlint .github/workflows/deploy.yml`
Expected: 에러 0. (caller의 `uses:` 원격 참조는 actionlint가 형식만 검사.)

- [ ] **Step 3: 커밋**

```bash
git add .github/workflows/deploy.yml
git commit -m "ci: use reusable deploy-service workflow"
```

### Task 8: knowledge-svc deploy caller

**Files:**
- Modify(replace): `synapse-knowledge-svc/.github/workflows/deploy.yml`

- [ ] **Step 1: 파일 전체 교체**

```yaml
name: Deploy

on:
  push:
    branches: [main]

permissions:
  contents: read
  id-token: write

jobs:
  deploy:
    uses: team-project-final/synapse-shared/.github/workflows/deploy-service.yml@main
    secrets: inherit
    with:
      gitops_app: knowledge-svc
      ecr_repository: synapse/knowledge-svc
```

- [ ] **Step 2: actionlint 검증** — `actionlint .github/workflows/deploy.yml` → 에러 0.
- [ ] **Step 3: 커밋** — `git add .github/workflows/deploy.yml && git commit -m "ci: use reusable deploy-service workflow"`

### Task 9: platform-svc deploy caller

**Files:**
- Modify(replace): `synapse-platform-svc/.github/workflows/deploy.yml`

- [ ] **Step 1: 파일 전체 교체**

```yaml
name: Deploy

on:
  push:
    branches: [main]

permissions:
  contents: read
  id-token: write

jobs:
  deploy:
    uses: team-project-final/synapse-shared/.github/workflows/deploy-service.yml@main
    secrets: inherit
    with:
      gitops_app: platform-svc
      ecr_repository: synapse/platform-svc
```

- [ ] **Step 2: actionlint 검증** — `actionlint .github/workflows/deploy.yml` → 에러 0.
- [ ] **Step 3: 커밋** — `git add .github/workflows/deploy.yml && git commit -m "ci: use reusable deploy-service workflow"`

### Task 10: learning-svc deploy caller (모노레포 → 2잡)

**Files:**
- Modify(replace): `synapse-learning-svc/.github/workflows/deploy.yml`

- [ ] **Step 1: 파일 전체 교체** (learning-ai, learning-card 각각 별도 잡)

```yaml
name: Deploy

on:
  push:
    branches: [main]

permissions:
  contents: read
  id-token: write

jobs:
  learning-ai:
    uses: team-project-final/synapse-shared/.github/workflows/deploy-service.yml@main
    secrets: inherit
    with:
      gitops_app: learning-ai
      ecr_repository: synapse/learning-ai
      build_context: learning-ai
  learning-card:
    uses: team-project-final/synapse-shared/.github/workflows/deploy-service.yml@main
    secrets: inherit
    with:
      gitops_app: learning-card
      ecr_repository: synapse/learning-card
      build_context: learning-card
```

> `build_context`가 하위 디렉토리이고 각 디렉토리에 `Dockerfile`이 있으므로 `dockerfile` 입력은 기본값(`Dockerfile`) 사용 → 실제 빌드는 `learning-ai/Dockerfile`, `learning-card/Dockerfile`.

- [ ] **Step 2: actionlint 검증** — `actionlint .github/workflows/deploy.yml` → 에러 0.
- [ ] **Step 3: 커밋** — `git add .github/workflows/deploy.yml && git commit -m "ci: split learning deploy into ai/card via reusable workflow"`

### Task 11: gateway deploy caller

**Files:**
- Modify(replace): `synapse-gateway/.github/workflows/deploy.yml`

> **선행조건:** Phase 2(Task 6) 머지 + ECR 리포 `synapse/gateway` 존재. 미충족 시 bump 단계가 `exit 1`.

- [ ] **Step 1: 파일 전체 교체**

```yaml
name: Deploy

on:
  push:
    branches: [main]
    paths-ignore:
      - 'docs/**'
      - '*.md'

permissions:
  contents: read
  id-token: write

jobs:
  deploy:
    uses: team-project-final/synapse-shared/.github/workflows/deploy-service.yml@main
    secrets: inherit
    with:
      gitops_app: gateway
      ecr_repository: synapse/gateway
```

- [ ] **Step 2: actionlint 검증** — `actionlint .github/workflows/deploy.yml` → 에러 0.
- [ ] **Step 3: 커밋** — `git add .github/workflows/deploy.yml && git commit -m "ci: use reusable deploy-service workflow"`

### Task 12: mirror caller 교체 (6개 리포)

**Files (각 리포에서 Modify(replace)):**
- `synapse-engagement-svc/.github/workflows/mirror.yml`
- `synapse-knowledge-svc/.github/workflows/mirror.yml`
- `synapse-learning-svc/.github/workflows/mirror.yml`
- `synapse-platform-svc/.github/workflows/mirror.yml`
- `synapse-frontend/.github/workflows/mirror.yml`
- `synapse-shared/.github/workflows/mirror.yml`

- [ ] **Step 1: 각 리포에 동일 내용으로 전체 교체**

```yaml
name: Mirror

on:
  push:
    branches: [main]

jobs:
  mirror:
    uses: team-project-final/synapse-shared/.github/workflows/mirror-service.yml@main
    secrets: inherit
```

> synapse-shared 자신도 caller가 된다(자기 리포의 reusable 워크플로우를 `@main`으로 참조 — 동일 리포 참조 허용됨).

- [ ] **Step 2: 각 리포에서 actionlint 검증** — `actionlint .github/workflows/mirror.yml` → 에러 0.
- [ ] **Step 3: 각 리포에서 커밋** — `git add .github/workflows/mirror.yml && git commit -m "ci: use reusable mirror-service workflow"`
- [ ] **Step 4: 각 리포에서 PR 생성/머지** (컨벤션대로)

---

## Phase 4 — 활성화 검증 (Prerequisites 충족 후)

> `AWS_ROLE_ARN` 등록 + ECR 리포 존재 + Phase 1/2 머지 완료 후 수행. 실제 push로만 통합 검증 가능.

### Task 13: 엔드투엔드 배포 검증

- [ ] **Step 1: deploy 트리거** — 임의 서비스(예: engagement-svc) main에 커밋 푸시.

Run:
```bash
gh run list --repo team-project-final/synapse-engagement-svc --workflow Deploy --limit 1
```
Expected: 최신 run `completed / success`.

- [ ] **Step 2: ECR 이미지 확인**

Run:
```bash
aws ecr describe-images --repository-name synapse/engagement-svc --region ap-northeast-2 \
  --query 'sort_by(imageDetails,&imagePushedAt)[-1].imageTags'
```
Expected: 방금 푸시한 커밋 SHA 태그 존재.

- [ ] **Step 3: gitops newTag 반영 확인**

Run:
```bash
cd /c/workspace/team-project-final/synapse-gitops && git pull
yq '.images[0].newTag' apps/engagement-svc/overlays/dev/kustomization.yaml
```
Expected: 해당 커밋 SHA.

- [ ] **Step 4: ArgoCD 롤아웃 확인** — ArgoCD UI/CLI에서 engagement-svc `Synced & Healthy`, 새 이미지로 롤아웃.

- [ ] **Step 5: mirror 검증** — 동일 푸시 후 `synapse-mirror/services/synapse-engagement-svc`가 갱신됐는지 확인.

```bash
gh run list --repo team-project-final/synapse-engagement-svc --workflow Mirror --limit 1
```
Expected: 최신 run `success`.

- [ ] **Step 6: learning 2잡 / gateway 검증** — learning-svc 푸시 시 `learning-ai`/`learning-card` 두 잡 성공 + 두 overlay newTag 갱신. gateway 푸시 시 `synapse/gateway` 이미지 + `apps/gateway/overlays/dev` newTag 갱신.

---

## Self-Review

**1. Spec coverage:**
- §2 감사 결과 → Phase 1(경로/인증/이미지명 수정), Task 10(learning 모노레포), Task 11(gateway 경로), Task 12(mirror)로 커버.
- §3.3 deploy-service.yml → Task 1. §3.4 mirror-service.yml → Task 2. §3.5 callers → Task 7~12. §3.6 gateway 온보딩 → Phase 2(Task 4~6) + Task 11.
- §5 OIDC → Prerequisites(인프라 소유)로 명시. §6 검증 → Phase 4.
- 범위 밖(Pages deploy, ci-java 드리프트)은 spec대로 제외 — 의도된 갭.

**2. Placeholder scan:** 코드 단계는 모두 완전한 YAML/명령 포함. `externalsecret.yaml`의 `name: TO_BE_PATCHED`는 자리표시자가 아니라 **기존 base의 실제 값**(overlay에서 `aws-secrets-manager`로 패치되는 리터럴)임 — engagement-svc base와 동일.

**3. Type consistency:** 입력명(`gitops_app`, `ecr_repository`, `build_context`, `dockerfile`)이 Task 1 정의와 Task 7~11 caller에서 일치. 시크릿명(`AWS_ROLE_ARN`, `GITOPS_TOKEN`, `MIRROR_TOKEN`)이 reusable 정의와 Prerequisites에서 일치. gitops_app 값(`engagement-svc`,`knowledge-svc`,`platform-svc`,`learning-ai`,`learning-card`,`gateway`)이 실제 gitops `apps/` 디렉토리명과 일치(검증 완료).

**의존성 순서:** Task 3(shared 머지) → Task 7~12. Task 6(gateway overlay 머지)+ECR → Task 11. Phase 4 ← 모든 머지 + AWS_ROLE_ARN.
