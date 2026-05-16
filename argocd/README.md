# argocd/

ArgoCD 부트스트랩 매니페스트와 ApplicationSet 정의.

## 디렉토리

```
argocd/
├── projects.yaml              # AppProject: synapse (synapse-* namespace 한정)
├── applicationset.yaml        # ApplicationSet: synapse-apps (matrix 5svc × env)
└── bootstrap/
    ├── rbac-cm.yaml           # ArgoCD RBAC (admin / readonly)
    └── notifications-cm.yaml  # 알림 plate (W3에 채움)
```

## ApplicationSet 구조

`synapse-apps`는 **matrix generator** 패턴:
- 첫 번째 list: 5개 서비스 (`platform-svc`, `engagement-svc`, `knowledge-svc`, `learning-card`, `learning-ai`)
- 두 번째 list: 환경 (W1은 `[dev]`만, W3에 `staging`, W4에 `prod` 추가)
- 결과: `5 × N환경` Application 생성, 이름 규칙 `synapse-<svc>-<env>`

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

## RBAC

`bootstrap/rbac-cm.yaml`에 2개 role 정의:
- `role:admin` — 전체 권한 (admin 계정 기본 매핑)
- `role:readonly` — get만 (default policy)

W2 SSO 연동 후 `dev` 그룹 추가 예정.

## 트러블슈팅

### Application이 OutOfSync로 표시됨
정상. W1은 base manifest가 비어있어 Application은 등록되지만 워크로드는 W2에서 채워짐.

### sync 거부됨 (permission denied)
RBAC 확인:
```bash
kubectl get cm argocd-rbac-cm -n argocd -o yaml
argocd account can-i sync applications "synapse-platform-svc-dev"
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
