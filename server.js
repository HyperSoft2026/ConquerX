const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { Pool } = require('pg');

const port = Number(process.env.PORT || 3000);
const poolConfig = process.env.POSTGRESQL_ADDON_URI
  ? { connectionString: process.env.POSTGRESQL_ADDON_URI, ssl: { rejectUnauthorized: false } }
  : { host: process.env.POSTGRESQL_ADDON_HOST, port: Number(process.env.POSTGRESQL_ADDON_PORT || 5432), database: process.env.POSTGRESQL_ADDON_DB, user: process.env.POSTGRESQL_ADDON_USER, password: process.env.POSTGRESQL_ADDON_PASSWORD, ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false };
const pool = new Pool(poolConfig);

const SERVER_URL = 'https://app-4729a9fe-87fc-4f1b-9248-112725e0db57.cleverapps.io';
const DISCORD_CLIENT_ID = process.env.DISCORD_CLIENT_ID || '';
const DISCORD_CLIENT_SECRET = process.env.DISCORD_CLIENT_SECRET || '';
const DISCORD_REDIRECT_URI = process.env.DISCORD_REDIRECT_URI || `${SERVER_URL}/auth/discord/callback`;
const OAUTH_STATE_SECRET = process.env.DISCORD_CLIENT_SECRET || '';
const LOGIN_SESSION_TTL_MS = 10 * 60 * 1000;

const publicRoot = path.join(__dirname, 'public');
const staticRoot = path.join(__dirname, 'assets');
const pages = { '/terms-of-service': 'terms-of-service.html', '/privacy-policy': 'privacy-policy.html' };
const mimeTypes = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.gif': 'image/gif', '.svg': 'image/svg+xml' };

function serveFile(res, filePath) {
  try {
    const extension = path.extname(filePath).toLowerCase();
    const content = fs.readFileSync(filePath);
    res.writeHead(200, { 'Content-Type': mimeTypes[extension] || 'application/octet-stream' });
    res.end(content);
    return true;
  } catch {
    return false;
  }
}

function sendJson(res, statusCode, body) {
  res.writeHead(statusCode, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(body));
}

function createSignedState(loginSessionId) {
  const payload = `${loginSessionId}.${Date.now()}`;
  const signature = crypto.createHmac('sha256', OAUTH_STATE_SECRET).update(payload).digest('base64url');
  return `${Buffer.from(payload).toString('base64url')}.${signature}`;
}

function readSignedState(state) {
  if (!OAUTH_STATE_SECRET || !state) return null;
  const [encodedPayload, signature] = state.split('.');
  if (!encodedPayload || !signature) return null;
  let payload;
  try { payload = Buffer.from(encodedPayload, 'base64url').toString('utf8'); } catch { return null; }
  const expected = crypto.createHmac('sha256', OAUTH_STATE_SECRET).update(payload).digest('base64url');
  const a = Buffer.from(signature);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  const dot = payload.lastIndexOf('.');
  if (dot <= 0) return null;
  const loginSessionId = payload.slice(0, dot);
  const issuedAt = Number(payload.slice(dot + 1));
  if (!Number.isFinite(issuedAt) || Date.now() - issuedAt > LOGIN_SESSION_TTL_MS) return null;
  if (!/^[a-f0-9-]{36}$/i.test(loginSessionId)) return null;
  return loginSessionId;
}

function createToken() { return crypto.randomBytes(32).toString('base64url'); }

async function checkDatabase() {
  const result = await pool.query('SELECT 1 AS ok');
  return result.rows[0]?.ok === 1;
}

