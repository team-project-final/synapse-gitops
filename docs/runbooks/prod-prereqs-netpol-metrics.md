# Runbook: Prod 선행조건 — VPC CNI NetworkPolicy 컨트롤러 + metrics-server

> **대상**: prod 배포 담당자 (gitops 트랙)
> **소요 시간**: ~15분 (클러스터 접근 가능 상태 기준)
> **전제**: W3 완료 (staging overlay + Observability 스택 동작 확인), prod ApplicationSet Manual sync 활성화 전

---

## 왜 필요한가

prod overlays는 두 가지 클러스터 수준 선행조건에 의존한다.

| prod 오버레이 | 선행조건 | 미충족 시 증상 |
|---|---|---|
| `apps/*/overlays/prod/netpol.yaml` | VPC CNI NetworkPolicy 컨트롤러 활성 | NetworkPolicy가 조용히 무시됨 (보안 no-op — 차단도 장애도 없이 정책 미집행) |
| `apps/*/overlays/prod/hpa.yaml` | metrics-server 설치 | HPA TARGETS가 `<unknown>` 반환, 스케일링 불가 |

두 조건이 충족되지 않은 채 prod ApplicationSet을 sync하면 보안 정책이 집행되지 않고 오토스케일링이 동작하지 않는다.

---

## 인프라-as-코드 구현 (WS4)

- **WS4-1** (`infra/aws/dev/eks.tf`): `aws_eks_addon.vpc_cni` 리소스 — `enableNetworkPolicy=true` 설정. `terraform apply` 시 EKS 관리형 addon으로 VPC CNI에 NetworkPolicy 컨트롤러가 활성화된다.
- **WS4-2** (`infra/k8s-addons/metrics-server.yaml`): 공식 upstream metrics-server v0.7.2 vendored manifest. `bring-up.sh` `manifests` phase 직후 `metrics-server` phase로 자동 설치된다.

---

## 검증 순서 (prod 윈도)

prod ApplicationSet Manual sync 전에 아래 순서로 확인한다.

### 1) VPC CNI NetworkPolicy 컨트롤러 활성 확인

```bash
kubectl -n kube-system get ds aws-node -o yaml | grep -i ENABLE_NETWORK_POLICY || echo "(미설정 — 컨트롤러 비활성)"
```

`ENABLE_NETWORK_POLICY: "true"` 가 출력되어야 한다.

출력이 없거나 `"false"` 이면 terraform vpc-cni addon을 재적용한다 (WS4-1):

```bash
cd infra/aws/dev
terraform apply -target=aws_eks_addon.vpc_cni -auto-approve -input=false
```

### 2) metrics-server Ready 확인

```bash
kubectl -n kube-system get deploy metrics-server
```

`READY` 열이 `1/1` 이어야 한다.

미설치 또는 미Ready이면 bring-up에서 해당 phase만 재실행한다 (WS4-2):

```bash
bash scripts/bring-up.sh --from metrics-server --to metrics-server
```

### 3) NetworkPolicy 집행 스모크 테스트

gateway 라벨이 없는 파드는 engagement-svc:8080 에 도달해서는 안 된다.

```bash
# gateway 라벨 없는 임시 파드 → engagement 접근 시도 (차단 기대: 000 또는 timeout)
kubectl -n synapse-prod run probe --rm -i --restart=Never --image=curlimages/curl \
  --command -- curl -s -m5 -o /dev/null -w "%{http_code}\n" \
  http://engagement-svc.synapse-prod.svc.cluster.local:8080
# 결과가 200이면 NetworkPolicy 미집행 → step 1 재확인
```

### 4) HPA TARGETS 확인

```bash
kubectl -n synapse-prod get hpa
```

`TARGETS` 열에 `cpu: 12%/70%` 처럼 실제 수치가 표시되어야 한다. `<unknown>/70%` 이면 step 2 재확인.

---

## 비고

- dev/staging은 NetworkPolicy 및 HPA를 prod-only로 적용한다 (보고서 §2.2). dev/staging overlay에는 해당 리소스가 없으므로 이 선행조건은 prod 전용이다.
- prod ApplicationSet은 Manual sync로 설정되어 있어 위 검증을 완료한 뒤 담당자가 명시적으로 `argocd app sync` 를 실행해야 한다.
- VPC CNI NetworkPolicy 컨트롤러 활성 여부는 `networkpolicy-validation.md` §사전 필수 항목도 함께 참고.

---

## 관련 파일

- `infra/aws/dev/eks.tf` — `aws_eks_addon.vpc_cni` (WS4-1)
- `infra/k8s-addons/metrics-server.yaml` — vendored metrics-server v0.7.2 (WS4-2)
- `scripts/bring-up.sh` — `metrics-server` phase (`manifests` 직후)
- `docs/runbooks/networkpolicy-validation.md` — prod netpol 검증 절차
