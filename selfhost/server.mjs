// Munawib self-hosted server: runs the same Worker code on Node 22 with SQLite (node:sqlite) and HTTP/2 APNs.
import http from 'node:http';
import http2 from 'node:http2';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';

const ROOT = path.dirname(new URL(import.meta.url).pathname);
const DATA = process.env.DATA_DIR || path.join(ROOT, 'data');
fs.mkdirSync(DATA, { recursive: true });
const sqlite = new DatabaseSync(path.join(DATA, 'munawib.db'));
sqlite.exec('PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;');
const schemaFile = [path.join(ROOT, 'schema.sql'), path.join(ROOT, '../backend/schema.sql')].find(f => fs.existsSync(f));
sqlite.exec(fs.readFileSync(schemaFile, 'utf8'));
// idempotent migrations (columns added after v2.0)
for (const f of ['migrate_v21.sql', '../backend/migrate_v21.sql'].map(f => path.join(ROOT, f)).filter(f => fs.existsSync(f)).slice(0, 1))
  for (const q of fs.readFileSync(f, 'utf8').split(';').map(x => x.trim()).filter(Boolean)) { try { sqlite.exec(q); } catch {} }

// --- D1-compatible shim ---
const norm = v => v === undefined ? null : typeof v === 'boolean' ? (v ? 1 : 0) : v;
const plain = r => r ? { ...r } : r;
class Stmt {
  constructor(sql, args = []) { this.sql = sql; this.args = args; }
  bind(...a) { return new Stmt(this.sql, a.map(norm)); }
  _p() { return sqlite.prepare(this.sql); }
  async first(col) { const r = plain(this._p().get(...this.args)); return r == null ? null : col ? r[col] : r; }
  async all() { return { results: this._p().all(...this.args).map(plain), success: true }; }
  async run() { const r = this._p().run(...this.args); return { success: true, meta: { changes: Number(r.changes), last_row_id: Number(r.lastInsertRowid) } }; }
  async raw() { return this._p().all(...this.args).map(r => Object.values(r)); }
}
const DB = {
  prepare: sql => new Stmt(sql),
  async batch(list) { sqlite.exec('BEGIN'); try { const out = []; for (const s of list) out.push(await s.run()); sqlite.exec('COMMIT'); return out; } catch (e) { sqlite.exec('ROLLBACK'); throw e; } },
  async exec(sql) { sqlite.exec(sql); return { count: 1 }; },
};

// --- secrets / env ---
const secretFile = path.join(DATA, 'jwt_secret');
if (!process.env.JWT_SECRET && !fs.existsSync(secretFile)) fs.writeFileSync(secretFile, crypto.randomBytes(32).toString('hex'), { mode: 0o600 });
let apnsKey = process.env.APNS_KEY || '';
if (!apnsKey && process.env.APNS_KEY_FILE && fs.existsSync(process.env.APNS_KEY_FILE)) apnsKey = fs.readFileSync(process.env.APNS_KEY_FILE, 'utf8');
const env = {
  DB, RUNTIME: 'node',
  JWT_SECRET: process.env.JWT_SECRET || fs.readFileSync(secretFile, 'utf8').trim(),
  APNS_KEY: apnsKey || undefined, APNS_KEY_ID: process.env.APNS_KEY_ID, TEAM_ID: process.env.TEAM_ID,
  APNS_TOPIC: process.env.APNS_TOPIC || 'com.mohlab.munawib', OWNER_EMAIL: process.env.OWNER_EMAIL || '',
};

// --- APNs over HTTP/2 (Node fetch is HTTP/1.1 only) ---
const sessions = {};
globalThis.__apnsFetch = (url, init = {}) => new Promise((resolve, reject) => {
  const u = new URL(url);
  let s = sessions[u.origin];
  if (!s || s.closed || s.destroyed) { s = sessions[u.origin] = http2.connect(u.origin); s.on('error', () => delete sessions[u.origin]); }
  const req = s.request({ ':method': init.method || 'POST', ':path': u.pathname, ...(init.headers || {}) });
  let status = 0, buf = '';
  req.on('response', h => status = h[':status']);
  req.on('data', c => buf += c);
  req.on('end', () => resolve(new Response(buf || null, { status })));
  req.on('error', reject);
  req.end(init.body);
});

const { default: worker } = await import(process.env.WORKER_FILE || path.join(ROOT, 'worker.mjs'));
const ctx = { waitUntil: p => Promise.resolve(p).catch(e => console.error(e)), passThroughOnException() {} };

const PORT = Number(process.env.PORT || 8787);
http.createServer(async (req, res) => {
  try {
    const chunks = []; for await (const c of req) chunks.push(c);
    const host = req.headers['x-forwarded-host'] || req.headers.host || `localhost:${PORT}`;
    const proto = req.headers['x-forwarded-proto'] || 'http';
    const r = await worker.fetch(new Request(`${proto}://${host}${req.url}`, {
      method: req.method, headers: req.headers, body: ['GET', 'HEAD'].includes(req.method) ? undefined : Buffer.concat(chunks),
    }), env, ctx);
    res.writeHead(r.status, Object.fromEntries(r.headers));
    res.end(Buffer.from(await r.arrayBuffer()));
  } catch (e) { console.error(e); res.writeHead(500, { 'content-type': 'application/json' }); res.end('{"error":"internal"}'); }
}).listen(PORT, () => console.log(`Munawib self-hosted server on :${PORT}`));

// cron: every 5 minutes, same as Cloudflare
if (worker.scheduled) setInterval(() => worker.scheduled({ cron: '*/5 * * * *', scheduledTime: Date.now() }, env, ctx).catch(console.error), 5 * 60 * 1000);
