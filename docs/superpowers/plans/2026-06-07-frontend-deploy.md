# Frontend 배포 통합 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** synapse-frontend(Flutter web)를 nginx 정적 컨테이너로 빌드해 로컬/AWS k8s에 배포하고, gateway가 SPA를 단일 진입점으로 catch-all 서빙하도록 한다.

**Architecture:** Flutter web 빌드(`--dart-define=API_BASE_URL=` 빈 값 = 동일 오리진)를 `nginxinc/nginx-unprivileged`로 서빙(SPA fallback). gateway는 `/api/**`를 기존 백엔드로, 그 외 `/**`를 frontend 서비스로 프록시하며 SecurityConfig는 `/api/**`만 인증·나머지 공개로 조정한다. gitops는 `apps/frontend`(base+overlays)와 `local-k8s/apps/frontend`를 추가하고 ApplicationSet·minikube-up.sh에 등록한다.

**Tech Stack:** Flutter 3.x / Dart, nginx, Docker(멀티스테이지), Spring Cloud Gateway(WebFlux, Spring Boot 4), Kustomize, ArgoCD ApplicationSet, minikube.

**Spec:** `docs/superpowers/specs/2026-06-07-frontend-deploy-design.md`

**푸시 정책 (사용자 지정):**
- synapse-gitops / synapse-gateway: 직접 push 가능. **단, 각 push 직전 사용자 확인 필수.**
- synapse-frontend(그 외 전부): **별도 브랜치 + 커밋 + push + PR만. main 직접 push 금지.** push/PR 직전 사용자 확인.

---

## Phase A — synapse-frontend *(branch + PR only)*

> 작업 디렉터리: `D:\workspace\final-project-syn\synapse-frontend`
> 시작 전: `git checkout -b feat/web-docker-nginx main` (또는 최신 기본 브랜치 기준)

### Task 1: API base URL 결정 함수 (TDD)

**Files:**
- Modify: `lib/core/network/app_environment.dart`
- Test: `test/core/network/app_environment_test.dart` (Create)

- [ ] **Step 1: 실패 테스트 작성**

Create `test/core/network/app_environment_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:synapse_frontend/core/network/app_environment.dart';

void main() {
  group('resolveApiBaseUrl', () {
    test('override 없으면 환경 기본 baseUrl로 폴백', () {
      expect(resolveApiBaseUrl(AppEnvironment.dev), 'http://localhost:8080');
      expect(resolveApiBaseUrl(AppEnvironment.staging),
          'https://api-staging.synapse.app');
      expect(resolveApiBaseUrl(AppEnvironment.prod), 'https://api.synapse.app');
    });

    test('빈 문자열 override = 동일 오리진 상대경로', () {
      expect(resolveApiBaseUrl(AppEnvironment.prod, apiBaseOverride: ''), '');
    });

    test('비어있지 않은 override가 환경 기본값보다 우선', () {
      expect(
        resolveApiBaseUrl(AppEnvironment.dev,
            apiBaseOverride: 'https://custom.example'),
        'https://custom.example',
      );
    });
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/core/network/app_environment_test.dart`
Expected: FAIL — `The function 'resolveApiBaseUrl' isn't defined`

- [ ] **Step 3: 최소 구현**

Replace `lib/core/network/app_environment.dart` 전체:

```dart
enum AppEnvironment { dev, staging, prod }

extension AppEnvironmentBaseUrl on AppEnvironment {
  String get baseUrl {
    return switch (this) {
      AppEnvironment.dev => 'http://localhost:8080',
      AppEnvironment.staging => 'https://api-staging.synapse.app',
      AppEnvironment.prod => 'https://api.synapse.app',
    };
  }
}

/// 효과적인 API base URL을 결정한다.
///
/// [apiBaseOverride]가 null이 아니면 우선 적용한다. 빈 문자열('')은
/// "동일 오리진 상대경로"를 의미하며, gateway가 SPA와 /api를 같은 오리진에서
/// 서빙할 때 사용한다(빌드 시 --dart-define=API_BASE_URL=). null이면 환경 기본값.
String resolveApiBaseUrl(AppEnvironment env, {String? apiBaseOverride}) {
  return apiBaseOverride ?? env.baseUrl;
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `flutter test test/core/network/app_environment_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: 커밋**

