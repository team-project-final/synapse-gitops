# Deploy / Mirror 워크플로우 표준화 설계

- 작성일: 2026-05-27
- 대상 리포: synapse-engagement-svc, synapse-knowledge-svc, synapse-platform-svc, synapse-learning-svc, synapse-gateway (+ mirror 대상 synapse-frontend, synapse-shared)
- 표준 워크플로우 호스트: synapse-shared
- 배포 소스 오브 트루스: synapse-gitops (`apps/<app>/overlays/dev/kustomization.yaml`)

## 1. 배경 / 점검 동기

각 작업 리포의 `.github/workflows/deploy.yml`, `mirror.yml` 구성을 점검한 결과,
**dev 배포 파이프라인이 모든 백엔드 서비스에서 사실상 무동작(silent no-op)** 임을 확인했다.
빌드/푸시가 실패하거나, 성공하더라도 gitops 이미지 태그가 갱신되지 않아 ArgoCD 롤아웃이
발생하지 않는다. `mirror.yml`은 6개 리포에서 바이트 단위로 동일하며 정상이다.

본 문서는 (a) 점검 결과(감사)와 (b) 표준화 설계를 함께 담는다.

## 2. 감사 결과 (Audit Findings)

### 2.1 deploy.yml — 핵심 결함: gitops bump가 절대 실행되지 않음 (Critical)

gitops 리포의 앱 디렉토리는 `synapse-` 접두사가 **없다**:
`apps/engagement-svc`, `apps/knowledge-svc`, `apps/platform-svc`, `apps/learning-ai`, `apps/learning-card`.

그러나 모든 `deploy.yml`은 서비스명을 리포명에서 유도한다:

```sh
SERVICE="${GITHUB_REPOSITORY##*/}"        # → synapse-engagement-svc
KUSTOMIZATION="apps/${SERVICE}/overlays/dev/kustomization.yaml"
# → apps/synapse-engagement-svc/overlays/dev/kustomization.yaml  (존재하지 않음)
if [ ! -f "$KUSTOMIZATION" ]; then
  echo "::warning::Kustomization not found"; exit 0   # 조용히 종료
fi
```

`synapse-` 접두사 불일치로 파일을 찾지 못해 `exit 0`. **이미지 태그가 영원히 갱신되지 않는다.**

### 2.2 deploy.yml — 백엔드 svc 4종에 ECR 인증 단계 없음 (High)

engagement / knowledge / learning / platform 의 `deploy.yml`은 `secrets.ECR_REGISTRY`를
레지스트리 문자열로만 사용하고 `aws-actions/configure-aws-credentials`,
`aws-actions/amazon-ecr-login`이 **없다**. 경로가 맞았더라도 `docker push`가 인증 실패한다.
(gateway는 이 인증을 올바르게 수행 → 표준의 기준점.)

### 2.3 deploy.yml — 이미지 리포 경로 불일치 (High)

워크플로우는 `<registry>/synapse-engagement-svc` 로 푸시하지만, gitops `newName`은
`963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/engagement-svc` 를 기대한다
(`synapse/<app>` 네임스페이스, 접두사 없음).

### 2.4 deploy.yml — synapse-learning-svc는 모노레포 (High)

`synapse-learning-svc`는 `learning-ai/Dockerfile`, `learning-card/Dockerfile` 두 개를 가진
모노레포이며 gitops에서도 `learning-ai`, `learning-card` 두 앱으로 분리된다.
그러나 `deploy.yml`은 루트에서 단일 `docker build .`를 수행한다(루트 Dockerfile 없음).
→ 이름·빌드·앱 매핑 모두 불일치.

### 2.5 deploy.yml — synapse-gateway (Medium)

gateway는 ECR 인증을 올바르게 수행하나, gitops를 `services/synapse-gateway/dev/kustomization.yaml`
경로로 갱신 시도한다. gitops에는 `services/` 트리도, `apps/gateway` 오버레이도 없다
(gateway는 현재 `local-k8s/gateway.yaml`에만 존재). → AWS dev로 온보딩하기로 결정.

추가 불일치: gateway는 `sed`로 `newTag:`를 수정하고 `:latest` 태그도 푸시하나,
svc 계열은 `yq '.images[0].newTag'`를 사용. 도구/태깅 전략이 갈린다.

