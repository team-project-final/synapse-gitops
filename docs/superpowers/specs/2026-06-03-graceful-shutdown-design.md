# Spring graceful shutdown — 설계 (2026-06-03)

## 배경

핸드오프 후속 finding B3. #98에서 무중단 배포를 위해 k8s 측(RollingUpdate maxUnavailable:0,
terminationGracePeriodSeconds:40, preStop sleep 5)은 적용했으나 **앱 레벨 graceful shutdown
(`server.shutdown: graceful`)이 부재**해 SIGTERM 시 진행 중 요청이 끊길 수 있다. 완전 무중단엔
앱이 in-flight 요청을 드레인하도록 graceful shutdown이 필요하다.

## 대상 / 비대상

**대상(5개 Spring Boot svc 레포):** synapse-gateway, synapse-platform-svc,
synapse-engagement-svc, synapse-knowledge-svc, synapse-learning-svc(learning-card).
모두 현재 `server.shutdown`·`spring.lifecycle.timeout-per-shutdown-phase` 미설정.

**비대상:** learning-ai(Python/uvicorn — graceful은 uvicorn `timeout-graceful-shutdown` +
SIGTERM 처리로 별도 메커니즘, 이번 범위 밖). k8s 매니페스트(이미 #98로 preStop·grace 적용).

## ⚠️ 실행 게이트

이 작업은 **svc 앱 레포 5개 편집·PR**이다. [[svc-repo-changes-need-confirmation]] 규칙에 따라
각 레포 실제 편집·커밋·푸시·PR **직전에 사용자 확인 필수**. 본 문서는 설계/계획 저장이며
실행은 다음 세션으로 이관.

## 변경 설계

각 서비스 `src/main/resources/application.yml`에 2가지 추가:
- `server.shutdown: graceful` — 톰캣/네티가 SIGTERM 시 새 요청 거부 + in-flight 드레인.
- `spring.lifecycle.timeout-per-shutdown-phase: 30s` — 드레인 최대 대기.

**타임 버짓 정합(이미 적용된 k8s와):** preStop sleep 5s(gateway 10s) + graceful drain ≤30s <
terminationGracePeriodSeconds 40s. 즉 LB에서 엔드포인트 제거(preStop) 후 드레인이 grace 안에 완료.
gateway는 preStop 10s라 drain 30s + 10s = 40s로 빠듯 → gateway는 timeout 20s 권장(아래 plan 반영).

프로파일: 기본 `application.yml`에 두어 전 환경 공통 적용(dev/prod 프로파일 오버라이드 불필요).

## 검증 계획

- 빌드: 각 레포 `./gradlew build`(또는 CI) 통과 — YAML 추가만이라 컴파일 영향 없음.
- 런타임(선택, minikube): 파드에 부하 중 `kubectl delete pod` → 진행 요청 200 유지 확인.
  #98 무중단 70/70 200 테스트 재활용 가능. 단 svc 레포 빌드+이미지 재배포 필요.
- 실제 무중단 효과는 EKS(롤링 업데이트)에서 최종 확인 — 태스크 A.

## 영향 / PR

- svc 레포 **5개 PR**(gateway/platform/engagement/knowledge/learning-card). 각 1파일(application.yml).
- gitops/매니페스트 변경 없음(k8s 측 #98 완료). learning-ai 별도(후속).