```bash
git add lib/core/network/app_environment.dart test/core/network/app_environment_test.dart
git commit -m "feat(network): add resolveApiBaseUrl with same-origin override"
```

---

### Task 2: dio_client에 override 배선

**Files:**
- Modify: `lib/core/network/dio_client.dart`

- [ ] **Step 1: dio_client에서 override 사용**

Replace `lib/core/network/dio_client.dart` 의 `dioProvider`:

```dart
final dioProvider = Provider<Dio>((ref) {
  final environment = ref.watch(environmentProvider);
  // 빌드 시 --dart-define=API_BASE_URL=<값> 제공 시 override 적용.
  // 값이 빈 문자열이면 동일 오리진 상대경로(gateway 단일 진입점 서빙).
  const hasOverride = bool.hasEnvironment('API_BASE_URL');
  const override = String.fromEnvironment('API_BASE_URL');
  final baseUrl = resolveApiBaseUrl(
    environment,
    apiBaseOverride: hasOverride ? override : null,
  );
  return Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );
});
```

(파일 상단 `import 'package:synapse_frontend/core/network/app_environment.dart';` 는 이미 존재 — `resolveApiBaseUrl` 동일 파일에서 export됨.)

- [ ] **Step 2: 전체 테스트로 회귀 확인**

Run: `flutter test`
Expected: PASS (기존 테스트 + 신규 3건). 실패 시 analyzer 오류 우선 수정.

Run: `flutter analyze`
Expected: No issues found.

- [ ] **Step 3: 커밋**

```bash
git add lib/core/network/dio_client.dart
git commit -m "feat(network): wire API_BASE_URL override into dio base url"
```

---

### Task 3: nginx 설정 (SPA fallback)

**Files:**
- Create: `nginx.conf`

- [ ] **Step 1: nginx.conf 작성**

Create `nginx.conf` (레포 루트):

```nginx
# Flutter web SPA 정적 서빙 (nginx-unprivileged, listen 8080, uid 101)
server {
    listen       8080;
    server_name  _;
    root         /usr/share/nginx/html;
    index        index.html;

    gzip              on;
    gzip_types        text/plain text/css application/javascript application/json image/svg+xml application/wasm;
    gzip_min_length   1024;

    # 헬스체크 — index.html 비의존, k8s 프로브용
    location = /healthz {
        access_log off;
        add_header Content-Type text/plain;
        return 200 "ok\n";
    }

    # 갱신이 잦은 부트스트랩/서비스워커/버전 메타는 no-cache
    location = /flutter_service_worker.js { add_header Cache-Control "no-cache"; try_files $uri =404; }
    location = /flutter_bootstrap.js     { add_header Cache-Control "no-cache"; try_files $uri =404; }
    location = /version.json             { add_header Cache-Control "no-cache"; try_files $uri =404; }

    # 해시 파일명 정적 자산 — 장기 캐시
    location ~* \.(?:js|css|png|jpg|jpeg|gif|ico|svg|woff2?|ttf|wasm)$ {
        try_files $uri =404;
        expires 7d;
        add_header Cache-Control "public, max-age=604800";
    }

    # SPA fallback — 존재하지 않는 경로(딥링크)는 index.html로
    location / {
        try_files $uri $uri/ /index.html;
        add_header Cache-Control "no-cache";
    }
}
```

- [ ] **Step 2: 커밋**

```bash
git add nginx.conf
git commit -m "feat(web): add nginx SPA config (fallback + cache headers)"
```

---

### Task 4: Dockerfile + .dockerignore

