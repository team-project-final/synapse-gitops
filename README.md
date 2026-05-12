# synapse-gitops

Kubernetes 매니페스트 + ArgoCD ApplicationSet 관리.

## 구조
```
envs/
  dev/
  staging/
  prod/
apps/
  base/
```

## 배포 방식
- ArgoCD ApplicationSet 기반 GitOps
- PR merge → ArgoCD 자동 sync
