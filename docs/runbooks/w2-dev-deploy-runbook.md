# Runbook: W2 Dev 환경 배포 + 시크릿 + 이미지 자동화 실행 가이드

> **대상**: gitops 트랙 담당자 (@VelkaressiaBlutkrone) 또는 dev 환경 배포 작업자
> **소요 시간**: 약 5일 (2026-05-19 ~ 2026-05-23)
> **전제**: W1 완료 (ArgoCD 부트스트랩 + ApplicationSet 구성 + CI 검증), EKS 클러스터 Running, ArgoCD UI 접속 가능
>
> 이전 단계: [w1-argocd-bootstrap-runbook.md](./w1-argocd-bootstrap-runbook.md) 완료 상태

---

## 0. 준비물 체크리스트

실행 전에 모두 확보:

- [ ] W1 runbook 완료 확인: `argocd app list`에 5개 `synapse-*-dev` Application 표시
- [ ] `kubectl` — EKS 클러스터 연결 확인 (`kubectl get nodes` → Ready)
- [ ] `argocd` CLI — 로그인 상태 (`argocd account get-user-info`)
- [ ] `helm` v3 — ESO 및 Image Updater 설치용
- [ ] `aws` CLI — Secrets Manager 접근 가능 (`aws secretsmanager list-secrets`)
- [ ] `gitleaks` 또는 `trufflehog` — 시크릿 스캔용
- [ ] 5개 앱 Docker 이미지 — ECR에 최소 1개 태그 push 완료
- [ ] `gh` CLI 로그인 + 레포 push 권한
- [ ] 작업 디렉토리: `synapse-gitops` 레포 루트, main 최신 sync (`git pull origin main`)

도구 부재 시:
```bash
# macOS (Homebrew)
brew install helm gitleaks

# Windows (Chocolatey)
choco install kubernetes-helm gitleaks

# gitleaks 수동 설치
# https://github.com/gitleaks/gitleaks/releases
```

5개 앱 목록:

| 앱 | 디렉토리 | 포트 | 설명 |
|---|---|---|---|
| platform-svc | `apps/platform-svc/` | 8080 | 플랫폼 공통 서비스 |
| engagement-svc | `apps/engagement-svc/` | 8080 | 사용자 참여 서비스 |
| knowledge-svc | `apps/knowledge-svc/` | 8080 | 지식 관리 서비스 |
| learning-card | `apps/learning-card/` | 3000 | 학습 카드 프론트엔드 |
| learning-ai | `apps/learning-ai/` | 8000 | AI 학습 서비스 |

---

## Step 4. Dev Overlay 5개 앱 완성 (2일)

5개 앱의 base 매니페스트 + dev overlay를 작성하고, ArgoCD 자동 sync로 dev 네임스페이스에 배포한다.

📖 **[step4-dev-overlay.md](./step4-dev-overlay.md)** — 4-A 사전 분석 / 4-B base 매니페스트 작성 / 4-C dev overlay 작성 / 4-D ArgoCD sync + 검증. 트러블슈팅 5건.

요약:
1. 5개 앱별 리소스 요구사항, 환경변수, 포트, 헬스체크 endpoint 정리
2. `apps/{app}/base/`에 deployment.yaml, service.yaml, configmap.yaml, kustomization.yaml 작성
3. `apps/{app}/overlays/dev/kustomization.yaml`에 dev 전용 설정 (replica=1, 최소 리소스, LOG_LEVEL=DEBUG)
4. git push → ArgoCD 자동 sync → 5앱 Synced + Healthy 확인

검증:
```bash
argocd app list
# 5개 모두 Status: Synced, Health: Healthy

kubectl get pods -n dev
# 5개 pod 모두 Running
```

---

## Step 5. ESO Secret 관리 (1.5일)

External Secrets Operator를 도입해 AWS Secrets Manager에서 시크릿을 자동 동기화한다. git에서 평문 시크릿을 완전히 제거한다.

📖 **[step5-eso-secrets.md](./step5-eso-secrets.md)** — 5-A 사전 분석 / 5-B AWS Secrets Manager 등록 / 5-C ESO 설치 / 5-D 테스트 / 5-E 5개 앱 ExternalSecret 작성 / 5-F 보안 검증. 트러블슈팅 4건.

요약:
1. ESO vs SOPS vs Sealed Secrets 비교 후 ESO 선택 (AWS native, 운영 단순)
2. AWS Secrets Manager에 5개 앱 시크릿 등록 (명명: `synapse/dev/{app}/{key}`)
3. Helm으로 ESO 설치 + IRSA 설정 + ClusterSecretStore 생성
4. 5개 앱 ExternalSecret 매니페스트 작성, 기존 평문 Secret 제거
5. gitleaks로 git history 전체 스캔 → 평문 시크릿 0건 확인