**Files:**
- Create: `Dockerfile`
- Create: `.dockerignore`

- [ ] **Step 1: .dockerignore 작성**

Create `.dockerignore`:

```
.git
.github
.dart_tool
build
ios
android
.idea
.vscode
*.iml
.omc
test
coverage
```

- [ ] **Step 2: Dockerfile 작성**

Create `Dockerfile`:

```dockerfile
# syntax=docker/dockerfile:1

# --- Stage 1: Flutter web 빌드 ---
# 태그는 pubspec sdk(>=3.11.0)를 만족하는 stable 사용. 재현성 위해 후속에 버전 핀 권장.
FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app

# 의존성 캐시 레이어 (소스 변경과 분리)
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# 소스 복사 후 웹 빌드. API_BASE_URL 빈 값 = 동일 오리진 상대경로.
COPY . .
ARG API_BASE_URL=""
ARG APP_ENV="prod"
RUN flutter build web --release \
      --dart-define=API_BASE_URL=${API_BASE_URL} \
      --dart-define=APP_ENV=${APP_ENV}

# --- Stage 2: nginx 정적 서빙 (non-root) ---
FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime
COPY --chown=nginx:nginx nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build --chown=nginx:nginx /app/build/web /usr/share/nginx/html
EXPOSE 8080
# 베이스 이미지 기본 entrypoint(nginx) 사용 — uid 101, listen 8080.
```

- [ ] **Step 3: 커밋**

```bash
git add Dockerfile .dockerignore
git commit -m "feat(web): containerize Flutter web with nginx-unprivileged"
```

---

### Task 5: 이미지 빌드·실행 검증 + push + PR

**Files:** 없음 (검증/배포 단계)

- [ ] **Step 1: docker 이미지 빌드**

Run: `docker build -t synapse-frontend:local .`
Expected: 빌드 성공, 최종 stage `runtime` 까지 완료. (flutter SDK 다운로드로 수 분 소요 가능)

- [ ] **Step 2: 컨테이너 실행 + SPA 응답 확인**

Run:
```bash
docker run -d --rm -p 8088:8080 --name synfe synapse-frontend:local
```
그 다음(컨테이너 기동 ~2초 후):
```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8088/healthz   # 기대: 200
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8088/          # 기대: 200
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8088/some/deep/link  # 기대: 200 (SPA fallback)
curl -s http://localhost:8088/ | grep -i "<title>"                       # 기대: <title>Synapse</title> 포함
```
정리: `docker stop synfe`
Expected: healthz·/ ·딥링크 모두 200, index.html(title=Synapse) 반환.

- [ ] **Step 2.5: 비루트 실행 확인**

Run: `docker run --rm synapse-frontend:local id`
Expected: `uid=101(nginx) gid=101(nginx)` (또는 nginx 그룹) — 비루트 확인.

- [ ] **Step 3: 브랜치 push (⚠ 사용자 확인 후)**

> **STOP — 사용자 확인 필수.** synapse-frontend는 PR-only 레포다. push/PR 전 사용자에게 확인받는다.

Run:
```bash
git push -u origin feat/web-docker-nginx
```

- [ ] **Step 4: PR 생성**

Run:
```bash
gh pr create --title "feat(web): Dockerize Flutter web for k8s deploy" \
  --body "Flutter web → nginx-unprivileged 정적 서빙. API_BASE_URL override로 동일 오리진(/api) 호출. gitops/gateway 연계 배포(스펙: synapse-gitops/docs/superpowers/specs/2026-06-07-frontend-deploy-design.md).

- Dockerfile(멀티스테이지) + nginx.conf(SPA fallback) + .dockerignore
- resolveApiBaseUrl + dio_client 배선 (--dart-define=API_BASE_URL=)

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```
Expected: PR URL 출력. **이 PR 번호를 기록** (gitops/gateway 작업에서 참조).

---

## Phase B — synapse-gateway *(push 가능, push 전 확인)*

