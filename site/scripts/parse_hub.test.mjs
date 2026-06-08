import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseHubStatusTable, buildHubModel } from './parse_hub.mjs';

const SAMPLE = `# Synapse 통합 핸드오프 허브

> 최종 갱신: 2026-06-08

## 1. 프로젝트 상태 대시보드

### 환경별 서비스 상태

> 블록쿼트 노이즈 라인

| 서비스 | 로컬 compose | dev (EKS) | staging | prod |
|---|---|---|---|---|
| platform-svc | ✅ Healthy | ✅ **5/5(06-08)** | ✅ 5/5(06-08, CrashLoop 해소) | ⏳ W5 |
| gateway | ✅ Healthy | ✅ 5/5(06-08) | — | ⏳ W5 |

> 표 뒤 블록쿼트

### 인프라 상태

| 컴포넌트 | 상태 |
|---|---|
| EKS | ✅ ACTIVE |
`;

test('parseHubStatusTable: envs + rows 파싱', () => {
  const { envs, rows } = parseHubStatusTable(SAMPLE);
  assert.deepEqual(envs, ['로컬 compose', 'dev (EKS)', 'staging', 'prod']);
  assert.equal(rows.length, 2);
  assert.equal(rows[0].service, 'platform-svc');
  assert.equal(rows[0].cells.length, 4);
});

test('parseHubStatusTable: 선두 이모지 status 매핑 + 라벨 정리', () => {
  const { rows } = parseHubStatusTable(SAMPLE);
  const platformDev = rows[0].cells[1]; // dev (EKS)
  assert.equal(platformDev.env, 'dev (EKS)');
  assert.equal(platformDev.status, 'healthy');
  assert.equal(platformDev.label, '5/5(06-08)'); // ✅ 와 ** 제거
});

test('parseHubStatusTable: planned/na 매핑', () => {
  const { rows } = parseHubStatusTable(SAMPLE);
  assert.equal(rows[0].cells[3].status, 'planned'); // ⏳ W5
  assert.equal(rows[1].cells[2].status, 'na');      // — (gateway staging)
});

test('parseHubStatusTable: 인프라 표는 잡지 않음(첫 표만)', () => {
  const { rows } = parseHubStatusTable(SAMPLE);
  assert.ok(rows.every((r) => r.service !== 'EKS'));
});

test('parseHubStatusTable: 섹션 없으면 빈 결과', () => {
  const { envs, rows } = parseHubStatusTable('# 제목\n\n표 없음');
  assert.deepEqual(envs, []);
  assert.deepEqual(rows, []);
});

test('buildHubModel: title/lastUpdated/bodyMarkdown 포함', () => {
  const m = buildHubModel(SAMPLE, '2026-06-08');
  assert.equal(m.title, 'Synapse 통합 핸드오프 허브');
  assert.equal(m.lastUpdated, '2026-06-08');
  assert.equal(m.statusTable.length, 2);
  assert.ok(m.bodyMarkdown.includes('환경별 서비스 상태'));
});
