# Cross-Repo Work Order — platform-svc staging 프로필

> **발행일**: 2026-05-27 (W3 Day2)
> **발행**: synapse-gitops (@VelkaressiaBlutkrone)
> **수신**: synapse-platform-svc (앱 트랙)
> **우선순위**: P0 (W3 staging 5/5 Healthy 차단 요인)

## 배경
A2 실 EKS 검증에서 staging은 **4/5 Healthy**였고, platform-svc만 Degraded였다.
원인은 platform-svc 앱에 `staging` Spring profile이 없어서다(cross-repo = 앱 레포 의존).
gitops 측 staging overlay(`apps/platform-svc/overlays/staging`)·ExternalSecret 경로
(`synapse/staging/platform-svc/*`)·ApplicationSet auto-sync는 이미 완비됨.

## 요청 사항
1. `application-staging.yml`(또는 `application.yml`의 `staging` 프로필) 추가:
   - DB/Redis/Kafka 연결을 staging ExternalSecret 키와 정합(`spring.data.redis.*` relaxed-binding 키 — gitops main 6ea673a 참조).
   - `ddl-auto`/Flyway는 dev와 동일 전략(현재 그린 상태 유지).
2. staging 프로필로 기동 시 `/actuator/health` → UP.
3. ECR 이미지에 staging 프로필 포함 빌드 → 태그 push.

## 검수 기준
- gitops staging ApplicationSet sync 후 platform-svc staging **Synced + Healthy** (5/5 달성).
- 검증은 gitops 조건부 EKS 사이클(W3 Day4 또는 W4)에서 수행.

## 참고
- gitops staging overlay: `apps/platform-svc/overlays/staging/kustomization.yaml`
- Redis 키 수정 이력: gitops main `7be0998`, `93150f2`
