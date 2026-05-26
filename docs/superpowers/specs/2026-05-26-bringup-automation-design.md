# Bring-up 자동화·견고화 설계

> **작성일**: 2026-05-26
> **트랙**: gitops
> **담당**: @VelkaressiaBlutkrone
> **배경**: 클러스터가 매 세션 `terraform destroy`되는 구조라, W3 잔여 검증(staging 5/5 Healthy · 메트릭 E2E 수집 · 실 Slack 도달)을 하려면 매번 W1(ArgoCD)+W2(ESO+앱) 부트스트랩을 거쳐야 한다. 현재 부트스트랩은 12단계 수동 런북(`w2-session-bootstrap-runbook.md`)이라 느리고 취약하다. 이를 멱등 스크립트로 자동화·견고화한다.
> **관련**: [HANDOFF_W3](../HANDOFF_W3.md) (D-026/032/033/034/035), [w2-session-bootstrap-runbook](../../runbooks/w2-session-bootstrap-runbook.md)

---

## 1. 목표

`scripts/bring-up.sh` 한 명령으로 destroy된 상태에서 **dev/staging + observability까지 기동**하고, `--verify`로 W3 잔여 3개 항목을 **반복가능하게 검증**한다. 수동 런북의 취약점(SG ID 수동 탐색, OIDC ID 매 apply 변경, `--server-side` 누락, bastion에 git 없음)을 자동화로 제거한다.

**범위 밖(cross-repo)**: platform-svc staging Spring 프로필, learning-ai 기동 문제는 app 레포 소관. 스크립트는 앱을 이미지가 허용하는 만큼 띄우고, 검증에서 "조건부"로 표시한다.

---

## 2. 핵심 결정

| 항목 | 결정 |
|---|---|
| 실행 모델 | **로컬 단일 스크립트 + SSM 포트포워딩 터널** — kubectl/helm을 로컬에서 터널 경유 실행, 로컬 워킹트리 매니페스트 직접 적용 |
| EBS CSI (D-033) | **terraform `aws_eks_addon`** + IRSA + gp3 default StorageClass |
| 죽은 `helm_release.argocd` | **terraform에서 제거** — apply가 exit 0으로 정상화, argocd는 스크립트가 터널 경유 설치 |
| 비밀값 | `synapse/monitoring/grafana`·`synapse/monitoring/alertmanager`(실 Slack webhook)를 **AWS SM에 1회 생성(destroy에도 보존)** → ESO 동기화 |
| SG/OIDC 취약점 | terraform **output**으로 SG ID·bastion·endpoint·OIDC 노출 → 스크립트가 결정적으로 읽음 |

---

## 3. 파일 구조

```
scripts/
  bring-up.sh            # 메인: phase 함수 선형 실행, --from <phase>, --verify, --destroy, --dry-run, --help
  lib/eks-tunnel.sh      # SSM 포트포워딩 + 터널 kubeconfig(tls-server-name) 생성/정리, source용
infra/aws/dev/
  addons.tf              # (신규) aws_eks_addon.aws-ebs-csi-driver + IRSA role/policy
  outputs.tf             # SG ID 4종 + eks_cluster_sg + bastion_instance_id + oidc_id + eks_endpoint 추가
  argocd.tf              # helm_release.argocd + output 제거
infra/monitoring/
  storageclass-gp3.yaml  # (신규) gp3 default SC (gp2 in-tree 대체, isDefaultClass)
docs/runbooks/
  w2-session-bootstrap-runbook.md  # bring-up.sh를 1차 경로로, 수동 12단계는 fallback으로 갱신
```

`bring-up.sh` 흐름: 로컬 terraform/AWS CLI 단계 → `lib/eks-tunnel.sh` source(터널+kubeconfig) → kubectl/helm 단계(argocd·ESO·manifests·observability) → `trap`으로 터널 정리.

---

## 4. Phase 분해 (멱등)