> 작업 디렉터리: `D:\workspace\final-project-syn\synapse-gateway`
> 시작 전: `git checkout -b feat/frontend-catchall-route main`

### Task 6: gateway 라우팅/보안 통합테스트 추가 (TDD — 실패 먼저)

**Files:**
- Modify: `src/test/java/com/synapse/gateway/security/GatewaySecurityIntegrationTest.java`

- [ ] **Step 1: FRONTEND_SVC_URI 고정 + SPA 공개·라우팅 테스트 추가**

`GatewaySecurityIntegrationTest.java` 의 `properties(...)` `@DynamicPropertySource` 에 한 줄 추가:

```java
        // 프론트 업스트림도 즉시 연결거부 주소로 고정 (인증 통과 후 라우팅 시도 → 5xx).
        registry.add("FRONTEND_SVC_URI", () -> "http://localhost:1");
```

그리고 클래스 끝에 테스트 3개 추가:

```java
    @Test
    void spaRootIsPublicAndRoutedToFrontend() {
        // "/" 는 공개(permitAll) → 인증 통과 후 dead 업스트림으로 라우팅 → 5xx (401 아님).
        client.get().uri("/")
                .exchange()
                .expectStatus().is5xxServerError();
    }

    @Test
    void spaDeepLinkIsPublic() {
        // go_router 딥링크 새로고침 경로도 공개여야 SPA 로드 가능.
        client.get().uri("/dashboard/notes/42")
                .exchange()
                .expectStatus().is5xxServerError();
    }

    @Test
    void staticAssetPathIsPublic() {
        client.get().uri("/flutter_bootstrap.js")
                .exchange()
                .expectStatus().is5xxServerError();
    }
```

- [ ] **Step 2: 실패 확인**

Run: `./gradlew test --tests "com.synapse.gateway.security.GatewaySecurityIntegrationTest"`
Expected: 신규 3건 FAIL — 현재 `anyExchange().authenticated()` 라 "/"·딥링크·정적자산이 **401**(5xx 아님). 기존 6건은 PASS.

---

### Task 7: SecurityConfig — /api만 인증, 나머지 공개

**Files:**
- Modify: `src/main/java/com/synapse/gateway/config/SecurityConfig.java:34-37`

- [ ] **Step 1: authorizeExchange 규칙 조정**

`SecurityConfig.java` 의 `.authorizeExchange(...)` 블록을 다음으로 교체:

```java
                .authorizeExchange(exchange -> exchange
                        .pathMatchers(HttpMethod.OPTIONS, "/**").permitAll()
                        // 공개 경로(actuator·auth 엔드포인트 등)는 /api/** 인증 규칙보다 먼저 매칭.
                        .pathMatchers(publicPaths).permitAll()
                        // API는 인증 필수 (공개 경로 제외).
                        .pathMatchers("/api/**").authenticated()
                        // 그 외(SPA 셸·정적 자산·딥링크)는 공개 — gateway가 frontend로 프록시.
                        .anyExchange().permitAll())
```

(주석: 정적 SPA 번들에는 비밀이 없고, 민감 데이터는 모두 `/api/**`(인증 유지)로 흐른다.)

- [ ] **Step 2: 보안 테스트 재실행**

Run: `./gradlew test --tests "com.synapse.gateway.security.GatewaySecurityIntegrationTest"`
Expected: `protectedRouteWithoutTokenReturnsUnauthorized` 등 /api 인증 테스트 PASS, `publicHealthEndpointIsAccessible` PASS. 신규 SPA 3건은 여전히 FAIL일 수 있음 — **frontend 라우트가 아직 없어** "/" 가 라우팅되지 않고 404(시큐리티는 통과하나 매칭 라우트 없음). 다음 태스크에서 라우트 추가로 5xx 달성.

> 참고: 라우트가 없으면 "/" 는 인증 통과 후 "no route" → Spring 기본 404. 5xx 단언은 Task 8에서 충족.