검증:
```bash
kubectl get externalsecret -n dev
# 5개 모두 SecretSynced=True

gitleaks detect --source . --verbose
# 0 findings
```

---

## Step 6. 이미지 태그 자동 Sync (1.5일)

ArgoCD Image Updater를 설치해 ECR에 새 이미지가 push되면 자동으로 dev 환경에 반영하고, 태그 변경 이력을 git log에 남긴다.

📖 **[step6-image-sync.md](./step6-image-sync.md)** — 6-A 사전 분석 / 6-B Image Updater 설치 / 6-C Application annotation 추가 / 6-D 자동 머지 정책 / 6-E 검증. 트러블슈팅 4건.

요약:
1. ArgoCD Image Updater vs GitHub Actions PR 방식 비교 후 Image Updater 선택
2. Helm으로 Image Updater 설치 + ECR 인증 설정
3. 5개 Application에 image-updater annotation 추가 (update-strategy: semver)
4. write-back-method: git → 태그 변경이 git commit으로 기록
5. 테스트 이미지 push → 5분 이내 dev Pod 반영 확인

검증:
```bash
# 새 이미지 push 후 5분 대기
kubectl get pods -n dev -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'

# git log에 태그 변경 커밋 확인
git log --oneline -5
```

---

## 검증 체크리스트 (Done 표시용)

W2 PRD 검수 기준 최종 검증:

- [ ] **FR-GO-201**: `argocd app list` 출력에 5개 앱 모두 `Synced` + `Healthy` (P0)
- [ ] **FR-GO-202**: `curl -s -o /dev/null -w '%{http_code}' https://dev-platform-svc.<도메인>/health` → `200` (5개 앱 모두) (P0)
- [ ] **FR-GO-203**: `gitleaks detect --source .` → 0 findings + `kubectl get externalsecret -n dev` 모두 정상 (P0)
- [ ] **FR-GO-204**: `kubectl get externalsecret -n dev` → 5개 모두 `SecretSynced=True` (P0)
- [ ] **FR-GO-205**: ECR에 새 이미지 push 후 5분 이내 `kubectl get pods -n dev`에서 신규 이미지 태그 확인 (P1)
- [ ] **FR-GO-206**: `git log --oneline` → Image Updater의 태그 변경 커밋 존재 (P1)

---

## 트러블슈팅 (공통)

### ArgoCD sync가 안 됨

```bash
# Application 상태 확인
argocd app get synapse-platform-svc-dev

# sync 강제 실행
argocd app sync synapse-platform-svc-dev

# ApplicationSet 상태 확인
kubectl get applicationset -n argocd
kubectl describe applicationset synapse-apps -n argocd
```

### kubectl 연결 끊김

```bash
# kubeconfig 갱신
aws eks update-kubeconfig --name synapse-dev --region ap-northeast-2

# 노드 상태 확인
kubectl get nodes
```

### ECR 이미지 pull 실패

```bash
# ECR 로그인 토큰 갱신 (12시간마다 만료)
aws ecr get-login-password --region ap-northeast-2 | kubectl create secret docker-registry ecr-cred \
  --docker-server=<ACCOUNT>.dkr.ecr.ap-northeast-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region ap-northeast-2) \
  -n dev --dry-run=client -o yaml | kubectl apply -f -
```

### Helm 설치 실패

```bash
# Helm repo 업데이트
helm repo update

# 설치된 릴리즈 확인
helm list -A

# 실패한 릴리즈 삭제 후 재설치
helm uninstall <release-name> -n <namespace>
```

---

## 실 환경 정리 (W2 학습 완료 후)

```bash
# Image Updater 제거
helm uninstall argocd-image-updater -n argocd

# ESO 제거
helm uninstall external-secrets -n external-secrets

# Application 삭제
argocd app delete -y synapse-platform-svc-dev synapse-engagement-svc-dev \
  synapse-knowledge-svc-dev synapse-learning-card-dev synapse-learning-ai-dev

# dev 네임스페이스 정리
kubectl delete namespace dev

# AWS Secrets Manager 시크릿 정리
for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  aws secretsmanager delete-secret --secret-id synapse/dev/$app/db-password --region ap-northeast-2
done
```

---

## 도움 요청

- 본 runbook의 단계가 막힐 때: HISTORY에 "도움 요청" 항목으로 기록 + Slack #synapse-gitops 채널
- ArgoCD Image Updater: https://argocd-image-updater.readthedocs.io/
- External Secrets Operator: https://external-secrets.io/
- Kustomize: https://kustomize.io/
