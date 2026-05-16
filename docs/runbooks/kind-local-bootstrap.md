# Runbook: kind 로컬 클러스터로 ArgoCD 부트스트랩 (B-2 path)

> **대상**: AWS 비용/제약 없이 ArgoCD HA + ApplicationSet 동작을 검증하고 싶은 작업자
> **소요 시간**: 약 30~40분 (Docker 설치 제외)
> **결과**: 로컬 Docker 위에 3노드 K8s + ArgoCD HA + 5 Application 등록
> **상위 문서**: [w1-argocd-bootstrap-runbook.md](./w1-argocd-bootstrap-runbook.md) — EKS path가 막혔을 때 대체

본 문서는 2026-05-16 W1 Task 14에서 AWS 신규 계정 Free Tier 제약으로 EKS 부트스트랩이 막혔을 때 채택한 대체 path(B-2)를 정리한다. EKS path가 가능하다면 그쪽이 PRD 검수에 더 가깝지만, kind는:
- **비용 0**, 즉시 시작/정리 가능
- ArgoCD HA + ApplicationSet matrix 동작 검증
- FR-GO-101/103/104 부분 충족
- FR-GO-102는 port-forward로 대체 (NLB는 못 만듦)
- FR-GO-105는 GitHub Ruleset으로 별도 충족

---

## 사전 점검

```powershell
# Docker
docker version 2>$null
if ($?) { Write-Host "Docker OK" } else { Write-Host "Docker MISSING" }

# kind
kind version 2>$null
if ($?) { Write-Host "kind OK" } else { Write-Host "kind MISSING" }

# kubectl
kubectl version --client 2>$null
if ($?) { Write-Host "kubectl OK" } else { Write-Host "kubectl MISSING" }

# 사용 가능 메모리 (5GB 이상 권장)
Get-CimInstance Win32_OperatingSystem | Select-Object @{N='Free GB'; E={[math]::Round($_.FreePhysicalMemory/1MB, 1)}}, @{N='Total GB'; E={[math]::Round($_.TotalVisibleMemorySize/1MB, 1)}}
```

---

## 1. Docker Desktop 설치 + 메모리 할당 (Windows)

미설치면:
1. https://www.docker.com/products/docker-desktop/ → Windows AMD64 → 설치 → 재부팅
2. Docker Desktop 실행 → **Settings → Resources**:
   - **Memory**: 6 GB 이상 (ArgoCD HA + redis-ha + redis-ha-haproxy + 5 application = 약 4 GB 필요)
   - **CPU**: 2 이상
   - **Disk image size**: 20 GB 이상
3. **Apply & Restart**

macOS / Linux는 각 OS 표준 설치.

---

## 2. kind 설치

### Windows
```powershell
winget install --id Kubernetes.kind -e
```
또는 직접 다운로드:
- https://github.com/kubernetes-sigs/kind/releases (Windows AMD64 binary)
- `C:\Tools\kind\kind.exe`로 저장 후 PATH에 추가

### macOS
```bash
brew install kind
```

### Linux
```bash
[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

**검증**: `kind version` → `kind v0.23.x` 이상

---

## 3. kubectl 설치

### Windows
```powershell
winget install --id Kubernetes.kubectl -e
```

### macOS
```bash
brew install kubectl
```

### Linux
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

**검증**: `kubectl version --client` → `Client Version: v1.x.x`

---

## 4. kind cluster 생성 (3~5분)

작업 폴더(레포 루트 아닌 곳) 생성 — kind 산출물과 레포 코드 분리:
```powershell
mkdir D:\workspace\final-project-syn\synapse-gitops\kind-local -ErrorAction SilentlyContinue
cd D:\workspace\final-project-syn\synapse-gitops\kind-local
```

### cluster config 작성

`kind-config.yaml`:
```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: synapse-dev
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30443
        hostPort: 8443
        protocol: TCP
  - role: worker
  - role: worker
```

PowerShell에서 한 번에:
```powershell
@'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: synapse-dev
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30443
        hostPort: 8443
        protocol: TCP
  - role: worker
  - role: worker
'@ | Out-File -Encoding ascii kind-config.yaml
```

### cluster 생성

```powershell
kind create cluster --config kind-config.yaml
```

**Expected** (3분 정도):
```
Creating cluster "synapse-dev" ...
 ✓ Ensuring node image ...
 ✓ Preparing nodes ...
 ✓ Writing configuration ...
 ✓ Starting control-plane ...
 ✓ Installing CNI ...
 ✓ Installing StorageClass ...
 ✓ Joining worker nodes ...
