# Frontend readOnlyRootFilesystem 하드닝 설계

> **작성일**: 2026-06-07
> **상태**: 설계 승인 + minikube 검증 완료
> **대상**: `synapse-gitops/apps/frontend/base/deployment.yaml`

## 배경 / 감사 결과

local-k8s frontend 매니페스트를 fleet 하드닝 패턴과 비교 감사:

| 항목 | fleet 현황 | frontend |
|---|---|---|
| 무중단 롤아웃·프로브·non-root securityContext | 백엔드 공통 | 이미 적용 ✅ |
| NetworkPolicy / HPA | **prod overlay 5개 svc 전용** (local·gateway·frontend 없음) | local-k8s 갭 아님 |
| readOnlyRootFilesystem | 어느 앱도 미사용 | 미적용 → 본 설계 대상 |

결론: local-k8s frontend는 이미 일관·하드닝돼 있고 NetPol/HPA는 prod 전용. 유일하게 의미 있는 추가 방어심화는 **정적 파일 서버(nginx)에 대한 루트 파일시스템 불변화**.

## 변경

`apps/frontend/base/deployment.yaml` 컨테이너 securityContext에 `readOnlyRootFilesystem: true` 추가.
nginx-unprivileged 런타임 쓰기 경로를 `emptyDir`로 제공:
- `/tmp` — pid(`/tmp/nginx.pid`) 및 임시 파일
- `/var/cache/nginx` — nginx 캐시/임시 디렉터리

base 변경이므로 AWS(dev/staging/prod overlay)·local-k8s 공통 적용. frontend가 fleet에서 readOnlyRootFilesystem을 선도.

## 근거

- 정적 SPA 서버는 런타임에 디스크 쓰기가 불필요 → 루트FS 불변은 컨테이너 변조·악성코드 드롭 방어심화(defense in depth).
- nginx-unprivileged는 이미 비루트(uid 101)이므로, 쓰기 경로만 emptyDir로 격리하면 안전하게 readOnly 가능.

## 검증 (minikube, 완료)

- `kubectl apply -k local-k8s/apps/frontend` → 파드 `1/1 Running`(쓰기 경로 부족 시 CrashLoop인데 정상 기동 = 마운트 충분).
- `/healthz`·`/`·딥링크 모두 200, `<title>Synapse</title>` 서빙 확인.
- 파드 내 `/`에 쓰기 시도 → 거부(`Read-only file system`) = readOnlyRootFilesystem 실제 강제 확인.

## 범위 밖 (의도적 제외)

- NetworkPolicy/HPA: prod overlay 전용 패턴 → frontend prod 패리티는 별도 과제.
- 다른 svc로의 readOnlyRootFilesystem 확산: JVM 앱은 쓰기 경로(tmp, 로그)가 많아 별도 검토 필요.