### 2.6 GitHub Pages 계열 deploy.yml (참고)

synapse-prototype / schedule-repo / moking-data-guide 는 서로 다른 3가지 Pages 배포 패턴.
서비스 배포와 무관하므로 본 표준화 범위 밖(현상 유지). `moking-data-guide`는 빌드 단계 없이
리포 루트를 그대로 게시한다는 점만 기록.

### 2.7 mirror.yml — 정상 (Good)

engagement / knowledge / learning / platform / frontend / shared 6개 리포에서 바이트 단위 동일.
`synapse-mirror`로 rsync, 시크릿 제외(`.env*`, `*.key`, `*.pem`) 적절. 결함 없음.
단, 6개 동일 복사본이라 향후 드리프트 위험이 있어 reusable 전환 대상으로 삼는다.

### 2.8 범위 밖 관찰

`ci-java.yml`이 synapse-shared와 svc 리포 간 이미 드리프트(shared에는 `dev` 트리거·`dev-smoke`
잡 없음). 동일한 중앙화로 추후 정리 가능하나 본 작업 범위에는 포함하지 않는다.

## 3. 표준화 설계 (Approach A — Reusable Workflow)

### 3.1 결정 사항

- **방식 A**: synapse-shared에 `workflow_call` reusable 워크플로우를 두고, 각 리포는 얇은 caller만 보유.
- **gateway**: AWS dev 배포 대상으로 온보딩(gitops 오버레이 + ECR 리포 신규 생성).
- **mirror.yml**: deploy와 동일 패턴으로 reusable 전환.
- **AWS 인증**: GitHub OIDC + IAM `role-to-assume` (장기 액세스키 미사용).
  gitops `infra/aws/dev/image-updater-irsa.tf`가 이미 OIDC 기반이라 결이 맞음.
- **gitops 갱신 도구**: `yq`로 통일(구조화된 YAML 리스트 편집).

### 3.2 정규 매핑 테이블 (caller가 선언하는 계약)

| 리포 | gitops app | dev 오버레이(bump 대상) | ECR 리포(push 대상) | 빌드 컨텍스트 |
|---|---|---|---|---|
| synapse-engagement-svc | `engagement-svc` | `apps/engagement-svc/overlays/dev/kustomization.yaml` | `synapse/engagement-svc` | `.` |
| synapse-knowledge-svc | `knowledge-svc` | `apps/knowledge-svc/overlays/dev/…` | `synapse/knowledge-svc` | `.` |
| synapse-platform-svc | `platform-svc` | `apps/platform-svc/overlays/dev/…` | `synapse/platform-svc` | `.` |
| synapse-learning-svc | `learning-ai` | `apps/learning-ai/overlays/dev/…` | `synapse/learning-ai` | `learning-ai/` |
| synapse-learning-svc | `learning-card` | `apps/learning-card/overlays/dev/…` | `synapse/learning-card` | `learning-card/` |
| synapse-gateway *(신규)* | `gateway` | `apps/gateway/overlays/dev/…` *(생성)* | `synapse/gateway` *(생성)* | `.` |

공통 값: registry `963773969059.dkr.ecr.ap-northeast-2.amazonaws.com`, namespace `synapse/`, region `ap-northeast-2`.

### 3.3 Reusable 워크플로우: `synapse-shared/.github/workflows/deploy-service.yml`

```yaml
on:
  workflow_call:
    inputs:
      gitops_app:     { required: true,  type: string }   # 예: engagement-svc
      ecr_repository: { required: true,  type: string }   # 예: synapse/engagement-svc
      build_context:  { required: false, type: string, default: "." }
      dockerfile:     { required: false, type: string, default: "Dockerfile" }
    secrets:
      AWS_ROLE_ARN:   { required: true }
      GITOPS_TOKEN:   { required: true }
```

잡 단계:
1. `actions/checkout@v4`
2. `aws-actions/configure-aws-credentials@v4` — `role-to-assume: ${{ secrets.AWS_ROLE_ARN }}`, OIDC (`permissions: id-token: write`)
3. `aws-actions/amazon-ecr-login@v3` → registry 출력
4. `docker build -f <dockerfile> <build_context>` → `:<sha>` 태그 → `<registry>/<ecr_repository>:<sha>` 푸시
5. synapse-gitops clone → `yq -i '.images[0].newTag = "<sha>"' apps/<gitops_app>/overlays/dev/kustomization.yaml` → commit & push (`GITOPS_TOKEN`)

