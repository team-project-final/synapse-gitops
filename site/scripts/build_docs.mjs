import fs from 'fs';
import path from 'path';
import { createHash } from 'crypto';
import matter from 'gray-matter';
import { buildHubModel } from './parse_hub.mjs';

const WORKSPACE = path.resolve('../../../');
const GITOPS_DOCS = path.join(WORKSPACE, 'synapse-gitops/docs/runbooks');
const SHARED_DOCS = path.join(WORKSPACE, 'synapse-shared/docs');
const OUTPUT_DIR = path.resolve('../assets/docs');

const CATEGORY_MAP = [
  { pattern: /^gitops\/docs\/runbooks/, category: 'infra' },
  { pattern: /^shared\/docs\/guides/, category: 'guides' },
  { pattern: /^shared\/docs\/project-management/, category: 'management' },
  { pattern: /^shared\/docs\/(prd|superpowers)/, category: 'prd' },
  { pattern: /^shared\/docs\/rules/, category: 'rules' },
  { pattern: /^shared\/docs\/fix-requests/, category: 'fix-requests' },
];

const TAG_KEYWORDS = [
  'kafka', 'argocd', 'terraform', 'eks', 'rds', 'msk', 'redis', 'opensearch',
  'docker', 'helm', 'staging', 'dev', 'prod', 'security', 'tls', 'acl',
  'flyway', 'gradle', 'ci', 'cd', 'deploy', 'rollback', 'e2e', 'avro', 'schema',
];

const STOP_PARTICLES = ['은', '는', '이', '가', '을', '를', '의', '에', '로', '와', '과', '도', '만', '까지'];

const CACHE_FILE = path.resolve('.summary-cache.json');

function collectMarkdownFiles() {
  const files = [];

  if (fs.existsSync(GITOPS_DOCS)) {
    for (const f of fs.readdirSync(GITOPS_DOCS)) {
      if (f.endsWith('.md')) {
        files.push({ absPath: path.join(GITOPS_DOCS, f), relKey: `gitops/docs/runbooks/${f}` });
      }
    }
  }

  function walk(dir, relBase) {
    if (!fs.existsSync(dir)) return;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      const rel = `${relBase}/${entry.name}`;
      if (entry.isDirectory()) walk(full, rel);
      else if (entry.name.endsWith('.md')) files.push({ absPath: full, relKey: rel });
    }
  }
  walk(SHARED_DOCS, 'shared/docs');

  return files;
}

function categorize(relKey) {
  for (const { pattern, category } of CATEGORY_MAP) {
    if (pattern.test(relKey)) return category;
  }
  return 'etc';
}

function slugify(relKey) {
  return path.basename(relKey, '.md')
    .toLowerCase()
    .replace(/[^a-z0-9가-힣_-]/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '');
}

