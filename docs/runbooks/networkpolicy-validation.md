# Runbook — prod NetworkPolicy 검증 (dev EKS)

prod 오버레이의 per-svc NetworkPolicy(`apps/<svc>/overlays/prod/netpol.yaml`)를 **dev EKS에서 먼저 검증**한 뒤 prod에 적용하기 위한 절차. (작성 시점에 dev EKS 미프로비저닝 — 클러스터 생성 후 수행.)

## 정책 요약
per-svc NetworkPolicy(podSelector=해당 svc):
- **Ingress**: 같은 네임스페이스 파드(gateway·타 svc)에서 svc 포트(8080, learning-ai 8090)만 허용 → 외부/타 ns 직접 ingress 차단
- **Egress**: ① kube-dns(53) ② 같은 ns inter-svc ③ VPC `10.0.0.0/16`의 RDS(5432)/ElastiCache(6379)/MSK(9092,9094)/OpenSearch(443) ④ 외부 HTTPS(443, VPC·메타데이터 169.254.169.254 제외 — Stripe/OAuth/OpenAI/AWS API)
- 그 외 ingress/egress는 암묵적 deny

## ⚠️ 사전 필수: NetworkPolicy enforcement 활성 확인
**EKS Amazon VPC CNI는 NetworkPolicy를 기본으로 강제하지 않는다.** 정책 컨트롤러가 꺼져 있으면 netpol이 **조용히 무시**된다(차단도 안 되고 장애도 안 남). 검증 전 반드시 확인:

```bash
# VPC CNI NetworkPolicy 컨트롤러 활성 여부
kubectl -n kube-system get ds aws-node -o jsonpath='{.spec.template.spec.containers[*].args}' | tr ',' '\n' | grep -i network-policy
kubectl -n kube-system get ds aws-node -o yaml | grep -i "ENABLE_NETWORK_POLICY"   # "true" 여야 함
# 또는 Calico 애드온 사용 시
kubectl -n kube-system get ds | grep -i calico
```
- 비활성이면: `aws eks update-addon ... --configuration-values '{"enableNetworkPolicy":"true"}'` 또는 VPC CNI 환경변수 `ENABLE_NETWORK_POLICY=true` 후 검증.
- enforcement가 꺼진 채로는 "통과" 결과가 무의미하니 반드시 켜고 검증.

## 검증 절차 (dev, namespace=synapse-dev)

> dev 오버레이엔 현재 netpol이 없으므로, **임시로 prod netpol을 dev 네임스페이스에 적용해 검증**하거나(아래), dev 오버레이에도 동일 netpol을 추가해 검증한다. 검증 후 임시 적용분은 제거.

```bash
# 0) 적용 전 베이스라인 — 전 워크로드 Ready 확인
kubectl -n synapse-dev get pods

# 1) prod netpol을 dev에 임시 렌더·적용 (ipBlock 10.0.0.0/16은 dev VPC와 동일하다고 가정; 다르면 dev VPC CIDR로 치환)
for s in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  kubectl kustomize apps/$s/overlays/prod | yq 'select(.kind=="NetworkPolicy")' | \
    kubectl -n synapse-dev apply -f -
done
kubectl -n synapse-dev get networkpolicy

# 2) 핵심: egress가 막혀 앱이 죽지 않는지 (가장 위험한 부분)
#    파드 재시작 후 DB/Kafka/OpenSearch 연결 정상 = egress 허용목록 정확
kubectl -n synapse-dev rollout restart deploy/platform-svc
kubectl -n synapse-dev rollout status deploy/platform-svc --timeout=300s
kubectl -n synapse-dev logs deploy/platform-svc | grep -iE "Connection refused|timed out|UnknownHost|could not be established" | head
#    위 에러가 없고 Ready면 egress OK. 있으면 누락된 egress 대상(포트/CIDR) 추가.

# 3) ingress: 같은 ns(gateway)에서 도달 O, 타 ns에서 직접 도달 X
kubectl -n synapse-dev exec deploy/gateway -- curl -s -m5 -o /dev/null -w "%{http_code}\n" http://platform-svc/actuator/health   # 200 기대
kubectl -n default run probe --rm -it --image=curlimages/curl --restart=Never -- \
  curl -s -m5 -o /dev/null -w "%{http_code}\n" http://platform-svc.synapse-dev.svc.cluster.local:80   # 차단(000) 기대

# 4) 외부 HTTPS(Stripe/OAuth) 도달 — 앱이 결제/로그인 흐름에서 외부 호출 성공하는지 기능 확인
#    (gateway 경유 결제/소셜로그인 e2e 또는 svc 로그에서 외부 호출 에러 부재 확인)

# 5) 기능 스모크: gateway 경유 주요 API + Kafka 이벤트 왕복 1건
```

## 통과 기준
- 전 워크로드 Ready 유지(egress 허용목록이 DB/Kafka/OpenSearch/외부 HTTPS를 안 끊음)
- gateway→svc 200, 타 ns→svc 차단(000)
- 결제/로그인 등 외부 HTTPS 호출 정상
- Kafka 이벤트 왕복 정상

## 롤백
```bash
kubectl -n synapse-dev delete networkpolicy -l app.kubernetes.io/part-of=synapse
```
prod 적용 후 문제 시: `apps/<svc>/overlays/prod/kustomization.yaml`의 `resources`에서 `- netpol.yaml` 제거 → 재 sync, 또는 `kubectl -n synapse-prod delete networkpolicy <name>`.

## 알려진 한계 / 후속
- ingress가 "같은 ns 전체 허용"이라 gateway 외 svc도 서로 접근 가능. 더 조이려면 `from`을 gateway 라벨로 한정(단 inter-svc REST 흐름 매핑 필요).
- 외부 egress가 `0.0.0.0/0:443`(VPC 제외)이라 넓음. 보안 강화 시 Stripe/OAuth/OpenAI IP 레인지로 좁히되 IP 변동 리스크 고려(또는 egress 프록시).
- gateway는 현재 어느 ApplicationSet에도 없어 prod 미배포 — gateway용 netpol은 배포 경로 확정 후.

## B4 — ingress 호출자 한정 + 외부443 차등 (2026-06-03)

per-svc netpol을 cookie-cutter(ns 전체 ingress + 전 서비스 외부443)에서 호출 그래프 기반으로 조임:
- ingress `from`: platform←gateway,learning-ai / engagement←gateway / knowledge←gateway /
  learning-card←gateway,learning-ai / learning-ai←knowledge-svc.
- 외부 0.0.0.0/0:443: platform·learning-ai만 유지, engagement·knowledge·learning-card 제거.
- intra-ns egress(`podSelector {}`)·VPC 데이터스토어 egress는 보수적으로 유지.

### EKS 프로비저닝 시 확인
- **gateway 의존성(B1)**: ingress가 `app.kubernetes.io/name: gateway` 라벨 의존. gateway가 prod에
  배포되어야 공개 API 경로가 열림. gateway 파드 라벨이 정확히 그 값인지 확인.
- **외부443 제거 영향**: engagement/knowledge/learning-card가 향후 AWS SDK(CloudWatch/S3/SQS) 등
  외부 호출을 추가하면 차단됨 → 해당 netpol에 외부443 재추가 또는 VPC 엔드포인트 사용.
- **VPC CNI 정책 컨트롤러** 활성 선행. 미활성 시 정책 무시.
