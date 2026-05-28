# argocd/

ArgoCD 부트스트랩 매니페스트와 ApplicationSet 정의.

## 디렉토리

```
argocd/
├── projects.yaml              # AppProject: synapse (synapse-* ns) + synapse-prod (synapse-prod ns, restricted)
├── applicationset.yaml        # ApplicationSet: synapse-apps (matrix 5svc × env)
├── applicationset-staging.yaml # ApplicationSet: synapse-apps-staging (auto-sync)
├── applicationset-prod.yaml   # ApplicationSet: synapse-apps-prod (manual sync, image-updater 없음)
└── bootstrap/
    ├── rbac-cm.yaml           # ArgoCD RBAC (admin / readonly / prod-deployer)
    ├── argocd-cm.yaml         # 로컬 계정 gitops-admin (prod 수동 sync 전용)
    └── notifications-cm.yaml  # 알림 plate (W3에 채움)
```

## ApplicationSet 구조

`synapse-apps`는 **matrix generator** 패턴:
- 첫 번째 list: 5개 서비스 (`platform-svc`, `engagement-svc`, `knowledge-svc`, `learning-card`, `learning-ai`)
- 두 번째 list: 환경 (W1은 `[dev]`만, W3에 `staging`, W4에 `prod` 추가)
- 결과: `5 × N환경` Application 생성, 이름 규칙 `synapse-<svc>-<env>`

staging/prod는 sync 정책이 달라 **별도 파일**(`applicationset-staging.yaml`, `applicationset-prod.yaml`)로 분리한다.

## 새 앱 추가 절차

1. `apps/<new-svc>/{base,overlays/dev}` 디렉토리 생성
2. `apps/<new-svc>/base/{kustomization.yaml,deployment.yaml,service.yaml}` 작성
3. `apps/<new-svc>/overlays/dev/kustomization.yaml` 작성
4. `argocd/applicationset.yaml`의 첫 번째 list에 `- service: <new-svc>` 한 줄 추가
5. PR 생성 → CI 통과 → 머지
6. ArgoCD가 3분 이내 polling으로 자동 인식

## 환경 추가 (W3, W4)

1. `argocd/applicationset.yaml`의 두 번째 list에 `- env: staging` (또는 `prod`) 추가
2. 모든 앱의 `apps/<svc>/overlays/<env>/kustomization.yaml` 작성
3. auto-sync 분기가 필요하면 `spec.template`에 `templatePatch` 재도입:
   ```yaml
   templatePatch: |
     {{- if ne .env "dev" }}
     spec:
       syncPolicy:
         automated: null
     {{- end }}
   ```

## prod 환경 (W4)

prod는 거버넌스(수동 승인 + 권한 분리)를 증명하는 환경이라 dev/staging과 다음이 다르다.

- **별도 ApplicationSet** `applicationset-prod.yaml` — list generator 5개. `syncPolicy.automated` **없음** → main 머지 후 OutOfSync 대기(수동 sync 게이트, FR-GO-402). `project: synapse-prod`.
- **별도 AppProject** `synapse-prod`(projects.yaml) — destination `synapse-prod` ns 한정. RBAC 리소스 포맷이 `<project>/<app>`이라, `role:prod-deployer`의 `synapse-prod/*` glob이 prod 앱만 겨냥하려면 이 프로젝트 분리가 전제.
- **image-updater 어노테이션 없음** — prod 이미지 승격은 overlay `images[].newTag`를 바꾸는 **명시적 PR**. 자동 bump 안 함.
- **데이터 논리 분리** — 공유 dev 데이터스토어 + DB명 `synapse_prod` / Redis index 1(platform-svc) / 시크릿 경로 `synapse/prod/{app}/*`. Kafka 토픽·OpenSearch 인덱스 공유는 캡스톤 한계.
- **적용**: staging/prod ApplicationSet은 W1 bootstrap 스크립트가 적용하지 않는다. `kubectl apply -f argocd/applicationset-prod.yaml` 로 라이브 시 직접 적용.

## RBAC

`bootstrap/rbac-cm.yaml`에 role 정의:
- `role:admin` — 전체 권한 (admin 계정 기본 매핑)
- `role:readonly` — get만 (`policy.default`)
- `role:prod-deployer` — `synapse-prod/*` 앱 **sync만** 허용 + 전체 get. `gitops-admin` 계정에 매핑.

`policy.default: role:readonly` 라서 권한 없는 계정의 prod sync는 거부된다(FR-GO-403). `gitops-admin` 로컬 계정은 `bootstrap/argocd-cm.yaml`(`accounts.gitops-admin: apiKey, login`)에 정의하고, 설치 후 `argocd account update-password --account gitops-admin` 로 비밀번호를 설정한다(시크릿 미커밋).

> ⚠️ `argocd-cm.yaml`은 bootstrap 적용 시 ArgoCD 설치본의 기존 argocd-cm을 덮어쓰지 않도록 최초 적용 후 기존 data 키 보존을 확인할 것(파일 주석 참조).

W2 SSO 연동 후 `dev` 그룹 추가 예정.

## 트러블슈팅

### Application이 OutOfSync로 표시됨
- W1: base manifest가 비어있어 Application은 등록되지만 워크로드는 W2에서 채워짐.
- **prod**: 정상. prod ApplicationSet은 `automated` 없음 → 항상 수동 sync 대기. `gitops-admin` 으로 `argocd app sync synapse-<svc>-prod`.

### sync 거부됨 (permission denied)
RBAC 확인:
```bash
kubectl get cm argocd-rbac-cm -n argocd -o yaml
argocd account can-i sync applications "synapse-platform-svc-dev"
# prod: gitops-admin 계정이어야 yes
argocd account can-i sync applications "synapse-prod/synapse-platform-svc-prod"
```

### 브라우저 self-signed TLS 경고
옵션 2 정상 동작. 다음 중 하나:
- Chrome/Edge: 고급 → "안전하지 않음으로 진행"
- Safari: 상세 → "이 웹사이트 방문" (인증서 신뢰 추가)
- 영구 해결: [TLS 마이그레이션 가이드](../docs/argocd-tls-migration.md) 따라 옵션 1로 전환

### CLI 로그인 실패
```bash
NLB_HOST=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
PW=$(aws secretsmanager get-secret-value --secret-id synapse/argocd/admin \
       --query SecretString --output text | jq -r .password)
argocd login "$NLB_HOST" --username admin --password "$PW" --insecure --grpc-web
```
