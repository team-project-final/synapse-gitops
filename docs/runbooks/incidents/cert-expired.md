# Incident: TLS 인증서 만료

> 대상 스택: **ALB + self-signed ACM import** (cert-manager 미도입 — 2026-06-05 W5 클리어 설계 결정)
> 관련 자산: `infra/ingress/nipio/*.yaml`, `scripts/gen-nipio-selfsigned.sh`, `.nipio-certs/`(gitignore)
> ⚠️ ACM **import 인증서는 자동 갱신이 없다** — 만료는 "발생하는" 장애가 아니라 "예정된" 장애다.

## 증상

- `curl --cacert .nipio-certs/ca.crt https://argocd.<IP>.nip.io` → `certificate has expired`
- 브라우저 인증서 만료 경고 / ALB 리스너의 인증서 오류
- GitHub webhook 전송 실패 (TLS 검증 거부)

## 진단

```bash
# 1. 실제 서빙 중인 인증서 만료일
openssl s_client -connect argocd.<IP>.nip.io:443 -servername argocd.<IP>.nip.io </dev/null 2>/dev/null \
  | openssl x509 -noout -dates
# 2. ACM 쪽 만료일 대조
aws acm list-certificates --region ap-northeast-2 \
  --query 'CertificateSummaryList[].{arn:CertificateArn,domain:DomainName,exp:NotAfter}'
aws acm describe-certificate --certificate-arn <ARN> --query 'Certificate.NotAfter'
# 3. ingress가 어떤 ARN을 쓰는지
kubectl get ingress -A -o yaml | grep certificate-arn
```

## 조치

### A. nip.io ALB 인증서 (주 경로)

```bash
# 1. 현재 ALB DNS 확인
kubectl get ingress -A   # ADDRESS 컬럼
# 2. 재발급 + ACM 재임포트 (새 ARN 출력)
bash scripts/gen-nipio-selfsigned.sh <ALB_DNS>   # → CERT_ARN=arn:aws:acm:...
# 3. ingress의 certificate-arn 교체
#    - 상시 운영 중이면: infra/ingress/nipio/*.yaml 수정 → PR → 머지 → sync
#    - 윈도우(폐기 전제) 중이면: kubectl annotate 로 직접 교체 후 윈도우 종료 시 destroy
# 4. 검증
curl --cacert .nipio-certs/ca.crt https://argocd.<IP>.nip.io   # 200 + 체인 유효
```

> ALB IP가 바뀌었으면 nip.io 호스트도 무효 — 스크립트가 새 IP 기준 SAN으로 재생성하므로 ingress의 host도 함께 치환한다.

### B. ArgoCD NLB self-signed (W1 유산 경로 사용 시)

기본 접근은 SSM 터널 + `--insecure`라 외부 TLS 비의존. NLB 노출을 유지 중인 경우에만:

```bash
kubectl delete secret argocd-server-tls -n argocd   # 재생성 트리거 (자체 생성 경로)
kubectl rollout restart deploy/argocd-server -n argocd
```

### C. 만료된 구 인증서 정리

```bash
aws acm delete-certificate --certificate-arn <OLD_ARN>   # ingress 참조 해제 후
```

## 에스컬레이션 기준

- 재발급 후에도 체인 검증 실패 (SAN/IP 불일치 반복) → L2
- 공인 인증서(실 도메인) 전환 결정 필요 시 → team-lead (비용·도메인 확보 결정)

## 회피 방법

- **만료 30일 전 점검**: ACM `NotAfter` 확인을 윈도우 Phase 0 체크리스트에 포함
- nip.io self-signed는 **윈도우 1회성·폐기 전제** — 장기 운영 전환 시 실 도메인 + 공인 ACM으로 교체 (TASK Step 9 이월 항목)
- (후보) CloudWatch Events + ACM 만료 알람 → Slack — 실 도메인 전환 시 도입

## 사후 점검

- [ ] 새 ARN이 git의 ingress 매니페스트와 일치하는지 (윈도우 외 상시 운영 시)
- [ ] `.nipio-certs/` 로컬 파일이 커밋되지 않았는지 (`git status` — gitignore 확인)
- [ ] webhook 외부 도달 재검증 (GitHub ping → `/api/webhook` 200)