---

### Task 8: RoutesConfig — frontend catch-all 라우트

**Files:**
- Modify: `src/main/java/com/synapse/gateway/config/RoutesConfig.java`

- [ ] **Step 1: frontend URI 주입 + catch-all 라우트 추가**

`RoutesConfig.java` 의 필드부에 추가 (다른 `@Value` 옆):

```java
    @Value("${FRONTEND_SVC_URI:http://frontend:80}")
    private String frontendUri;
```

상단 import 추가:

```java
import org.springframework.core.Ordered;
```

`customRouteLocator(...)` 의 `.build()` 직전, learning-svc 라우트 뒤에 catch-all 추가:

```java
            // catch-all: /api/** 외 모든 경로 → frontend(nginx) SPA.
            // LOWEST_PRECEDENCE 로 /api 라우트(기본 order 0)보다 항상 나중에 매칭.
            // rate-limit 미적용(정적 자산). SPA fallback은 nginx가 처리.
            .route("frontend", r -> r
                .order(Ordered.LOWEST_PRECEDENCE)
                .path("/**")
                .uri(frontendUri))
```

- [ ] **Step 2: 전체 gateway 테스트 통과 확인**

Run: `./gradlew test`
Expected: PASS — SPA 3건(5xx), /api 인증 4건, public/actuator 모두 통과. `publicHealthEndpointIsAccessible`(actuator 200)가 catch-all에 가로채이지 않음을 확인(actuator 핸들러 매핑이 gateway 라우트보다 우선).

> 만약 `/actuator/health` 가 5xx로 깨지면: actuator 핸들러 매핑 우선순위 문제 → frontend 라우트 predicate를 `/**` 유지하되 catch-all order가 LOWEST인지 재확인. 그래도 깨지면 `management.endpoints.web.base-path` 가 라우트와 겹치지 않는지 점검.

- [ ] **Step 3: 커밋**

```bash
git add src/main/java/com/synapse/gateway/config/SecurityConfig.java \
        src/main/java/com/synapse/gateway/config/RoutesConfig.java \
        src/test/java/com/synapse/gateway/security/GatewaySecurityIntegrationTest.java
git commit -m "feat(gateway): catch-all route to frontend + open non-/api paths"
```

- [ ] **Step 4: push (⚠ 사용자 확인 후)**

> **STOP — push 전 사용자 확인.** (메모리 규칙: svc 레포 변경 사전확인)

Run: `git push -u origin feat/frontend-catchall-route`
그 다음 PR 생성 또는 직접 머지 여부는 사용자 지시에 따른다.

---

## Phase C — synapse-gitops AWS 매니페스트 *(push 가능, push 전 확인)*

> 작업 디렉터리: `D:\workspace\final-project-syn\synapse-gitops`
> 브랜치: `feat/frontend-deploy` (이미 존재 — spec 커밋됨)

### Task 9: apps/frontend/base

**Files:**
- Create: `apps/frontend/base/deployment.yaml`
- Create: `apps/frontend/base/service.yaml`
- Create: `apps/frontend/base/kustomization.yaml`

- [ ] **Step 1: deployment.yaml**

Create `apps/frontend/base/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  labels:
    app.kubernetes.io/name: frontend
    app.kubernetes.io/part-of: synapse
spec:
  replicas: 1
  minReadySeconds: 5
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: frontend
  template:
    metadata:
      labels:
        app.kubernetes.io/name: frontend
        app.kubernetes.io/part-of: synapse
    spec:
      terminationGracePeriodSeconds: 15
      containers:
        - name: frontend
          image: ghcr.io/team-project-final/synapse-frontend:latest
          ports:
            - containerPort: 8080
          startupProbe:
            httpGet:
              path: /healthz
              port: 8080
            periodSeconds: 3
            failureThreshold: 10
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 3
            periodSeconds: 5
          resources:
            requests:
              cpu: 25m
              memory: 32Mi
            limits:
              cpu: 200m
              memory: 128Mi
          securityContext:
            runAsNonRoot: true
            runAsUser: 101
            runAsGroup: 101
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            seccompProfile:
              type: RuntimeDefault
```