| # | Phase | 동작 | 멱등 검사 / readiness |
|---|---|---|---|
| 1 | `terraform` | init(필요시)+apply | 선언적. argocd 제거+EBS CSI addon으로 exit 0 정상화 |
| 2 | `eks-auth` | authenticationMode=API_AND_CONFIG_MAP | 현재 모드 확인 후 변경, `aws eks wait cluster-active` |
| 3 | `access-entry` | 운영자(synapse-admin) cluster-admin access entry | 엔트리 존재 시 skip (터널은 bastion k8s 권한 불필요) |
| 4 | `sg` | EKS SG→RDS/Redis/MSK/OpenSearch ingress (D-026) | terraform output의 SG ID 사용, 중복 규칙 무시 |
| 5 | `tunnel` | SSM 포트포워딩+터널 kubeconfig (lib) | kubectl 도달까지 폴링, trap 종료정리 |
| 6 | `argocd` | ns + `apply --server-side` install.yaml + `--insecure` patch | 서버사이드 재적용 idempotent, pods Ready 대기 |
| 7 | `eso` | helm install/upgrade + IRSA SA annotate + restart | 릴리스 있으면 upgrade, rollout status 대기 |
| 8 | `oidc-fix` | 현 OIDC ID vs ESO role trust policy 비교→불일치 시 갱신+restart | 매 apply 갱신되는 OIDC ID 자동 처리 |
| 9 | `manifests` | ClusterSecretStore+projects+ApplicationSet(dev+staging auto) 로컬 트리에서 apply | CSS Valid + 5 ExternalSecret SecretSynced 대기 |
| 10 | `observability` | monitoring ns + SM 시크릿 확인 + ESO + kube-prom-stack/Loki/Promtail + ServiceMonitor/Rule/dashboard | SM 시크릿 없으면 명확 경고, pods Ready 대기 (EBS CSI+gp3로 Loki 영속화 정상) |
| 11 | `status` | dev/staging 앱·ESO·monitoring 상태 출력 | — |

`--from <phase>`로 중간 재개. 각 phase 실패 시 phase명+조치 힌트 출력 후 중단(에러 미삼킴).

---

## 5. 검증 (`--verify`)

bring-up 후 3개 항목 검사 → PASS/FAIL/조건부 표 + 증거를 stdout 및 `verification-<date>.md`에 기록(커밋 여부는 사용자 선택).

| 검증 | 방법 | 통과 기준 | cross-repo caveat |
|---|---|---|---|
| **staging N/5 Healthy** | `kubectl -n argocd get apps` + staging pods | 각 앱 Synced/Healthy | platform-svc·learning-ai는 app 레포 → 실패 시 "조건부", 막힌 앱 명시 |
| **메트릭 E2E** | Prometheus `/api/v1/targets`(터널) + `up{namespace=~"synapse-.*"}` + 앱 메트릭(`http_server_requests…`) | 5앱 타깃 UP & 메트릭 반환 | 타깃 DOWN이면 앱이 `/actuator/prometheus` 미노출 = app 레포(micrometer). ServiceMonitor(gitops)는 정상 |
| **실 Slack 도달** | 즉발 PrometheusRule(`for: 0s`, `TestSlackDelivery`) 적용→Alertmanager firing+slack 라우팅 확인→채널 수신→임시 룰 제거 | Alertmanager 라우팅 OK + 채널 수신 | SM에 실 webhook 있으면 gitops 완전 검증 |

- **즉발 테스트 룰**: SynapsePodDown(`for: 5m`)는 느리므로 일회성 `TestSlackDelivery`(`for: 0s`)로 즉시 발화→Slack 확인→삭제(잔존물 없음).
- **실 Slack 수신**: Alertmanager 알림 로그(에러 없음)+라우팅까지 자동, 채널 실수신은 사람이 눈으로 확인(Slack API 토큰 제공 시 자동).

---

## 6. 에러 처리 · 정리 · 테스트

- **에러 처리**: `set -euo pipefail`. phase 실패 시 phase명+조치 힌트 출력 후 중단. `trap`으로 종료/실패 시 SSM 터널 정리. `--from <phase>`로 재개.
- **정리**: `bring-up.sh --destroy` → `terraform destroy`로 비용 차단. argocd 리소스 제거로 destroy 깔끔.
- **테스트**:
  - 정적(무비용): `shellcheck` 통과 + `--dry-run`(명령 출력만) 흐름 검증.
  - 멱등성: bring-up 후 한 phase 재실행 시 안전(skip/upgrade) 확인.
  - 수용: 1회 실제 사이클(apply→bring-up→`--verify`→phase 재실행→destroy) — 클러스터 1회 과금 필요(정직히 명시).

---

## 7. 완료 정의

- `scripts/bring-up.sh` + `lib/eks-tunnel.sh` 작성, `shellcheck` 통과, `--dry-run` 동작
- terraform: EBS CSI addon+IRSA, gp3 SC, 필요한 output 추가, 죽은 argocd 리소스 제거 — `terraform validate` 통과
- 런북을 1차 경로(스크립트)로 갱신, 수동 단계는 fallback 보존
- (수용) 1회 실제 사이클로 bring-up + `--verify` 통과 — staging은 cross-repo 조건부 허용
