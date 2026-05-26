# Synapse Docs Portal

synapse-gitops 문서(runbook / handoff / 개발 가이드)를 검색·브라우즈하는 Flutter Web 포털.

## 구조

- `lib/pages/` — home / search / dashboard / doc / runbook / onboarding
- `lib/widgets/` — 공통 위젯 (markdown viewer, sidebar, progress bar 등)
- `scripts/build_docs.mjs` — Markdown → JSON + 검색 인덱스 + AI 요약 빌드 (Node)

## 로컬 실행

```bash
# 1) 문서 JSON 생성 (synapse-gitops + synapse-shared 문서 수집)
cd scripts && npm ci && node build_docs.mjs

# 2) 포털 실행
cd .. && flutter pub get && flutter run -d chrome
```

## 배포

main 푸시 시 `.github/workflows/deploy-pages.yml`이 문서 JSON을 빌드하고
Flutter Web을 GitHub Pages로 자동 배포한다.