- [ ] **Step 2: service.yaml**

Create `apps/frontend/base/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend
  labels:
    app.kubernetes.io/name: frontend
    app.kubernetes.io/part-of: synapse
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
      name: http
  selector:
    app.kubernetes.io/name: frontend
```

- [ ] **Step 3: kustomization.yaml**

Create `apps/frontend/base/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml

labels:
  - pairs:
      app.kubernetes.io/managed-by: kustomize
    includeSelectors: true
```

- [ ] **Step 4: base 빌드 검증**

Run: `kubectl kustomize apps/frontend/base`
Expected: Deployment + Service 렌더링 성공, 오류 없음. `image: ghcr.io/team-project-final/synapse-frontend:latest`, Service port 80→8080 확인.

---

### Task 10: apps/frontend/overlays/{dev,staging,prod}

**Files:**
- Create: `apps/frontend/overlays/dev/kustomization.yaml`
- Create: `apps/frontend/overlays/staging/kustomization.yaml`
- Create: `apps/frontend/overlays/prod/kustomization.yaml`

- [ ] **Step 1: dev overlay**

Create `apps/frontend/overlays/dev/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namespace: synapse-dev
patches:
  - target:
      kind: Deployment
      name: frontend
    patch: |
      - op: replace
        path: /spec/replicas
        value: 1
images:
  - name: ghcr.io/team-project-final/synapse-frontend
    newName: 963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/frontend
    newTag: latest
```

- [ ] **Step 2: staging overlay** (dormant — ApplicationSet env=dev만 생성)

Create `apps/frontend/overlays/staging/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namespace: synapse-staging
patches:
  - target:
      kind: Deployment
      name: frontend
    patch: |
      - op: replace
        path: /spec/replicas
        value: 2
images:
  - name: ghcr.io/team-project-final/synapse-frontend
    newName: 963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/frontend
    newTag: latest
```

- [ ] **Step 3: prod overlay** (dormant)

Create `apps/frontend/overlays/prod/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namespace: synapse-prod
patches:
  - target:
      kind: Deployment
      name: frontend
    patch: |
      - op: replace
        path: /spec/replicas
        value: 2
images:
  - name: ghcr.io/team-project-final/synapse-frontend
    newName: 963773969059.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/frontend
    newTag: latest
```

- [ ] **Step 4: overlay 빌드 검증**

Run:
```bash
kubectl kustomize apps/frontend/overlays/dev
kubectl kustomize apps/frontend/overlays/staging
kubectl kustomize apps/frontend/overlays/prod
```
Expected: 3개 모두 성공. 각 namespace(synapse-dev/staging/prod)·ECR 이미지로 치환 확인.

---

### Task 11: ApplicationSet에 frontend 등록

**Files:**
- Modify: `argocd/applicationset.yaml`

- [ ] **Step 1: service 리스트에 frontend 추가**

`argocd/applicationset.yaml` 의 `list.elements` (services) 에 마지막 항목으로 추가:

```yaml
                - service: gateway
                - service: frontend
```

(env 리스트는 변경하지 않음 — 현재 `dev`만 생성됨. staging/prod overlay는 dormant.)

- [ ] **Step 2: YAML 유효성 확인**

Run: `kubectl kustomize argocd 2>/dev/null || python -c "import yaml,sys; list(yaml.safe_load_all(open('argocd/applicationset.yaml'))); print('ok')"`
Expected: `ok` (또는 kustomize 출력). 파싱 오류 없음.

