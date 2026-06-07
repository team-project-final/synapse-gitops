# Frontend 배포 통합 설계 (로컬 k8s + AWS EKS + Gateway 라우팅)

> **작성일**: 2026-06-07
> **상태**: 설계 승인됨 (구현 대기)
> **대상 레포**: synapse-frontend, synapse-gitops, synapse-gateway

## 1. 배경 / 문제

`synapse-frontend`(Flutter web/mobile)는 현재 **어떤 배포 채널에도 포함되어 있지 않다**.

- AWS EKS(ArgoCD ApplicationSet): 백엔드 6개(platform/engagement/knowledge/learning-card/learning-ai/gateway)만 배포. frontend 없음.
- 로컬 k8s(`local-k8s/`): 동일 6개 + infra만. frontend 없음.
- Gateway(`RoutesConfig.java`): `/api/{platform,engagement,knowledge,learning}/**`만 프록시. frontend 라우트 없음.
- frontend 레포: `Dockerfile`·k8s 매니페스트 없음. 워크플로는 `ci-flutter.yml`(CI)·`mirror.yml`·`parse-workflow.yml`뿐 → 배포 파이프라인 부재.

본 설계는 **(a)** 로컬·AWS k8s에 nginx 정적 서빙 Deployment를 추가하고, **(b)** Gateway가 SPA를 단일 진입점으로 서빙하도록 catch-all 라우트를 추가한다.

## 2. 핵심 결정

| 항목 | 결정 | 비고 |
|---|---|---|
| (b) Gateway 노출 | **catch-all 라우트 → `frontend` nginx 서비스** | `/api/**`는 기존 백엔드, 그 외 전부 frontend-svc. 단일 진입점·동일 오리진·CORS 불필요 |
| (a) 정적 서빙 | Flutter web 빌드 → **nginx:alpine** | SPA fallback `try_files $uri $uri/ /index.html` |
| AWS 환경 | base + overlays **dev/staging/prod** 전체 생성 | ApplicationSet env 리스트는 현재 `dev`만 → staging/prod overlay는 dormant(타 svc와 동일 현황) |
| 이미지 | ECR `synapse/frontend` (image-updater), 로컬 `synapse-frontend:local`, base는 ghcr 플레이스홀더 | 기존 svc 패턴 동일 |
| Flutter API base | **동일 오리진 상대경로** (`--dart-define=API_BASE_URL=` 빈 값) | SPA의 `/api/**` 호출이 서빙 오리진=gateway로 감 |

## 3. 푸시 정책 (사용자 지정)

| 레포 | 정책 |
|---|---|
| synapse-gitops, synapse-shared, synapse-gateway | 직접 push 가능 (단, push 직전 사용자 확인) |
| **그 외 전부 (synapse-frontend 포함)** | **별도 브랜치 + 커밋 + push + PR만. main 직접 push 금지** |

## 4. 변경 상세

### 4.1 synapse-frontend *(branch + PR only)*

**브랜치**: `feat/web-docker-nginx` (예시)

1. **`Dockerfile`** — 멀티스테이지
   - stage1 builder: `ghcr.io/cirruslabs/flutter:<pubspec SDK에 맞는 안정 태그>`
     - `flutter pub get`
     - `flutter build web --release --dart-define=API_BASE_URL=` (빈 값 = 동일 오리진 상대경로)
   - stage2 runtime: `nginx:alpine`
     - `COPY --from=builder /app/build/web /usr/share/nginx/html`
     - `COPY nginx.conf /etc/nginx/conf.d/default.conf`
     - non-root 고려: nginx:alpine 기본은 root 마스터+nginx 워커. k8s securityContext와의 정합을 위해 unprivileged 변형(`nginxinc/nginx-unprivileged:alpine`, listen 8080) 사용 검토 → **runtime 이미지는 `nginxinc/nginx-unprivileged:alpine`, listen 8080, containerPort 8080**로 결정(securityContext `runAsNonRoot` 충족).
