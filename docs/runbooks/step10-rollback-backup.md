# Runbook: 롤백 + 백업 체계 구축 (Step 10 상세)

> **소요 시간**: 약 2일 (2026-06-04 ~ 06-05)
> **결과**: staging 복구 시뮬 통과, 백업 스케줄 동작, 롤백 절차 검증 완료
> **상위 문서**: [w4-prod-rollback-runbook.md](./w4-prod-rollback-runbook.md) Step 10
> **사전 조건**: Step 9 완료 (15 Application, prod Manual Sync, RBAC 검증 통과)

---

## 10-A. 사전 분석 (30분)

### 롤백 시나리오 분류

| 시나리오 | 롤백 방법 | 복구 시간 |
|---|---|---|
| 매니페스트 롤백 | git revert → ArgoCD auto sync | 2~5분 |
| 이미지만 롤백 | ArgoCD History rollback 또는 태그 고정 | 3~5분 |
| 클러스터 전체 복구 | Velero restore (S3 백업) | 15~30분 |

### RTO/RPO 목표

- **RTO** 30분: Velero restore + ArgoCD sync 포함
- **RPO** 1시간: 일일 백업 + git history 보완 (매니페스트는 git에 있으므로 RPO 사실상 0)

### 백업 저장소

S3 `synapse-velero-backups` 버킷. 일일 백업 7일 보존, 수동 백업 30일 보존. 암호화(AES-256) + 퍼블릭 차단.

---

## 10-B. ArgoCD 롤백 검증 (1시간)

### 10-B-1. ArgoCD History 기반 롤백

```bash
# 이전 sync 이력 확인
argocd app history synapse-platform-svc-staging

# 이전 revision으로 롤백
argocd app rollback synapse-platform-svc-staging <HISTORY_ID>
```

**Expected**: 이전 revision 매니페스트로 Pod 재생성.

> ArgoCD rollback은 git을 변경하지 않는다. 다음 sync 시 HEAD로 돌아간다. 영구 롤백은 git revert 사용.

### 10-B-2. git revert 기반 롤백

```bash
git log --oneline -10
git revert <problem-commit-hash> --no-edit
git push origin main
argocd app wait synapse-platform-svc-staging --sync --timeout 120
```

**Expected**: dev/staging 자동 sync로 이전 상태 복원.

### 10-B-3. Image Updater 태그 강제 고정

```bash
# Image Updater 자동 업데이트 무시 — annotation override
argocd app set synapse-platform-svc-staging \
  --annotation argocd-image-updater.argoproj.io/image-list=""
```

또는 `kustomization.yaml`에서 `images[].newTag`를 고정 태그로 지정.

---

## 10-C. Velero 설치 (1시간)

### 10-C-1. S3 백업 버킷 생성

```bash
aws s3api create-bucket --bucket synapse-velero-backups \
  --region ap-northeast-2 \
  --create-bucket-configuration LocationConstraint=ap-northeast-2

aws s3api put-bucket-versioning --bucket synapse-velero-backups \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption --bucket synapse-velero-backups \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block --bucket synapse-velero-backups \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

### 10-C-2. IRSA for Velero ServiceAccount

```bash
# IAM Policy 생성 (S3 + EBS snapshot 권한)
aws iam create-policy --policy-name VeleroAccessPolicy \
  --policy-document file://infra/velero/velero-iam-policy.json

# IRSA 연결
eksctl create iamserviceaccount --name velero --namespace velero \
  --cluster synapse-dev \
  --attach-policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/VeleroAccessPolicy \
  --approve --override-existing-serviceaccounts
```

필요 권한: `ec2:DescribeVolumes`, `ec2:CreateSnapshot`, `ec2:DeleteSnapshot`, `s3:GetObject/PutObject/DeleteObject/ListBucket`.

### 10-C-3. Helm으로 Velero 설치

```bash
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts && helm repo update

helm install velero vmware-tanzu/velero --namespace velero --create-namespace \
  --set configuration.backupStorageLocation[0].name=default \
  --set configuration.backupStorageLocation[0].provider=aws \
  --set configuration.backupStorageLocation[0].bucket=synapse-velero-backups \
  --set configuration.backupStorageLocation[0].config.region=ap-northeast-2 \
  --set configuration.volumeSnapshotLocation[0].name=default \
  --set configuration.volumeSnapshotLocation[0].provider=aws \
  --set configuration.volumeSnapshotLocation[0].config.region=ap-northeast-2 \
  --set initContainers[0].name=velero-plugin-for-aws \
  --set initContainers[0].image=velero/velero-plugin-for-aws:v1.9.0 \
  --set initContainers[0].volumeMounts[0].mountPath=/target \
  --set initContainers[0].volumeMounts[0].name=plugins \
  --set serviceAccount.server.create=false \
  --set serviceAccount.server.name=velero