> 참고: image-updater 어노테이션은 `{{service}}` 치환으로 frontend에도 자동 적용 → ECR `synapse/frontend`, write-branch `image-updater-frontend`. allow-tags 정규식이 semver(`^\d+\.\d+\.\d+$`)이므로, frontend CI가 semver 태그를 ECR에 publish해야 자동 갱신됨(별도 작업, 본 계획 범위 밖 — 부트스트랩은 `latest` 태그로 sync).

---

## Phase D — synapse-gitops 로컬(minikube) *(push 가능, push 전 확인)*

### Task 12: local-k8s/apps/frontend + 루트 kustomization

**Files:**
- Create: `local-k8s/apps/frontend/kustomization.yaml`
- Modify: `local-k8s/kustomization.yaml`

- [ ] **Step 1: 로컬 frontend overlay**

Create `local-k8s/apps/frontend/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../apps/frontend/base
images:
  - name: ghcr.io/team-project-final/synapse-frontend
    newName: synapse-frontend
    newTag: local
```

(base에 ExternalSecret이 없어 delete 패치 불필요. namespace는 루트 kustomization의 `synapse-local` 적용.)

- [ ] **Step 2: 루트 kustomization에 추가**

`local-k8s/kustomization.yaml` 의 `resources` 에 `apps/frontend` 추가 (gateway 뒤):

```yaml
  - apps/gateway
  - apps/frontend
  - apps/platform-svc
```

- [ ] **Step 3: 로컬 빌드 검증**

Run: `kubectl kustomize local-k8s`
Expected: 성공. frontend Deployment/Service 가 `namespace: synapse-local`, `image: synapse-frontend:local` 로 렌더링.

---

### Task 13: minikube-up.sh + README 갱신

**Files:**
- Modify: `scripts/minikube-up.sh`
- Modify: `local-k8s/README.md`

- [ ] **Step 1: 이미지 빌드 목록에 frontend 추가**

`scripts/minikube-up.sh` 의 `build_docker ... gateway` 줄 **뒤**에 추가 (line 19 부근):

```bash
build_docker synapse-frontend       "$SIB/synapse-frontend"
```

- [ ] **Step 2: 롤아웃 대기 루프에 frontend 추가**

`scripts/minikube-up.sh` 의 롤아웃 루프(line 51)를 수정:

```bash
for d in platform-svc engagement-svc knowledge-svc learning-card learning-ai gateway frontend; do
  kubectl -n synapse-local rollout status "deploy/$d" --timeout=300s || true
done
```

- [ ] **Step 3: 완료 안내(here-doc)에 SPA 접속 추가**

`scripts/minikube-up.sh` 의 종료 `cat <<'EOF' ... EOF` 안내에 한 줄 추가 (gateway port-forward 설명 뒤):

```
  # 브라우저로 SPA: http://localhost:8080/  (gateway가 /api 외 경로를 frontend로 서빙)
```

- [ ] **Step 4: README 접속 안내 갱신**

`local-k8s/README.md` 의 접속 섹션(gateway port-forward 설명 부근)에 추가:

```markdown
- 브라우저로 SPA 접속: `http://localhost:8080/` — gateway가 `/api/**` 외 경로를 `frontend`(nginx)로 프록시. 딥링크/새로고침은 nginx SPA fallback으로 `index.html` 반환.
```

- [ ] **Step 5: 스크립트 문법 확인**

Run: `bash -n scripts/minikube-up.sh`
Expected: 출력 없음(문법 오류 없음).

- [ ] **Step 6: 커밋**

```bash
git add apps/frontend local-k8s/apps/frontend local-k8s/kustomization.yaml \
        argocd/applicationset.yaml scripts/minikube-up.sh local-k8s/README.md