2. **`nginx.conf`**
   - `listen 8080;`
   - `location / { try_files $uri $uri/ /index.html; }` (SPA fallback)
   - 정적 자산 캐시 헤더, gzip on, `/healthz` 200 응답(프로브용) 또는 `/` 프로브 사용
3. **`.dockerignore`** — `build/`, `.dart_tool/`, `android/`, `ios/`, `.git/` 등 제외
4. **`lib/core/network/app_environment.dart` 수정**
   - `String.fromEnvironment('API_BASE_URL')`가 비어있지 않으면 그 값을, 비어있으면 기존 enum 기반 baseUrl을 사용하도록 분기.
   - 빈 문자열 = 상대경로(동일 오리진) 의미. dio `baseUrl: ''`이면 요청 경로(`/api/...`)가 페이지 오리진 기준으로 해석됨.
   - 기존 enum 기본값은 fallback으로 유지 → 기존 단위 테스트 영향 최소화. 변경에 대한 테스트 추가.
5. (선택) `ci-flutter.yml`에 `docker build` 검증 step 추가.

### 4.2 synapse-gitops *(push 가능, push 전 확인)*

**`apps/frontend/base/`** — platform-svc base 패턴 차용, 단 JVM 전용 요소(Kafka env, actuator 프로브) 제거
- `deployment.yaml`
  - `image: ghcr.io/team-project-final/synapse-frontend:latest` (플레이스홀더)
  - `containerPort: 8080`
  - `minReadySeconds`, RollingUpdate `maxUnavailable: 0/maxSurge: 1`, `terminationGracePeriodSeconds`(짧게, 정적이므로 ~10s)
  - 프로브: `startupProbe`/`livenessProbe`/`readinessProbe` 모두 `httpGet /` (또는 `/healthz`) port 8080. JVM 콜드스타트 불필요 → startup failureThreshold 작게.
  - `resources`: requests cpu 25m/mem 32Mi, limits cpu 200m/mem 128Mi (nginx 경량)
  - `securityContext`: `runAsNonRoot: true`, `runAsUser/Group`(nginx-unprivileged = 101), `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile: RuntimeDefault`
  - `envFrom`: `frontend-config` ConfigMap (필요 최소; 정적이라 거의 비어있음)
- `service.yaml`: ClusterIP, `port: 80 → targetPort: 8080`, name `frontend`
- `configmap.yaml`: `frontend-config` (LOG_LEVEL 등 최소, 없으면 생략 가능)
- `externalsecret.yaml`: 정적 프론트는 시크릿 불필요 → **base에서 생략** (타 svc와 달리 ExternalSecret 없음. 로컬 overlay의 `$patch: delete`도 불필요)
- `kustomization.yaml`: deployment/service/(configmap) 참조 + 공통 labels

**`apps/frontend/overlays/{dev,staging,prod}/kustomization.yaml`**
- `resources: [../../base]`, `namespace: synapse-<env>`
- replicas 패치(dev 1), `images:` ghcr → `963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/frontend`, newTag는 image-updater가 갱신
- staging/prod도 동일 형태로 생성하되 namespace/replicas만 차이 (dormant)

**`argocd/applicationset.yaml`**
- `list.elements`에 `- service: frontend` 추가. (env 리스트는 변경 없음 → dev만 실제 생성)
- image-updater 어노테이션은 `{{service}}` 치환으로 frontend에도 자동 적용 (ECR `synapse/frontend`, write-branch `image-updater-frontend`).

**`local-k8s/apps/frontend/kustomization.yaml`**
- `resources: [../../../apps/frontend/base]`
- `images:` `ghcr.io/team-project-final/synapse-frontend → synapse-frontend`, newTag `local`
- (base에 ExternalSecret 없으므로 delete 패치 불필요)

**`local-k8s/kustomization.yaml`**
- `resources`에 `apps/frontend` 추가

