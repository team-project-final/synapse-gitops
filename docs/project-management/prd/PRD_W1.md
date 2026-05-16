# PRD: W1 (synapse-gitops)

> **기간**: 2026-05-12 ~ 2026-05-16
> **트랙**: gitops
> **담당**: @VelkaressiaBlutkrone

이 주차의 GitOps 트랙 요구사항. 다른 트랙용 요구사항은 documents 레포의 `PRD_W1.md`에 통합되어 있고, 여기서는 gitops 트랙(`FR-GO-*`) 요구사항만 정의한다.

## 요구사항 목록

| 요구사항 ID | 제목 | 우선순위 | 검수 기준 |
|---|---|---|---|
| FR-GO-101 | EKS에 ArgoCD HA 모드로 설치 | P0 | argocd-server replica 3개 Running, CLI 로그인 성공 |
| FR-GO-102 | ArgoCD UI를 외부에 TLS로 노출 | P0 | argocd.<도메인> HTTPS 접속, 인증서 valid |
| FR-GO-103 | 5개 앱을 ApplicationSet으로 일괄 정의 | P0 | git push 시 5개 Application 자동 등록 |
| FR-GO-104 | validate-manifests CI에 kubeconform 추가 | P1 | 잘못된 apiVersion PR → CI 실패 |
| FR-GO-105 | main 브랜치 보호 + 필수 CI 체크 | P1 | CI 미통과 시 머지 차단 |