git commit -m "feat(frontend): add k8s manifests (base+overlays), ApplicationSet, local-k8s wiring"
```

- [ ] **Step 7: push (⚠ 사용자 확인 후)**

> **STOP — push 전 사용자 확인.**

Run: `git push -u origin feat/frontend-deploy`

---

## Phase E — 로컬 E2E 검증 (선택, 권장)

> 전제: minikube 사용 가능, 형제 레포 `../synapse-frontend` 가 **Phase A 브랜치(feat/web-docker-nginx)** 로 체크아웃, `../synapse-gateway` 가 **Phase B 브랜치** 로 체크아웃 되어 있어야 함(로컬 빌드가 sibling 워킹카피의 Dockerfile/소스를 사용).

### Task 14: minikube e2e

- [ ] **Step 1: 클린 재기동**

Run:
```bash
kubectl delete ns synapse-local --ignore-not-found
bash scripts/minikube-up.sh
```
Expected: frontend 포함 전 워크로드 빌드+적재+적용. `frontend` 롤아웃 성공.

- [ ] **Step 2: 파드 상태 확인**

Run: `kubectl -n synapse-local get pods`
Expected: `frontend-*` `1/1 Running`. (learning-ai는 OpenAI 키 없으면 CrashLoop 정상)

- [ ] **Step 3: gateway 경유 SPA + API 동시 확인**

별도 터미널: `kubectl -n synapse-local port-forward svc/gateway 8080:80`
그 다음:
```bash
curl -s -o /dev/null -w "SPA / -> %{http_code}\n"        http://localhost:8080/
curl -s -o /dev/null -w "deeplink -> %{http_code}\n"     http://localhost:8080/dashboard
curl -s -o /dev/null -w "asset -> %{http_code}\n"        http://localhost:8080/flutter_bootstrap.js
curl -s -o /dev/null -w "api health -> %{http_code}\n"   http://localhost:8080/api/platform/actuator/health
curl -s http://localhost:8080/ | grep -i "<title>"
```
Expected:
- SPA `/` → 200, 딥링크 → 200, asset → 200, `<title>Synapse</title>` 반환
- `/api/platform/actuator/health` → 200 (기존 백엔드 라우팅 회귀 없음)

- [ ] **Step 4: 결과 기록**

검증 결과를 PR/이슈에 기록. 실패 시 `kubectl -n synapse-local logs deploy/frontend` 및 gateway 로그로 디버깅(systematic-debugging 스킬).

---

## Self-Review (작성자 점검 완료)

**Spec coverage:**
- (a) nginx 정적 서빙 → Task 3,4 (nginx.conf, Dockerfile), Task 9 (Deployment) ✅
- (b) gateway catch-all → Task 8 ✅, SecurityConfig 공개화 → Task 7 ✅
- AWS dev/staging/prod overlays → Task 10 ✅, ApplicationSet → Task 11 ✅
- 로컬 k8s → Task 12, minikube-up.sh → Task 13 ✅
- 동일 오리진 baseUrl → Task 1,2 ✅
- ECR synapse/frontend → Task 10 (image), image-updater note → Task 11 ✅
- 푸시 정책(frontend PR-only, gitops/gateway 확인 후 push) → Task 5,8,13 STOP 게이트 ✅

**Placeholder scan:** Dockerfile flutter 태그 `stable`(버전 핀은 권장 주석으로 명시), overlay newTag `latest`(image-updater가 관리, note 명시) — 의도된 값. 그 외 TBD/TODO 없음 ✅

**Type/이름 일관성:** `resolveApiBaseUrl`(Task1 정의 ↔ Task2 사용) 일치. Service명 `frontend`(Task9) ↔ gateway 기본 `http://frontend:80`(Task8) ↔ 로컬 이미지 `synapse-frontend:local`(Task12,13) 일치. 프로브 경로 `/healthz`(nginx.conf Task3 ↔ deployment Task9) 일치. containerPort 8080 ↔ targetPort 8080 ↔ nginx listen 8080 일치 ✅

**미해결(스펙 명시):** ECR `synapse/frontend` 저장소 존재 가정 — 없으면 dev 파드 ImagePullBackOff. frontend CI의 ECR semver publish는 본 계획 범위 밖(부트스트랩은 latest 태그로 sync).