**`scripts/minikube-up.sh`**
- 형제 레포 이미지 빌드+적재 목록에 `synapse-frontend`(7번째) 추가 → `synapse-frontend:local`
- 롤아웃 대기 대상에 `deploy/frontend` 추가
- frontend는 Flutter web 빌드가 docker 멀티스테이지 내부에서 수행됨(별도 flutter 설치 불필요)

**`local-k8s/README.md`**
- 접속 안내 갱신: `port-forward svc/gateway 8080:80` 후 브라우저 `http://localhost:8080/` 로 SPA 확인 추가

### 4.3 synapse-gateway *(push 가능, push 전 확인)*

**`RoutesConfig.java`**
- `@Value("${FRONTEND_SVC_URI:http://frontend:80}") private String frontendUri;` 추가
- 최저 우선순위 catch-all 라우트 추가:
  ```java
  .route("frontend", r -> r
      .path("/**")                 // /api/** 라우트가 먼저 매칭되도록 순서/우선순위 보장
      .uri(frontendUri))
  ```
  - Spring Cloud Gateway는 정의 순서대로 평가하므로 catch-all을 **마지막**에 배치. 필요 시 `.order(Ordered.LOWEST_PRECEDENCE)` 명시.
  - 정적 자산이므로 `requestRateLimiter` 미적용.
  - SPA fallback(존재하지 않는 경로 → index.html)은 nginx가 처리. gateway는 순수 프록시.
- gateway base ConfigMap에 `FRONTEND_SVC_URI` 추가 불필요(기본값 `http://frontend:80`이 in-cluster DNS와 일치). 환경별 필요 시 overlay에서 주입.

## 5. 데이터 흐름

```
브라우저 → gateway:8080
   ├─ /api/platform/**   → platform-svc        (기존, stripPrefix(2)+rateLimit)
   ├─ /api/engagement/** → engagement-svc       (기존)
   ├─ /api/knowledge/**  → knowledge-svc        (기존)
   ├─ /api/learning/**   → learning-card-svc    (기존)
   └─ /** (그 외)        → frontend(nginx:8080) → SPA  (신규 catch-all)
SPA의 API 호출은 baseUrl='' → 동일 오리진 /api/** → gateway가 다시 백엔드로 라우팅
```

## 6. 검증 기준

- **로컬**: `minikube-up.sh` 후 `kubectl -n synapse-local port-forward svc/gateway 8080:80`
  - 브라우저 `http://localhost:8080/` → SPA 로드, 새로고침/딥링크(`/some/route`)도 200(SPA fallback)
  - `curl http://localhost:8080/api/platform/actuator/health` → 정상(기존 라우트 회귀 없음)
  - `kubectl -n synapse-local get pods` → `frontend` 1/1
- **AWS(dev)**: ArgoCD `synapse-frontend-dev` Application Synced/Healthy, gateway 경유 SPA 접근
- **Gateway**: `GatewaySecurityIntegrationTest` 등에 catch-all 라우트(비-/api 경로 → frontend) 케이스 추가, 기존 /api 라우트 회귀 없음 확인
- **Frontend 단위테스트**: `API_BASE_URL` 분기 로직 테스트 통과

## 7. 가정 / 미해결

- **ECR `synapse/frontend` 저장소 존재 가정.** 없으면 Terraform(`infra/aws/dev`)에 ECR 리소스 추가 또는 콘솔 생성 필요(별도 안내). 본 설계 범위에서는 매니페스트만 작성.
- ApplicationSet env 리스트는 dev 전용 → staging/prod 실제 배포는 향후 env 리스트 확장 시점에 활성화.
- frontend는 인증 토큰을 같은 오리진에서 다루므로 CORS/쿠키 도메인 이슈 없음. 단, JWT가 헤더 기반이면 SPA의 토큰 저장 전략은 기존 프론트 구현을 따른다(본 설계 범위 밖).
