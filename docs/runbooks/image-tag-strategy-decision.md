# 이미지 태그 전략 결정 (SHA ↔ semver) — 팀 입력물

> 작성: 2026-06-10 · 상태: **팀 결정 대기** · 관련: #165 · #157 · #126

## 문제
shared `deploy-service.yml`이 dev 오버레이에 **SHA를 write-back**(매 배포) → 두 부작용:
1. ArgoCD Image Updater `semver` 전략이 SHA를 `Invalid Semantic Version`으로 **skip**(learning-ai/card 자동업데이트 안 됨).
2. main이 매 배포마다 churn → 피처 PR이 ruleset strict로 반복 **BEHIND**(2026-06-10 PR #171 2회). → **strict 완화(#165)로 즉시 해소함**. 본 문서는 태깅 일관성(IU 자동업데이트)용 후속 결정.

## 옵션
| 옵션 | 내용 | 범위 | 트레이드오프 |
|------|------|------|-------------|
| (a) 임시 재태그 | ECR SHA→1.0.0 재태그 + overlay 정정 | gitops 1회 | 다음 배포에 회귀 → 무의미 |
| (b) deploy-service semver화 | shared 파이프라인이 릴리스시 semver 태깅 | **크로스레포**(shared, 팀) | 근본·처닝 격감, 단 조율 필요(#126류) |
| (c) IU digest 전환 | image-updater 전략 `digest`/`newest-build` + dev 오버레이 digest | **gitops 단독** | mutable 태그 추적, semver 불필요. SHA write-back과 양립 |

## 권장
**(c) IU digest** — gitops 단독 적용 가능(크로스레포 불필요), SHA write-back과 충돌 없음. BEHIND 레이스는 strict 완화로 이미 해소됐으므로 (c)는 IU 자동업데이트 일관성 목적의 선택적 후속.

## 연계 후속
- learning-card staging + 6앱 dev 오버레이 태그 일괄 재정렬은 본 결정 후.
- **staging readiness 401**(`/actuator/health/readiness` 인증 요구) = 앱 레포 시큐리티 → 상세 핸드오프 이슈 **synapse-learning-svc#74** 생성 완료(gitops 직접 처리 안 함).