async function ensureDatabaseSchema() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS accounts (
      id BIGSERIAL PRIMARY KEY,
      discord_user_id TEXT UNIQUE,
      username TEXT NOT NULL,
      avatar TEXT,
      gold INTEGER NOT NULL DEFAULT 0,
      gems INTEGER NOT NULL DEFAULT 0,
      kills INTEGER NOT NULL DEFAULT 0,
      wins INTEGER NOT NULL DEFAULT 0,
      level INTEGER NOT NULL DEFAULT 1,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS login_sessions (
      id UUID PRIMARY KEY,
      status TEXT NOT NULL DEFAULT 'pending',
      account_id BIGINT REFERENCES accounts(id) ON DELETE SET NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      expires_at TIMESTAMPTZ NOT NULL,
      completed_at TIMESTAMPTZ,
      session_token TEXT
    );
    CREATE TABLE IF NOT EXISTS app_sessions (
      token_hash TEXT PRIMARY KEY,
      account_id BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      expires_at TIMESTAMPTZ NOT NULL
    );
    ALTER TABLE login_sessions ADD COLUMN IF NOT EXISTS session_token TEXT;
    CREATE INDEX IF NOT EXISTS idx_login_sessions_expires_at ON login_sessions(expires_at);
    CREATE INDEX IF NOT EXISTS idx_app_sessions_account_id ON app_sessions(account_id);
  `);
}

async function getDiscordUser(accessToken) {
  const response = await fetch('https://discord.com/api/v10/users/@me', { headers: { Authorization: `Bearer ${accessToken}` } });
  if (!response.ok) throw new Error(`Discord user request failed: ${response.status}`);
  return response.json();
}

async function exchangeDiscordCode(code) {
  const body = new URLSearchParams({ client_id: DISCORD_CLIENT_ID, client_secret: DISCORD_CLIENT_SECRET, grant_type: 'authorization_code', code, redirect_uri: DISCORD_REDIRECT_URI });
  const response = await fetch('https://discord.com/api/v10/oauth2/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body });
  if (!response.ok) throw new Error(`Discord token exchange failed: ${response.status} ${await response.text()}`);
  return response.json();
}

async function upsertDiscordAccount(discordUser) {
  const username = discordUser.global_name || discordUser.username || `Player_${discordUser.id.slice(-6)}`;
  const avatar = discordUser.avatar || null;
  const result = await pool.query(`
    INSERT INTO accounts (discord_user_id, username, avatar) VALUES ($1, $2, $3)
    ON CONFLICT (discord_user_id) DO UPDATE SET username = EXCLUDED.username, avatar = EXCLUDED.avatar, updated_at = NOW()
    RETURNING id, username, avatar, gold, gems, kills, wins, level
  `, [discordUser.id, username, avatar]);
  return result.rows[0];
}

async function completeLogin(loginSessionId, accountId) {
  const token = createToken();
  const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(`UPDATE login_sessions SET status = 'completed', account_id = $2, completed_at = NOW(), session_token = $3 WHERE id = $1 AND status = 'pending'`, [loginSessionId, accountId, token]);
    await client.query(`INSERT INTO app_sessions (token_hash, account_id, expires_at) VALUES ($1, $2, NOW() + INTERVAL '30 days')`, [tokenHash, accountId]);
    await client.query('COMMIT');
    return token;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function consumeLoginSession(loginSessionId) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await client.query(`SELECT ls.status, ls.session_token, a.id, a.username, a.avatar, a.gold, a.gems, a.kills, a.wins, a.level FROM login_sessions ls LEFT JOIN accounts a ON a.id = ls.account_id WHERE ls.id = $1 AND ls.expires_at > NOW() FOR UPDATE`, [loginSessionId]);
    if (!result.rowCount) { await client.query('ROLLBACK'); return null; }
    const row = result.rows[0];
    if (row.status !== 'completed' || !row.session_token) { await client.query('ROLLBACK'); return { pending: true }; }
    await client.query('UPDATE login_sessions SET session_token = NULL WHERE id = $1', [loginSessionId]);
    await client.query('COMMIT');
    return { pending: false, token: row.session_token, account: { id: row.id, username: row.username, avatar: row.avatar, gold: row.gold, gems: row.gems, kills: row.kills, wins: row.wins, level: row.level } };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function getAccountFromToken(token) {
  if (!token) return null;
  const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
  const result = await pool.query(`SELECT a.id, a.username, a.avatar, a.gold, a.gems, a.kills, a.wins, a.level FROM app_sessions s JOIN accounts a ON a.id = s.account_id WHERE s.token_hash = $1 AND s.expires_at > NOW()`, [tokenHash]);
  return result.rows[0] || null;
}

function getBearerToken(req) {
  const header = req.headers.authorization || '';
  return header.startsWith('Bearer ') ? header.slice(7).trim() : '';
}

const server = http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') { res.writeHead(204); return res.end(); }

  const requestUrl = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const pathname = requestUrl.pathname;

  if (req.method === 'GET' && pages[pathname]) { if (serveFile(res, path.join(publicRoot, pages[pathname]))) return; }
  if (req.method === 'GET' && pathname === '/legal.css') { if (serveFile(res, path.join(publicRoot, 'legal.css'))) return; }
  if (req.method === 'GET' && pathname.startsWith('/assets/')) {
    const relativePath = pathname.slice('/assets/'.length);
    const filePath = path.resolve(staticRoot, relativePath);
    if (filePath.startsWith(staticRoot + path.sep) && serveFile(res, filePath)) return;
  }

  if (req.method === 'GET' && pathname === '/auth/discord/start') {
    if (!DISCORD_CLIENT_ID || !DISCORD_CLIENT_SECRET || !OAUTH_STATE_SECRET) return sendJson(res, 503, { error: 'Discord login is not configured' });
    const suppliedSessionId = requestUrl.searchParams.get('session');
    const loginSessionId = suppliedSessionId && /^[a-f0-9-]{36}$/i.test(suppliedSessionId) ? suppliedSessionId : crypto.randomUUID();
    await pool.query(`INSERT INTO login_sessions (id, expires_at) VALUES ($1, NOW() + INTERVAL '10 minutes') ON CONFLICT (id) DO UPDATE SET status = 'pending', account_id = NULL, created_at = NOW(), expires_at = NOW() + INTERVAL '10 minutes', completed_at = NULL, session_token = NULL`, [loginSessionId]);
    const state = createSignedState(loginSessionId);
    const params = new URLSearchParams({ client_id: DISCORD_CLIENT_ID, response_type: 'code', redirect_uri: DISCORD_REDIRECT_URI, scope: 'identify', state });
    res.writeHead(302, { Location: `https://discord.com/oauth2/authorize?${params.toString()}`, 'Cache-Control': 'no-store' });
    return res.end();
  }

  if (req.method === 'GET' && pathname === '/auth/discord/callback') {
    const code = requestUrl.searchParams.get('code');
    const state = requestUrl.searchParams.get('state');
    const loginSessionId = readSignedState(state);
    if (!code || !loginSessionId) return sendJson(res, 400, { error: 'Invalid Discord OAuth callback' });
    try {
      const sessionResult = await pool.query(`SELECT id FROM login_sessions WHERE id = $1 AND status = 'pending' AND expires_at > NOW()`, [loginSessionId]);
      if (!sessionResult.rowCount) return sendJson(res, 400, { error: 'Login session expired or already used' });
      const tokenResponse = await exchangeDiscordCode(code);
      const discordUser = await getDiscordUser(tokenResponse.access_token);
      const account = await upsertDiscordAccount(discordUser);
      await completeLogin(loginSessionId, account.id);
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
      return res.end(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>ConquerX Login</title><style>body{margin:0;background:#090d16;color:#eef3ff;font-family:Arial,sans-serif;display:grid;place-items:center;min-height:100vh;text-align:center}.card{max-width:520px;padding:42px;border:1px solid #26324a;border-radius:20px;background:#111827}h1{margin-top:0}p{color:#aeb9cc}</style></head><body><main class="card"><h1>Discord connected</h1><p>تم تسجيل الدخول إلى ConquerX بنجاح. يمكنك العودة إلى اللعبة الآن.</p></main></body></html>`);
    } catch (error) {
      console.error('Discord OAuth callback failed:', error.message);
      return sendJson(res, 500, { error: 'Discord login failed' });
    }
  }

  if (req.method === 'GET' && pathname === '/auth/discord/status') {
    const sessionId = requestUrl.searchParams.get('session');
    if (!sessionId || !/^[a-f0-9-]{36}$/i.test(sessionId)) return sendJson(res, 400, { error: 'Invalid session' });
    try {
      const login = await consumeLoginSession(sessionId);
      if (!login) return sendJson(res, 404, { status: 'expired' });
      if (login.pending) return sendJson(res, 200, { status: 'pending' });
      return sendJson(res, 200, { status: 'completed', session_token: login.token, account: login.account });
    } catch (error) {
      console.error('Discord login status failed:', error.message);
      return sendJson(res, 500, { error: 'Login status failed' });
    }
  }

  if (req.method === 'GET' && pathname === '/me') {
    try {
      const account = await getAccountFromToken(getBearerToken(req));
      if (!account) return sendJson(res, 401, { error: 'Unauthorized' });
      return sendJson(res, 200, { account });
    } catch (error) {
      console.error('Account lookup failed:', error.message);
      return sendJson(res, 500, { error: 'Account lookup failed' });
    }
  }

  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  if (req.method === 'GET' && pathname === '/health') {
    try {
      const database = await checkDatabase();
      res.writeHead(200);
      return res.end(JSON.stringify({ status: 'ok', database: database ? 'connected' : 'disconnected', game: 'ConquerX' }));
    } catch (error) {
      console.error('Database health check failed:', error.message);
      res.writeHead(503);
      return res.end(JSON.stringify({ status: 'error', database: 'disconnected', game: 'ConquerX' }));
    }
  }
  if (req.method === 'GET' && pathname === '/') {
    res.writeHead(200);
    return res.end(JSON.stringify({ name: 'ConquerX', status: 'online', version: '0.3.0' }));
  }
  res.writeHead(404);
  res.end(JSON.stringify({ error: 'Not Found' }));
});

server.listen(port, '0.0.0.0', async () => {
  console.log(`ConquerX server listening on port ${port}`);
  try { await ensureDatabaseSchema(); console.log('ConquerX database schema ready'); }
  catch (error) { console.error('Database schema initialization failed:', error.message); }
});

async function shutdown(signal) {
  console.log(`${signal}: shutting down ConquerX server...`);
  server.close(async () => { await pool.end(); process.exit(0); });
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
