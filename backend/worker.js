// Munawib API — Cloudflare Worker + D1 + APNs
const enc = new TextEncoder();
const b64u = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const b64uStr = (s) => b64u(enc.encode(s));
const fromB64u = (s) => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((s.length + 3) % 4)), c => c.charCodeAt(0));
const uid = () => crypto.randomUUID();
const now = () => Date.now();
const json = (d, s = 200) => new Response(JSON.stringify(d), { status: s, headers: { 'content-type': 'application/json; charset=utf-8', 'access-control-allow-origin': '*' } });
class HttpError extends Error { constructor(s, m) { super(m); this.status = s; } }
const need = (c, s, m) => { if (!c) throw new HttpError(s, m); };

async function hashPw(pw, saltB64) {
  const salt = saltB64 ? fromB64u(saltB64) : crypto.getRandomValues(new Uint8Array(16));
  const key = await crypto.subtle.importKey('raw', enc.encode(pw), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations: 100000 }, key, 256);
  return `pbkdf2$100000$${b64u(salt)}$${b64u(bits)}`;
}
async function verifyPw(pw, stored) {
  if (!stored) return false;
  const [, , salt, h] = stored.split('$');
  const again = (await hashPw(pw, salt)).split('$')[3];
  if (again.length !== h.length) return false;
  let r = 0; for (let i = 0; i < h.length; i++) r |= again.charCodeAt(i) ^ h.charCodeAt(i);
  return r === 0;
}
async function hmacKey(env) { return crypto.subtle.importKey('raw', enc.encode(env.JWT_SECRET), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']); }
async function signJWT(env, payload) {
  const h = b64uStr(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const p = b64uStr(JSON.stringify({ ...payload, exp: Math.floor(now() / 1000) + 60 * 60 * 24 * 30 }));
  const sig = await crypto.subtle.sign('HMAC', await hmacKey(env), enc.encode(`${h}.${p}`));
  return `${h}.${p}.${b64u(sig)}`;
}
async function verifyJWT(env, t) {
  const [h, p, s] = (t || '').split('.'); if (!s) return null;
  const ok = await crypto.subtle.verify('HMAC', await hmacKey(env), fromB64u(s), enc.encode(`${h}.${p}`));
  if (!ok) return null;
  const pl = JSON.parse(new TextDecoder().decode(fromB64u(p)));
  return pl.exp > now() / 1000 ? pl : null;
}

// ---------- APNs ----------
let apnsCache = null;
async function apnsJWT(env) {
  if (apnsCache && apnsCache.t > now() - 50 * 60 * 1000) return apnsCache.jwt;
  const pem = env.APNS_KEY.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const key = await crypto.subtle.importKey('pkcs8', Uint8Array.from(atob(pem), c => c.charCodeAt(0)), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const h = b64uStr(JSON.stringify({ alg: 'ES256', kid: env.APNS_KEY_ID }));
  const p = b64uStr(JSON.stringify({ iss: env.TEAM_ID, iat: Math.floor(now() / 1000) }));
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, enc.encode(`${h}.${p}`));
  apnsCache = { t: now(), jwt: `${h}.${p}.${b64u(sig)}` };
  return apnsCache.jwt;
}
async function apnsSend(env, token, envName, title, body, data = {}) {
  const host = envName === 'sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
  const r = await fetch(`https://${host}/3/device/${token}`, {
    method: 'POST',
    headers: { authorization: `bearer ${await apnsJWT(env)}`, 'apns-topic': env.APNS_TOPIC || 'com.mohlab.munawib', 'apns-push-type': 'alert', 'apns-priority': '10' },
    body: JSON.stringify({ aps: { alert: { title, body }, sound: 'default', badge: 1 }, ...data }),
  });
  let reason = ''; if (r.status !== 200) { try { reason = (await r.json()).reason; } catch { } }
  return { status: r.status, reason, host };
}
async function pushToUsers(env, hospitalId, userIds, title, body, data) {
  const results = [];
  if (!userIds.length) return results;
  const ph = userIds.map(() => '?').join(',');
  const { results: toks } = await env.DB.prepare(`SELECT token,user_id,env FROM device_tokens WHERE user_id IN (${ph})`).bind(...userIds).all();
  for (const t of toks) {
    let r;
    try {
      r = await apnsSend(env, t.token, t.env, title, body, data);
      if (r.status === 400 && r.reason === 'BadDeviceToken') {
        const other = t.env === 'sandbox' ? 'production' : 'sandbox';
        const r2 = await apnsSend(env, t.token, other, title, body, data);
        if (r2.status === 200) await env.DB.prepare('UPDATE device_tokens SET env=? WHERE token=?').bind(other, t.token).run();
        r = r2;
      }
      if (r.status === 410 || r.reason === 'Unregistered') await env.DB.prepare('DELETE FROM device_tokens WHERE token=?').bind(t.token).run();
    } catch (e) { r = { status: 0, reason: String(e) }; }
    results.push({ token: t.token.slice(0, 8) + '…', ...r });
  }
  for (const u of userIds) {
    const mine = results.length ? results.map(x => `${x.status}${x.reason ? ':' + x.reason : ''}`).join(',') : 'no-devices';
    await env.DB.prepare('INSERT INTO notification_log VALUES(?,?,?,?,?,?,?)').bind(uid(), hospitalId, u, title, body, mine, now()).run();
  }
  return results;
}
async function staffIds(env, hospitalId, deptId, roles) {
  let q = 'SELECT id FROM users WHERE hospital_id=?'; const a = [hospitalId];
  if (deptId) { q += ' AND department_id=?'; a.push(deptId); }
  if (roles) { q += ` AND role IN (${roles.map(() => '?').join(',')})`; a.push(...roles); }
  return (await env.DB.prepare(q).bind(...a).all()).results.map(r => r.id);
}

// ---------- helpers ----------
const inviteCode = () => Array.from(crypto.getRandomValues(new Uint8Array(6)), b => 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'[b % 31]).join('');
const pubUser = (u) => u && ({ id: u.id, hospital_id: u.hospital_id, department_id: u.department_id, email: u.email, name: u.name, title: u.title, employee_number: u.employee_number, role: u.role, phone: u.phone, photo: u.photo, reminder_minutes: u.reminder_minutes, invite_code: u.pw_hash ? null : u.invite_code, joined: !!u.pw_hash });
async function session(env, u) { return { token: await signJWT(env, { sub: u.id, hid: u.hospital_id, role: u.role }), user: pubUser(u) }; }
const isMgr = (me) => me.role === 'admin' || me.role === 'supervisor';

async function route(req, env) {
  const url = new URL(req.url); const p = url.pathname.replace(/\/+$/, '') || '/'; const m = req.method;
  if (m === 'OPTIONS') return new Response(null, { headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' } });
  const body = ['POST', 'PUT', 'PATCH'].includes(m) ? await req.json().catch(() => ({})) : {};
  const DB = env.DB;
  if (p === '/' || p === '/health') return json({ ok: true, service: 'munawib-api', apns: !!env.APNS_KEY });

  if (p === '/auth/signup' && m === 'POST') {
    const { hospital, email, password, name, department } = body;
    need(hospital && email && password && name, 400, 'missing fields'); need(password.length >= 8, 400, 'password too short');
    need(!(await DB.prepare('SELECT 1 FROM users WHERE email=?').bind(email.toLowerCase()).first()), 409, 'email exists');
    const hid = uid(), did = uid(), u = uid();
    await DB.batch([
      DB.prepare('INSERT INTO hospitals VALUES(?,?,?)').bind(hid, hospital, now()),
      DB.prepare('INSERT INTO departments VALUES(?,?,?)').bind(did, hid, department || 'القسم الرئيسي'),
      DB.prepare('INSERT INTO users(id,hospital_id,department_id,email,pw_hash,name,title,role,created_at) VALUES(?,?,?,?,?,?,?,?,?)').bind(u, hid, did, email.toLowerCase(), await hashPw(password), name, 'Admin', 'admin', now()),
    ]);
    return json(await session(env, await DB.prepare('SELECT * FROM users WHERE id=?').bind(u).first()), 201);
  }
  if (p === '/auth/login' && m === 'POST') {
    const u = await DB.prepare('SELECT * FROM users WHERE email=?').bind((body.email || '').toLowerCase()).first();
    need(u && await verifyPw(body.password || '', u.pw_hash), 401, 'invalid credentials');
    return json(await session(env, u));
  }
  if (p === '/auth/join' && m === 'POST') {
    const { code, email, password } = body; need(code && email && password && password.length >= 8, 400, 'missing fields');
    const u = await DB.prepare('SELECT * FROM users WHERE invite_code=? AND pw_hash IS NULL').bind(code.toUpperCase().trim()).first();
    need(u, 404, 'invalid invite');
    need(!(await DB.prepare('SELECT 1 FROM users WHERE email=? AND id<>?').bind(email.toLowerCase(), u.id).first()), 409, 'email exists');
    await DB.prepare('UPDATE users SET email=?,pw_hash=? WHERE id=?').bind(email.toLowerCase(), await hashPw(password), u.id).run();
    return json(await session(env, await DB.prepare('SELECT * FROM users WHERE id=?').bind(u.id).first()));
  }
  if (p.startsWith('/invite/') && m === 'GET') {
    const u = await DB.prepare('SELECT u.name,h.name hospital FROM users u JOIN hospitals h ON h.id=u.hospital_id WHERE invite_code=? AND pw_hash IS NULL').bind(p.split('/')[2].toUpperCase()).first();
    need(u, 404, 'invalid invite'); return json(u);
  }

  // ---- authenticated ----
  const claims = await verifyJWT(env, (req.headers.get('authorization') || '').replace(/^Bearer /i, ''));
  need(claims, 401, 'unauthorized');
  const me = await DB.prepare('SELECT * FROM users WHERE id=?').bind(claims.sub).first(); need(me, 401, 'unauthorized');
  const H = me.hospital_id;
  const mgr = () => need(isMgr(me), 403, 'forbidden');
  const seg = p.split('/').filter(Boolean);

  if (p === '/me' && m === 'GET') return json({ user: pubUser(me), hospital: await DB.prepare('SELECT * FROM hospitals WHERE id=?').bind(H).first() });
  if (p === '/me' && m === 'PATCH') {
    await DB.prepare('UPDATE users SET name=COALESCE(?,name),phone=COALESCE(?,phone),photo=COALESCE(?,photo),reminder_minutes=COALESCE(?,reminder_minutes) WHERE id=?')
      .bind(body.name ?? null, body.phone ?? null, body.photo ?? null, body.reminder_minutes ?? null, me.id).run();
    return json({ user: pubUser(await DB.prepare('SELECT * FROM users WHERE id=?').bind(me.id).first()) });
  }
  if (p === '/bootstrap' && m === 'GET') {
    const q = (s, ...a) => DB.prepare(s).bind(...a).all().then(r => r.results);
    const [hospital, departments, users, rosters, attendance, events, leaves, swaps, announcements, notifications] = await Promise.all([
      DB.prepare('SELECT * FROM hospitals WHERE id=?').bind(H).first(),
      q('SELECT * FROM departments WHERE hospital_id=?', H), q('SELECT * FROM users WHERE hospital_id=?', H),
      q('SELECT * FROM rosters WHERE hospital_id=? ORDER BY year DESC,month DESC LIMIT 36', H),
      q('SELECT * FROM attendance WHERE hospital_id=? ORDER BY date DESC LIMIT 1000', H),
      q('SELECT * FROM events WHERE hospital_id=? ORDER BY date', H),
      q('SELECT * FROM leave_requests WHERE hospital_id=? ORDER BY created_at DESC LIMIT 200', H),
      q('SELECT * FROM swap_requests WHERE hospital_id=? ORDER BY created_at DESC LIMIT 200', H),
      q('SELECT * FROM announcements WHERE hospital_id=? ORDER BY created_at DESC LIMIT 100', H),
      q('SELECT * FROM notification_log WHERE user_id=? ORDER BY created_at DESC LIMIT 50', me.id),
    ]);
    return json({ me: pubUser(me), hospital, departments, users: users.map(u => isMgr(me) ? pubUser(u) : { ...pubUser(u), invite_code: null, email: null }), rosters: rosters.map(r => ({ ...r, grid: JSON.parse(r.grid || '{}') })), attendance, events, leaves, swaps, announcements, notifications });
  }
  if (p === '/departments' && m === 'POST') { mgr(); const id = uid(); await DB.prepare('INSERT INTO departments VALUES(?,?,?)').bind(id, H, body.name).run(); return json({ id, name: body.name }, 201); }
  if (seg[0] === 'departments' && seg[1] && m === 'DELETE') { mgr(); await DB.prepare('DELETE FROM departments WHERE id=? AND hospital_id=?').bind(seg[1], H).run(); return json({ ok: true }); }

  if (p === '/employees' && m === 'POST') {
    mgr(); const id = uid(), code = inviteCode();
    const role = me.role === 'admin' && ['supervisor', 'employee', 'admin'].includes(body.role) ? body.role : 'employee';
    await DB.prepare('INSERT INTO users(id,hospital_id,department_id,name,title,employee_number,role,invite_code,phone,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)')
      .bind(id, H, body.department_id || me.department_id, body.name, body.title || '', body.employee_number || '', role, code, body.phone || '', now()).run();
    return json({ user: pubUser(await DB.prepare('SELECT * FROM users WHERE id=?').bind(id).first()), invite_code: code, invite_link: `munawib://join?code=${code}` }, 201);
  }
  if (seg[0] === 'employees' && seg[1] && m === 'PATCH') {
    mgr();
    await DB.prepare('UPDATE users SET name=COALESCE(?,name),title=COALESCE(?,title),employee_number=COALESCE(?,employee_number),department_id=COALESCE(?,department_id),phone=COALESCE(?,phone),role=COALESCE(?,role) WHERE id=? AND hospital_id=?')
      .bind(body.name ?? null, body.title ?? null, body.employee_number ?? null, body.department_id ?? null, body.phone ?? null, me.role === 'admin' ? (body.role ?? null) : null, seg[1], H).run();
    return json({ user: pubUser(await DB.prepare('SELECT * FROM users WHERE id=?').bind(seg[1]).first()) });
  }
  if (seg[0] === 'employees' && seg[1] && m === 'DELETE') { mgr(); need(seg[1] !== me.id, 400, 'cannot delete self'); await DB.prepare('DELETE FROM users WHERE id=? AND hospital_id=?').bind(seg[1], H).run(); return json({ ok: true }); }

  if (p === '/rosters' && m === 'PUT') {
    mgr(); const { department_id, year, month, grid } = body; need(department_id && year && month, 400, 'missing fields');
    const ex = await DB.prepare('SELECT id FROM rosters WHERE department_id=? AND year=? AND month=?').bind(department_id, year, month).first();
    const id = ex?.id || uid();
    await DB.prepare(`INSERT INTO rosters(id,hospital_id,department_id,year,month,status,grid,day_start,night_start,updated_at) VALUES(?,?,?,?,?,'draft',?,?,?,?)
      ON CONFLICT(department_id,year,month) DO UPDATE SET grid=excluded.grid,status='draft',day_start=excluded.day_start,night_start=excluded.night_start,updated_at=excluded.updated_at`)
      .bind(id, H, department_id, year, month, JSON.stringify(grid || {}), body.day_start ?? 5, body.night_start ?? 17, now()).run();
    return json({ id, status: 'draft' });
  }
  if (seg[0] === 'rosters' && seg[2] === 'status' && m === 'POST') {
    mgr(); const st = body.status; need(['draft', 'review', 'approved'].includes(st), 400, 'bad status');
    const r = await DB.prepare('SELECT * FROM rosters WHERE id=? AND hospital_id=?').bind(seg[1], H).first(); need(r, 404, 'not found');
    await DB.prepare('UPDATE rosters SET status=?,updated_at=? WHERE id=?').bind(st, now(), r.id).run();
    let push = [];
    if (st === 'approved') push = await pushToUsers(env, H, await staffIds(env, H, r.department_id), 'تم اعتماد الجدول ✅', `جدول ${r.month}/${r.year} أصبح معتمدًا. افتح مِناوب لمشاهدة مناوباتك.`, { type: 'roster', id: r.id });
    return json({ ok: true, status: st, push });
  }

  if (p === '/attendance' && m === 'POST') {
    const target = isMgr(me) && body.user_id ? body.user_id : me.id; const id = uid();
    await DB.prepare('INSERT INTO attendance VALUES(?,?,?,?,?,?,?)').bind(id, H, target, body.date, body.kind || 'H', body.hours || 0, body.note || '').run();
    return json({ id }, 201);
  }
  if (seg[0] === 'attendance' && seg[1] && m === 'DELETE') { mgr(); await DB.prepare('DELETE FROM attendance WHERE id=? AND hospital_id=?').bind(seg[1], H).run(); return json({ ok: true }); }
  if (p === '/events' && m === 'POST') { mgr(); const id = uid(); await DB.prepare('INSERT INTO events VALUES(?,?,?,?,?,?)').bind(id, H, body.title, body.date, body.location || '', body.audience || '').run(); return json({ id }, 201); }
  if (seg[0] === 'events' && seg[1] && m === 'DELETE') { mgr(); await DB.prepare('DELETE FROM events WHERE id=? AND hospital_id=?').bind(seg[1], H).run(); return json({ ok: true }); }

  if (p === '/leaves' && m === 'POST') {
    const id = uid(); await DB.prepare('INSERT INTO leave_requests(id,hospital_id,user_id,start_date,end_date,reason,created_at) VALUES(?,?,?,?,?,?,?)').bind(id, H, me.id, body.start_date, body.end_date, body.reason || '', now()).run();
    const push = await pushToUsers(env, H, (await staffIds(env, H, null, ['admin', 'supervisor'])).filter(x => x !== me.id), 'طلب إجازة جديد', `${me.name}: ${body.start_date} → ${body.end_date}`, { type: 'leave', id });
    return json({ id, push }, 201);
  }
  if (seg[0] === 'leaves' && seg[2] === 'decision' && m === 'POST') {
    mgr(); const st = body.approve ? 'approved' : 'rejected';
    const l = await DB.prepare('SELECT * FROM leave_requests WHERE id=? AND hospital_id=?').bind(seg[1], H).first(); need(l, 404, 'not found');
    await DB.prepare('UPDATE leave_requests SET status=?,decided_by=? WHERE id=?').bind(st, me.id, l.id).run();
    const push = await pushToUsers(env, H, [l.user_id], st === 'approved' ? 'تمت الموافقة على إجازتك ✅' : 'تم رفض طلب الإجازة', `${l.start_date} → ${l.end_date}`, { type: 'leave', id: l.id });
    return json({ ok: true, status: st, push });
  }
  if (p === '/swaps' && m === 'POST') {
    const id = uid(); await DB.prepare('INSERT INTO swap_requests(id,hospital_id,from_user,to_user,date,note,created_at) VALUES(?,?,?,?,?,?,?)').bind(id, H, me.id, body.to_user, body.date, body.note || '', now()).run();
    const targets = [...new Set([body.to_user, ...(await staffIds(env, H, null, ['admin', 'supervisor']))])].filter(x => x && x !== me.id);
    const push = await pushToUsers(env, H, targets, 'طلب تبديل مناوبة', `${me.name} يطلب تبديل مناوبة يوم ${body.date}`, { type: 'swap', id });
    return json({ id, push }, 201);
  }
  if (seg[0] === 'swaps' && seg[2] === 'decision' && m === 'POST') {
    mgr(); const st = body.approve ? 'approved' : 'rejected';
    const s = await DB.prepare('SELECT * FROM swap_requests WHERE id=? AND hospital_id=?').bind(seg[1], H).first(); need(s, 404, 'not found');
    await DB.prepare('UPDATE swap_requests SET status=?,decided_by=? WHERE id=?').bind(st, me.id, s.id).run();
    if (st === 'approved') {
      const [y, mo, d] = s.date.split('-').map(Number);
      const fu = await DB.prepare('SELECT department_id FROM users WHERE id=?').bind(s.from_user).first();
      const r = fu && await DB.prepare('SELECT * FROM rosters WHERE department_id=? AND year=? AND month=?').bind(fu.department_id, y, mo).first();
      if (r) { const g = JSON.parse(r.grid || '{}'); g[s.from_user] ||= {}; g[s.to_user] ||= {}; const a = g[s.from_user][d] || ''; g[s.from_user][d] = g[s.to_user][d] || ''; g[s.to_user][d] = a; await DB.prepare('UPDATE rosters SET grid=?,updated_at=? WHERE id=?').bind(JSON.stringify(g), now(), r.id).run(); }
    }
    const push = await pushToUsers(env, H, [s.from_user, s.to_user], st === 'approved' ? 'تمت الموافقة على التبديل ✅' : 'تم رفض طلب التبديل', `مناوبة يوم ${s.date}`, { type: 'swap', id: s.id });
    return json({ ok: true, status: st, push });
  }
  if (p === '/announcements' && m === 'POST') {
    mgr(); const id = uid();
    await DB.prepare('INSERT INTO announcements VALUES(?,?,?,?,?,?,?)').bind(id, H, body.department_id || null, me.name, body.title, body.body || '', now()).run();
    const push = await pushToUsers(env, H, (await staffIds(env, H, body.department_id || null)).filter(x => x !== me.id), `📢 ${body.title}`, body.body || '', { type: 'announcement', id });
    return json({ id, push }, 201);
  }
  if (p === '/devices' && m === 'POST') {
    need(/^[0-9a-f]{32,200}$/i.test(body.token || ''), 400, 'bad token');
    await DB.prepare('INSERT INTO device_tokens VALUES(?,?,?,?) ON CONFLICT(token) DO UPDATE SET user_id=excluded.user_id,env=excluded.env,updated_at=excluded.updated_at').bind(body.token, me.id, body.env === 'sandbox' ? 'sandbox' : 'production', now()).run();
    return json({ ok: true });
  }
  if (p === '/devices' && m === 'DELETE') { await DB.prepare('DELETE FROM device_tokens WHERE token=? AND user_id=?').bind(body.token || url.searchParams.get('token'), me.id).run(); return json({ ok: true }); }
  if (p === '/push/test' && m === 'POST') {
    need(env.APNS_KEY, 503, 'APNs not configured');
    const results = await pushToUsers(env, H, [me.id], 'اختبار التنبيهات 🔔', 'وصل تنبيه حقيقي من خادم مِناوب إلى جهازك.', { type: 'test' });
    return json({ sent: results.filter(r => r.status === 200).length, devices: results.length, results });
  }
  if (p === '/notifications' && m === 'GET') return json((await DB.prepare('SELECT * FROM notification_log WHERE user_id=? ORDER BY created_at DESC LIMIT 100').bind(me.id).all()).results);
  throw new HttpError(404, 'not found');
}

// ---------- cron: shift reminders ----------
async function shiftReminders(env) {
  if (!env.APNS_KEY) return;
  const t = new Date(now() + 3 * 3600 * 1000); // Asia/Riyadh (UTC+3, no DST)
  const months = [[t.getUTCFullYear(), t.getUTCMonth() + 1]];
  const nx = new Date(Date.UTC(t.getUTCFullYear(), t.getUTCMonth() + 1, 1)); months.push([nx.getUTCFullYear(), nx.getUTCMonth() + 1]);
  for (const [y, mo] of months) {
    const { results: rs } = await env.DB.prepare("SELECT * FROM rosters WHERE status='approved' AND year=? AND month=?").bind(y, mo).all();
    for (const r of rs) {
      const g = JSON.parse(r.grid || '{}');
      for (const [userId, days] of Object.entries(g)) {
        const u = await env.DB.prepare('SELECT reminder_minutes FROM users WHERE id=?').bind(userId).first(); if (!u) continue;
        const lead = (u.reminder_minutes ?? 60) * 60000;
        for (const [d, code] of Object.entries(days)) {
          if (code !== 'D' && code !== 'N') continue;
          const startLocal = Date.UTC(y, mo - 1, Number(d), code === 'D' ? r.day_start : r.night_start);
          const fireUtc = startLocal - 3 * 3600 * 1000 - lead;
          if (fireUtc <= now() && fireUtc > now() - 10 * 60000) {
            const key = `${userId}:${y}-${mo}-${d}:${code}`;
            const ins = await env.DB.prepare('INSERT OR IGNORE INTO reminders_sent VALUES(?)').bind(key).run();
            if (ins.meta.changes) await pushToUsers(env, r.hospital_id, [userId], 'تذكير بالمناوبة ⏰', `مناوبتك ${code === 'D' ? 'النهارية' : 'الليلية'} تبدأ الساعة ${code === 'D' ? r.day_start : r.night_start}:00`, { type: 'reminder' });
          }
        }
      }
    }
  }
}

export default {
  async fetch(req, env) {
    try { return await route(req, env); }
    catch (e) { return json({ error: e.message || 'error' }, e.status || 500); }
  },
  async scheduled(_ev, env, ctx) { ctx.waitUntil(shiftReminders(env)); },
};
