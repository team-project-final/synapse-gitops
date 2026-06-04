# CLAUDE.md

## Design System
시각·UI 결정 전에 항상 `DESIGN.md`를 먼저 읽는다.
폰트 선택, 색, 간격, 미감 방향은 모두 거기에 정의되어 있다.
명시적 사용자 승인 없이 벗어나지 않는다.
특히: 색은 **의미가 잠겨 있다**(레이어·메서드·서비스) — 임의로 다시 칠하지 않는다.
폰트는 `docs/*.html`에서 **base64 data-URI로 임베드**한다 — CDN 및 외부 woff2 파일참조 금지(file://은 unique origin이라 외부 폰트가 차단됨).
QA 시 `DESIGN.md`와 어긋나는 코드를 플래그한다.
