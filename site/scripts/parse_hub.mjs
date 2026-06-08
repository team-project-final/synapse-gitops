// HANDOFF_HUB.md "환경별 서비스 상태" 표만 구조화 파싱. 실패 시 빈 결과 반환(폴백).

const STATUS_MAP = {
  '✅': 'healthy',
  '🔄': 'pending',
  '⚠️': 'degraded',
  '🔴': 'down',
  '⏳': 'planned',
  '—': 'na',
};

function splitRow(line) {
  return line.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map((s) => s.trim());
}

function parseCell(raw) {
  const text = (raw ?? '').trim();
  if (text === '' || text === '—' || text === '-') return { status: 'na', label: '' };
  for (const [emoji, status] of Object.entries(STATUS_MAP)) {
    if (text.startsWith(emoji)) {
      const label = text.slice(emoji.length).replace(/\*\*/g, '').trim();
      return { status, label };
    }
  }
  return { status: 'na', label: text.replace(/\*\*/g, '').trim() };
}

export function parseHubStatusTable(markdown) {
  const lines = markdown.split('\n');
  const start = lines.findIndex((l) => /^#{2,4}\s+환경별 서비스 상태/.test(l));
  if (start === -1) return { envs: [], rows: [] };

  let header = -1;
  for (let j = start + 1; j < lines.length; j++) {
    if (lines[j].trim().startsWith('|')) { header = j; break; }
    if (/^#{1,4}\s/.test(lines[j])) break; // 다음 헤딩 전 표 없음
  }
  if (header === -1) return { envs: [], rows: [] };

  const headerCells = splitRow(lines[header]);
  if (headerCells.length < 2) return { envs: [], rows: [] };
  const envs = headerCells.slice(1);

  const rows = [];
  for (let j = header + 2; j < lines.length; j++) { // header+1 = 구분선
    const line = lines[j];
    if (!line.trim().startsWith('|')) break; // 표 종료
    const cells = splitRow(line);
    const service = (cells[0] ?? '').replace(/\*\*/g, '').trim();
    if (!service) continue;
    const cellData = envs.map((env, k) => {
      const { status, label } = parseCell(cells[k + 1]);
      return { env, status, label };
    });
    rows.push({ service, cells: cellData });
  }
  return { envs, rows };
}

export function buildHubModel(markdown, lastModified) {
  const titleLine = markdown.split('\n').find((l) => l.startsWith('# '));
  const { envs, rows } = parseHubStatusTable(markdown);
  return {
    title: titleLine ? titleLine.replace(/^#\s+/, '').trim() : 'Handoff Hub',
    lastUpdated: lastModified ?? '',
    envs,
    statusTable: rows,
    bodyMarkdown: markdown,
  };
}
