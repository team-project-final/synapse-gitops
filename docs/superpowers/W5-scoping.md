# W5 스코핑 초안 (2026-06-02 작성)

> W4 잔여 2일 작업(MSK terraform 편입 TLS-only + 정리·마감)에서 도출된 백로그/이월 정리.
> 관련: spec `2026-06-02-w4-remaining-msk-terraform-tls-design.md`, 기존 `docs/runbooks/w5-stabilize-runbook.md`.

## 백로그 (W4에서 의도적 이월/강등)

- **A안 SASL/IAM 전환**: `msk.tf` `client_authentication.sasl.iam=true` + 5개 서비스 `aws-msk-iam-auth` 의존성·IRSA/IAM Policy 매트릭스. **타 owner(서비스 코드) 조율 필요**. W4는 B(TLS-only) 확정 — A는 보안 정석이나 캡스톤 회수가치 낮아 이월.
- **브로커 주소 자동화**: 재apply마다 변동하는 MSK 브로커 DNS → 현재 5개 service overlay에 하드코딩(`KAFKA_BROKERS`, 5×3=15곳). `terraform output` → 단일 ConfigMap 소싱으로 전환해 하드코딩 제거. (code review Minor #4)
- **kafka-topics 모듈 lock 재현성**: `.terraform.lock.hcl`이 repo-wide gitignore라 미커밋 → provider 핀은 `~> 0.13` 제약식에만 의존. bastion 등 타 플랫폼 재현성 위해 `terraform providers lock -platform=linux_amd64` 후 lock 커밋(gitignore 예외) 검토. (code review Observation #6)
- **실도메인 의존 3항목**: ACM ARN 매핑·DNS 레코드·ArgoCD UI TLS·webhook 외부 도달 (W1 이월, 실 도메인 확보 시). port-forward 대체 중.
- **image-updater 측정 항목**: 평균 반영시간(목표 5분)·잘못된 이미지 → 이전 태그 롤백 케이스 (W2 이월, 라이브 재기동 시).

## team-lead 의존 (사람)

- 권한모델(ArgoCD RBAC `role:prod-deployer` + `gitops-admin`) 사인오프 — 패키지 준비 완료.
- RTO 30분 / RPO 1시간 사인오프 — 패키지 준비 완료.

## 후보 주제

- (W5 착수 시 brainstorming으로 구체화 — `w5-stabilize-runbook.md` 선행 참조)