```

```bash
kubectl get pods -n velero            # velero pod Running
velero version                        # Client + Server 버전
velero backup-location get            # default BSL Phase: Available
```

---

## 10-D. 백업 스케줄 + 복구 시뮬레이션 (2시간)

### 10-D-1. 일일 스케줄 백업 정의

```yaml
# infra/velero/daily-schedule.yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: daily-backup
  namespace: velero
spec:
  schedule: "0 2 * * *"          # 매일 02:00 UTC (KST 11:00)
  template:
    includedNamespaces: [dev, staging, prod]
    excludedResources: [events, events.events.k8s.io]
    storageLocation: default
    ttl: 168h0m0s                # 7일 보존
    snapshotVolumes: true
```

```bash
kubectl apply -f infra/velero/daily-schedule.yaml
velero schedule get                   # daily-backup Enabled
```

### 10-D-2. 수동 백업 + 복구 시뮬레이션

```bash
# 1. staging 수동 백업
velero backup create staging-manual-backup \
  --include-namespaces staging --storage-location default --ttl 72h

# 2. 백업 완료 대기
velero backup describe staging-manual-backup --details
# Expected: Phase: Completed

# 3. 복구 시뮬 시작 — staging 삭제
START_TIME=$(date +%s)
kubectl delete namespace staging --wait=true
kubectl get namespace staging          # NotFound

# 4. Velero restore
velero restore create staging-restore --from-backup staging-manual-backup \
  --include-namespaces staging
velero restore wait staging-restore --timeout 30m

# 5. 검증 + RTO 측정
kubectl get pods -n staging            # 5개 pod Running
END_TIME=$(date +%s)
echo "소요: $(( (END_TIME - START_TIME) / 60 ))분"

# 6. ArgoCD 재연결
for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  argocd app get synapse-$app-staging --hard-refresh
done
```

**Expected**: staging 5개 Pod 복구, RTO 30분 이내, ArgoCD `Synced` + `Healthy`.

---

## 10-E. 백업 모니터링 + 문서화 (1시간)

### 10-E-1. 백업 실패 알람 (PrometheusRule)

```yaml
# infra/monitoring/velero-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: velero-backup-alerts
  namespace: monitoring
  labels: { release: prometheus }
spec:
  groups:
    - name: velero.rules
      rules:
        - alert: VeleroBackupFailed
          expr: increase(velero_backup_failure_total[24h]) > 0
          for: 5m
          labels: { severity: critical }
          annotations: { summary: "Velero 백업 실패 감지" }
        - alert: VeleroBackupNotScheduled
          expr: time() - velero_backup_last_successful_timestamp{schedule="daily-backup"} > 90000
          for: 10m
          labels: { severity: warning }
          annotations: { summary: "Velero 일일 백업 25시간 이상 미실행" }
```

```bash
kubectl apply -f infra/monitoring/velero-alerts.yaml
```

### 10-E-2. etcd snapshot 정책

> EKS 관리형: etcd는 AWS 책임. 직접 접근/백업 불가. 클러스터 전체 복구 시 새 EKS 생성 + Velero restore.
> self-managed K8s는 `etcdctl snapshot save` 정기 실행 필요.

### 10-E-3. 롤백/백업 절차 문서

- **매니페스트 롤백**: `git revert` → main push → auto sync
- **이미지 롤백**: `argocd app rollback <app> <ID>` + Image Updater annotation 제거
- **전체 복구**: `velero restore create --from-backup <name>` → `argocd hard-refresh`

---

## 자주 막히는 지점

### Velero IRSA 권한 부족
**증상**: `AccessDenied` 또는 `NoCredentialProviders`. SA annotation 확인 → `kubectl get sa velero -n velero -o yaml`. 없으면 IRSA 재설정 후 `kubectl rollout restart deployment velero -n velero`.

### S3 bucket 생성 안 됨
`BucketAlreadyExists` → 글로벌 unique 이름 변경. `403 Forbidden` → IAM 권한 부족.

### 백업 크기 과다 (PV 제외 옵션)
GitOps는 매니페스트가 git에 있으므로 `--snapshot-volumes=false`로 PV 제외 가능.

### 복구 순서 의존성
`velero restore describe --details`로 실패 리소스 확인. 순서: Namespace → Secret/ConfigMap → ServiceAccount → Deployment → Service. 부분 복구 후 나머지 수동 적용.

### etcd snapshot 직접 접근 불가
EKS 관리형은 etcd 접근 불가. Velero 리소스 레벨 백업 + git 매니페스트로 대체.

---

## 다음 단계

W4 완료 후 전체 파이프라인 완성: 코드 변경 → CI → dev/staging(auto) → prod(manual) → 장애 시 롤백/Velero restore.

📖 상위 문서: [w4-prod-rollback-runbook.md](./w4-prod-rollback-runbook.md)