function extractToc(body) {
  const toc = [];
  for (const line of body.split('\n')) {
    const m = line.match(/^(#{2,3})\s+(.+)/);
    if (m) {
      const level = m[1].length;
      const text = m[2].trim();
      const anchor = text
        .toLowerCase()
        .replace(/[^a-z0-9가-힣\s-]/g, '')
        .replace(/\s+/g, '-');
      toc.push({ level, text, anchor });
    }
  }
  return toc;
}

function extractTags(body) {
  const lower = body.toLowerCase();
  const matched = TAG_KEYWORDS.filter(kw => {
    const regex = new RegExp(`\\b${kw.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'gi');
    return (lower.match(regex) || []).length >= 3;
  });
  return matched.slice(0, 5);
}

function extractCompletionRate(body) {
  const checked = (body.match(/- \[x\]/gi) || []).length;
  const unchecked = (body.match(/- \[ \]/g) || []).length;
  const total = checked + unchecked;
  if (total === 0) return null;
  return Math.round((checked / total) * 100);
}

function getLastModified(absPath) {
  try {
    return fs.statSync(absPath).mtime.toISOString().slice(0, 10);
  } catch { return null; }
}

function hashContent(text) {
  return createHash('md5').update(text).digest('hex');
}

function loadCache() {
  try { return JSON.parse(fs.readFileSync(CACHE_FILE, 'utf-8')); }
  catch { return {}; }
}

function saveCache(cache) {
  fs.writeFileSync(CACHE_FILE, JSON.stringify(cache, null, 2));
}

async function generateSummary(body, title) {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey || process.env.NO_AI === '1') return '';

  const prompt = `다음 기술 문서를 2~3줄로 요약해줘. 핵심 목적, 대상, 결과물을 포함해.\n\n제목: ${title}\n\n${body.slice(0, 4000)}`;

  try {
    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 200,
        messages: [{ role: 'user', content: prompt }],
      }),
    });

    if (!res.ok) {
      console.warn(`  AI summary failed for "${title}": ${res.status}`);
      return '';
    }

    const data = await res.json();
    return data.content?.[0]?.text || '';
  } catch (e) {
    console.warn(`  AI summary error for "${title}": ${e.message}`);
    return '';
  }
}

function buildSearchIndex(docs) {
  const index = {};
  for (const doc of docs) {
    // strip code blocks before indexing, title gets 3x weight
    const strippedBody = doc.body.replace(/```[\s\S]*?```/g, '').replace(/`[^`]+`/g, '');
    const text = `${doc.title} ${doc.title} ${doc.title} ${strippedBody}`;
    const tokens = text
      .split(/[\s,.;:!?()\[\]{}|/\\<>"'`~#*_=+\-\n\r\t]+/)
      .filter(Boolean);

    for (const raw of tokens) {
      let token = raw.toLowerCase();
      // strip Korean particles
      for (const p of STOP_PARTICLES) {
        if (token.endsWith(p) && token.length > p.length + 1) {
          token = token.slice(0, -p.length);
          break;
        }
      }
      if (token.length < 3 || token.length > 30) continue;
      // skip pure numbers and common noise
      if (/^\d+$/.test(token)) continue;
      if (!index[token]) index[token] = [];
      if (!index[token].find(e => e.s === doc.slug)) {
        index[token].push({ s: doc.slug, c: doc.category });
      }
    }
  }
  // prune tokens appearing in 80%+ of docs (too common to be useful)
  const threshold = Math.floor(docs.length * 0.8);
  for (const token of Object.keys(index)) {
    if (index[token].length > threshold) {
      delete index[token];
    }
  }

  return index;
}

async function main() {
  const files = collectMarkdownFiles();
  console.log(`Found ${files.length} markdown files`);

  // Create output dirs
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  for (const cat of ['infra', 'guides', 'management', 'prd', 'rules', 'fix-requests', 'etc']) {
    fs.mkdirSync(path.join(OUTPUT_DIR, cat), { recursive: true });
  }

  const cache = loadCache();
  const indexEntries = [];
  const allDocs = [];
  let summaryCount = 0;

  for (const { absPath, relKey } of files) {
    const raw = fs.readFileSync(absPath, 'utf-8');
    const { data: frontmatter, content: body } = matter(raw);

    const slug = slugify(relKey);
    const category = categorize(relKey);
    const title = frontmatter.title
      || body.split('\n').find(l => l.startsWith('# '))?.replace(/^#\s+/, '')
      || slug;
    const source = relKey.startsWith('gitops') ? 'synapse-gitops' : 'synapse-shared';

    // AI summary with cache
    const contentHash = hashContent(body);
    let summary = '';
    if (cache[slug] && cache[slug].hash === contentHash) {
      summary = cache[slug].summary;
    } else {
      summary = await generateSummary(body, title);
      if (summary) summaryCount++;
      cache[slug] = { hash: contentHash, summary };
    }

    const doc = {
      slug,
      title,
      category,
      source,
      tags: extractTags(body),
      summary,
      metadata: {
        lastUpdated: getLastModified(absPath),
        status: 'active',
        completionRate: extractCompletionRate(body),
      },
      toc: extractToc(body),
      body,
    };

    allDocs.push(doc);

    const docPath = path.join(OUTPUT_DIR, category, `${slug}.json`);
    fs.writeFileSync(docPath, JSON.stringify(doc, null, 2));

    indexEntries.push({
      slug: doc.slug,
      title: doc.title,
      category: doc.category,
      source: doc.source,
      tags: doc.tags,
      summary: doc.summary,
      metadata: doc.metadata,
    });

    if (relKey === 'shared/docs/project-management/HANDOFF_HUB.md') {
      const hubModel = buildHubModel(body, getLastModified(absPath));
      fs.writeFileSync(
        path.join(OUTPUT_DIR, 'hub.json'),
        JSON.stringify(hubModel, null, 2),
      );
      console.log(`Wrote hub.json (statusTable rows: ${hubModel.statusTable.length})`);
    }
  }

  saveCache(cache);

  // Write index
  fs.writeFileSync(path.join(OUTPUT_DIR, 'index.json'), JSON.stringify(indexEntries, null, 2));

  // Write search index
  const searchIndex = buildSearchIndex(allDocs);
  const searchJson = JSON.stringify(searchIndex);
  fs.writeFileSync(path.join(OUTPUT_DIR, 'search-index.json'), searchJson);

  const sizeKB = (Buffer.byteLength(searchJson) / 1024).toFixed(1);
  console.log(`Built ${indexEntries.length} docs, search index ${sizeKB}KB`);
  if (summaryCount > 0) console.log(`Generated ${summaryCount} new AI summaries`);
}

main().catch(console.error);