> 경로가 실제로 존재하므로 bump가 비로소 반영된다. newTag는 불변 태그(git SHA)로 갱신 → ArgoCD 롤아웃.

### 3.4 Reusable 워크플로우: `synapse-shared/.github/workflows/mirror-service.yml`

현행 `mirror.yml` 로직을 그대로 이식(`workflow_call`). 입력 없음(서비스명은 `github.repository`에서 유도하되
mirror는 경로 매핑이 단순하므로 현 로직 유지). secrets: `MIRROR_TOKEN`.

### 3.5 리포별 caller (얇은 호출부)

표준 svc 예시 (`synapse-engagement-svc/.github/workflows/deploy.yml`):

```yaml
name: Deploy
on:
  push: { branches: [main] }
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

`synapse-learning-svc`는 **두 잡**으로 호출:

```yaml
jobs:
  learning-ai:
    uses: …/deploy-service.yml@main
    secrets: inherit
    with: { gitops_app: learning-ai,  ecr_repository: synapse/learning-ai,  build_context: learning-ai }
  learning-card:
    uses: …/deploy-service.yml@main
    secrets: inherit
    with: { gitops_app: learning-card, ecr_repository: synapse/learning-card, build_context: learning-card }
```

mirror caller (6개 리포 동일):

```yaml
name: Mirror
on:
  push: { branches: [main] }
jobs:
  mirror:
    uses: team-project-final/synapse-shared/.github/workflows/mirror-service.yml@main
    secrets: inherit
```

### 3.6 gateway 온보딩 (gitops + infra 선행 작업)

- synapse-gitops에 `apps/gateway/base` + `apps/gateway/overlays/dev` 신규 생성
  (다른 svc 오버레이 구조를 따른다; 이미지 `name: ghcr.io/team-project-final/synapse-gateway`,
  `newName: …/synapse/gateway`, `newTag: dev-latest`).
- ECR 리포 `synapse/gateway` 생성(`infra/aws/dev/image-updater-irsa.tf` 패턴 참고).
- 위 두 가지 완료 후 gateway caller 추가. (선행 미완 시 동일한 "경로 없음" no-op 발생.)

## 4. 산출물 (Deliverables)

1. **감사 리포트** — 본 문서 §2.
2. **표준 워크플로우** — synapse-shared에 `deploy-service.yml`, `mirror-service.yml`.
3. **리포별 caller 교체** — 5개 백엔드 서비스(learning은 2잡) + 6개 mirror caller.
4. **gateway 온보딩** — gitops 오버레이 + ECR 리포 + caller.
5. **시크릿/IAM** — OIDC IAM role(`AWS_ROLE_ARN`) 및 각 리포 시크릿(`GITOPS_TOKEN`, `MIRROR_TOKEN`) 정합성 확인.

## 5. 리스크 / 오픈 아이템

- **OIDC IAM role 미존재 가능성**: `image-updater-irsa.tf`가 OIDC 기반이나, GitHub Actions용
  배포 role(ECR push + gitops push 권한)이 별도로 필요할 수 있음. 적용 전 확인.
- **reusable 워크플로우 참조 ref**: `@main` 고정 vs 태그 핀 고정. 초기엔 `@main`, 안정화 후 태그 권장.
- **learning 모노레포 경로 변경 트리거**: 추후 `paths:` 필터로 변경된 하위 서비스만 빌드하도록 최적화 가능(본 범위 밖).
- **gateway ECR/overlay 선행 의존**: caller보다 먼저 생성되어야 함.
- 범위 밖: `ci-java.yml` 드리프트(별도 작업).

## 6. 검증 (구현 후)

- 각 서비스 main 푸시 → Actions에서 `deploy-service.yml` 호출 성공 → ECR에 `:<sha>` 존재 확인.
- synapse-gitops `apps/<app>/overlays/dev/kustomization.yaml`의 `newTag`가 해당 SHA로 갱신됨 확인.
- ArgoCD에서 해당 앱 Synced/Healthy 및 새 이미지 롤아웃 확인.
- mirror: main 푸시 → `synapse-mirror/services/<svc>` 갱신 확인.