Set kubectl context to "kind-synapse-dev"
```

### 검증
```powershell
kubectl get nodes
```

3개 노드(`control-plane`, `worker`, `worker2`)가 `Ready` 상태.

---

## 5. ArgoCD HA 설치 (5~7분)

### 5-1. namespace + install

```powershell
kubectl create namespace argocd

# server-side apply 필수 — client-side는 ApplicationSet CRD annotation 크기 초과로 실패
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/ha/install.yaml
```

⚠️ **반드시 `--server-side --force-conflicts`**. 일반 `kubectl apply`는 ApplicationSet CRD가 너무 커서 `metadata.annotations: Too long: may not be more than 262144 bytes` 에러로 실패.

### 5-2. pod readiness 대기

```powershell
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=600s
kubectl get pods -n argocd
```

**Expected**: ArgoCD HA pods 다수 Running. 노드 자원 부족으로 일부 Pending 발생 가능 (정상).

### 5-3. argocd-server를 replicas=3으로 scale

ArgoCD HA install.yaml의 default가 server replicas=2. PRD W1 FR-GO-101은 3을 요구:
```powershell
kubectl scale deployment argocd-server -n argocd --replicas=3
Start-Sleep -Seconds 60
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server
```

3노드 cluster의 pod anti-affinity로 1개가 Pending이어도 deployment.replicas=3은 충족됨.

---

## 6. synapse 매니페스트 적용 (1분)

본 레포 main으로 sync:
```powershell
cd D:\workspace\final-project-syn\synapse-gitops
git checkout main && git pull --ff-only origin main
```

매니페스트 3개 적용:
```powershell
kubectl apply -f argocd\projects.yaml
kubectl apply -f argocd\bootstrap\
kubectl apply -f argocd\applicationset.yaml
```

**Expected**:
```
appproject.argoproj.io/synapse created
configmap/argocd-rbac-cm configured
configmap/argocd-notifications-cm configured
applicationset.argoproj.io/synapse-apps created
```

---

## 7. 5개 Application 등록 확인 (FR-GO-103)

```powershell
Start-Sleep -Seconds 10
kubectl get applications -n argocd
```

**Expected**:
```
NAME                          SYNC STATUS   HEALTH STATUS
synapse-engagement-svc-dev    Synced        Progressing
synapse-knowledge-svc-dev     Synced        Progressing
synapse-learning-ai-dev       Synced        Progressing
synapse-learning-card-dev     Synced        Progressing
synapse-platform-svc-dev      Synced        Progressing
```

`Progressing` Health Status는 base/overlay manifest가 거의 비어있어서 정상. W2에 실제 워크로드 채워짐.

---

## 8. (선택) UI 접속 — port-forward

별도 PowerShell 창에서 port-forward (이 창은 살려두기):
```powershell
kubectl port-forward svc/argocd-server -n argocd 8443:443
```

원래 창에서 initial admin 비번 추출 (PowerShell):
```powershell
$bytes = [System.Convert]::FromBase64String((kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}'))
[System.Text.Encoding]::UTF8.GetString($bytes)
```

브라우저:
- https://localhost:8443
- self-signed 경고 수용 (옵션 2의 self-signed TLS 동작과 동등)
- admin / 위 비번으로 로그인
- UI에서 5개 Application 카드 확인

---

## 9. (선택) CI 실패 검증 — 의도적 오류 PR (FR-GO-104)

ArgoCD 동작과 별개로, kubeconform CI가 잘못된 매니페스트를 잡는지 검증. 가장 확실한 방법은 **kustomize build 실패**:

```powershell
git checkout main && git pull --ff-only
git checkout -b test/intentional-ci-failure

# kustomization.yaml에 존재하지 않는 resource 추가
"  - nonexistent-file.yaml" | Add-Content apps\platform-svc\overlays\dev\kustomization.yaml

git add apps\platform-svc\overlays\dev\kustomization.yaml
git commit -m "test: trigger kustomize build failure"
git push -u origin test/intentional-ci-failure

gh pr create --title "test: CI failure verification (DO NOT MERGE)" --body "FR-GO-104 검수용. 머지 금지."
gh pr checks --watch
```

**Expected**: `validate`가 **FAIL** (kustomize build 단계).

⚠️ **`apiVersion` 변경(예: apps/v1 → apps/v999)으로 검증하려 하면 통과해버린다**: kubeconform `-ignore-missing-schemas` 옵션이 unknown apiVersion을 skip. CRD 호환을 위한 trade-off. W3에서 CRD 카탈로그 정비 시 강화 예정.

검증 후 즉시 정리:
```powershell
gh pr close --delete-branch
git checkout main && git pull
```

---

## 10. Cleanup (1분)

학습 완료 후 메모리 해방:
```powershell
kind delete cluster --name synapse-dev
```

**Expected**: `Deleted cluster "synapse-dev"`.

작업 폴더 삭제 (선택):
```powershell
Remove-Item -Recurse D:\workspace\final-project-syn\synapse-gitops\kind-local
```

Docker Desktop도 종료해서 메모리 완전 해방 가능.

---

## 트러블슈팅 (2026-05-16 실제 발생 + 일반 케이스)

### ❌ `kubectl apply -f .../ha/install.yaml` 에서 `metadata.annotations: Too long: may not be more than 262144 bytes`

**원인**: ApplicationSet CRD spec이 너무 커서 client-side `kubectl apply`의 last-applied-configuration annotation 한계(262144 bytes) 초과.

**해결**: `--server-side --force-conflicts` 사용. 본 가이드 5-1에 이미 반영.

### ❌ ApplicationSet CRD만 따로 설치하고 싶을 때

```powershell
kubectl apply --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/crds/applicationset-crd.yaml
```

### ❌ argocd-redis-ha-haproxy-N / argocd-server-N 이 Pending 상태

**원인**: HA pods의 PodAntiAffinity가 같은 노드에 같은 컴포넌트의 pod이 두 개 이상 schedule되지 않도록 강제. 3노드 cluster + 컴포넌트당 3 replica면 anti-affinity 만족 불가.

**해결 (학습용)**: 무시 가능. PRD HA 토폴로지 의도는 deployment.replicas=N으로 충족. 정확하게 동작 검증하려면 kind cluster를 4+ 노드로 늘리거나 anti-affinity 완화.

```powershell
# anti-affinity 완화 예시 (deployment patch)
kubectl patch deployment argocd-redis-ha-haproxy -n argocd --type=json -p='[{"op": "remove", "path": "/spec/template/spec/affinity/podAntiAffinity"}]'
```

### ❌ Pod이 `ImagePullBackOff`

**원인**: kind 노드가 인터넷 접근 못 하거나 image pull rate limit.

**해결**:
- Docker Desktop이 인터넷 가능한지 확인
- 인증된 docker login 후 재시도 (`docker login`)
- kind의 이미지 사전 로드: `kind load docker-image <image>:<tag> --name synapse-dev`

### ❌ `Application X is Synced but Health: Progressing`

정상. base/overlay manifest의 Deployment는 만들어졌지만 image가 placeholder라 pod이 안 뜸. W2 워크로드 채움 시 Healthy로 전환.

### ❌ port-forward가 "address already in use"

이미 다른 프로세스가 8443 점유. 다른 port로:
```powershell
kubectl port-forward svc/argocd-server -n argocd 9443:443
```
→ 브라우저: https://localhost:9443

### ❌ `kind create cluster`가 도중에 멈춤 / 매우 느림

Docker Desktop 메모리/CPU 부족. Settings → Resources에서 늘리고 Docker 재시작.

### ❌ `kubectl` 명령이 "The connection to the server localhost:8080 was refused"

kubeconfig context가 kind로 안 잡힘:
```powershell
kubectl config use-context kind-synapse-dev
```

---

## EKS path와의 매핑

| 항목 | EKS (옵션 2) | kind (B-2) |
|---|---|---|
| 비용 | $0.30~$0.40/시간 | 0 |
| HA 토폴로지 | Helm 차트 + `argocd-helm` values | install.yaml + kubectl scale |
| 외부 노출 | NLB passthrough + self-signed TLS | port-forward (localhost) |
| admin 비번 | Secrets Manager (`synapse/argocd/admin`) | `argocd-initial-admin-secret` 직접 사용 |
| 5 Application 등록 | bootstrap-argocd.sh 자동 | 수동 kubectl apply |
| 정리 | `terraform destroy` (~10분) | `kind delete cluster` (1분) |

EKS path가 가능해지면(예: 결제수단 verification 완료) [w1-argocd-bootstrap-runbook.md](./w1-argocd-bootstrap-runbook.md) Step 3 그대로 진행. 본 가이드는 fallback / 학습용.
