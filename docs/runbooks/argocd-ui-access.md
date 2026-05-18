# Runbook: ArgoCD UI 접속 가이드

> **목적**: 로컬(kind) 또는 EKS 환경에서 ArgoCD Web UI에 접속하는 절차
> **사전 조건**: ArgoCD가 클러스터에 설치되어 있고, `kubectl`로 해당 클러스터에 접근 가능

---

## 1. kubectl context 확인

ArgoCD가 설치된 클러스터를 가리키고 있는지 확인한다.

```bash
# 현재 context 확인
kubectl config current-context

# kind 클러스터로 전환 (필요 시)
kubectl config use-context kind-synapse-w2

# EKS 클러스터로 전환 (필요 시)
kubectl config use-context arn:aws:eks:ap-northeast-2:<ACCOUNT>:cluster/synapse-dev
```

ArgoCD pod이 Running인지 확인:

```bash
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server
# Expected: 1/1 Running
```

---

## 2. admin 비밀번호 확인

ArgoCD 설치 시 자동 생성된 초기 비밀번호를 조회한다.

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo ""
```

출력된 문자열이 admin 비밀번호이다.

> **참고**: `bootstrap-argocd.sh`로 비밀번호를 회전했다면 AWS Secrets Manager에서 조회:
> ```bash
> aws secretsmanager get-secret-value --secret-id synapse/argocd/admin \
>   --region ap-northeast-2 --query SecretString --output text | jq -r .password
> ```

---

## 3. 포트포워딩 (로컬 접속)

### kind 환경

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

브라우저에서 접속:
- **URL**: `https://localhost:8080`
- **ID**: `admin`
- **PW**: 2번에서 확인한 비밀번호

> 자체 서명 인증서 경고가 나오면 "고급" → "안전하지 않음 — 계속 진행"을 클릭한다.

### 포트 충돌 시

8080이 이미 사용 중이면 다른 포트를 사용한다:

```bash
# 9090 포트 사용
kubectl port-forward svc/argocd-server -n argocd 9090:443
```

브라우저에서 `https://localhost:9090`으로 접속.

이미 떠있는 포트포워딩 프로세스를 찾아 종료하려면:

```bash
# Windows (PowerShell)
netstat -ano | findstr :8080
taskkill /PID <PID> /F

# macOS / Linux
lsof -i :8080
kill <PID>
```

### EKS 환경

EKS에서는 NLB로 외부 노출되어 있으면 포트포워딩 없이 직접 접속 가능:

```bash
# NLB 주소 확인
kubectl get svc argocd-server -n argocd \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

브라우저에서 `https://<NLB-DNS>` 접속. NLB가 없으면 kind와 동일하게 포트포워딩 사용.

---

## 4. ArgoCD CLI 로그인 (선택)

UI 외에 CLI로도 접속할 수 있다.

```bash
# kind (포트포워딩 상태에서)
argocd login localhost:8080 --username admin --password <PW> --insecure --grpc-web

# EKS (NLB)
argocd login <NLB-DNS> --username admin --password <PW> --insecure --grpc-web

# 로그인 확인
argocd account get-user-info
```

---

## 5. UI에서 확인할 수 있는 항목

| 메뉴 | 확인 내용 |
|---|---|
| Applications | 5개 앱 sync 상태 (Synced/OutOfSync), health 상태 (Healthy/Progressing/Degraded) |
| 앱 클릭 → Resource Tree | Deployment, Service, ConfigMap, ExternalSecret 등 리소스 트리 |
| 앱 클릭 → Logs | Pod 로그 실시간 확인 |
| 앱 클릭 → Diff | git 매니페스트 vs 클러스터 상태 차이 |
| 앱 클릭 → Events | sync 이벤트, 에러 이력 |
| Settings → Repositories | git 레포 연결 상태 |
| Settings → Projects | synapse 프로젝트 설정 |

---

## 6. 트러블슈팅

### 포트포워딩 즉시 종료됨

```bash
# ArgoCD server pod 상태 확인
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=20
```

pod이 Running이 아니면 ArgoCD 재설치 또는 클러스터 문제.

### 브라우저에서 연결 거부

1. 포트포워딩이 실행 중인지 확인 (터미널에 `Forwarding from ...` 출력)
2. `https://`인지 확인 (`http://`가 아님)
3. 다른 포트로 시도 (위 "포트 충돌 시" 참조)

### 로그인 실패 (401)

```bash
# 비밀번호 재확인
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo ""

# 비밀번호가 회전되었으면 초기화
kubectl -n argocd delete secret argocd-initial-admin-secret
kubectl rollout restart deployment argocd-server -n argocd
# 새 비밀번호 재조회
```

### context가 잘못 지정됨

```bash
# 사용 가능한 context 목록
kubectl config get-contexts

# kind context로 전환
kubectl config use-context kind-synapse-w2
```
