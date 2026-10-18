const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { Pool } = require('pg');
const { WebSocketServer, WebSocket } = require('ws');

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

const WORLD_WIDTH = 4000;
const WORLD_HEIGHT = 2400;
const CELL_SIZE = 50;
const GRID_WIDTH = WORLD_WIDTH / CELL_SIZE;
const GRID_HEIGHT = WORLD_HEIGHT / CELL_SIZE;
const TICK_MS = 50;
const PLAYER_SPEED = 340;
const MAX_PLAYERS_PER_MATCH = 40;

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

const matches = new Map();
const connections = new Map();

function createMatch() {
  const match = {
    id: crypto.randomUUID(),
    players: new Map(),
    territory: new Uint32Array(GRID_WIDTH * GRID_HEIGHT),
    nextPlayerNumber: 1
  };
  matches.set(match.id, match);
  return match;
}

let match = createMatch();

function spawnForNumber(n) {
  const margin = 250;
  const slots = [
    [margin, margin], [WORLD_WIDTH - margin, margin], [margin, WORLD_HEIGHT - margin], [WORLD_WIDTH - margin, WORLD_HEIGHT - margin],
    [WORLD_WIDTH / 2, WORLD_HEIGHT / 2]
  ];
  return slots[(n - 1) % slots.length].slice();
}

function paintStartTerritory(matchState, player) {
  const cx = Math.floor(player.x / CELL_SIZE);
  const cy = Math.floor(player.y / CELL_SIZE);
  for (let y = cy - 2; y <= cy + 2; y += 1) {
    for (let x = cx - 2; x <= cx + 2; x += 1) {
      if (x >= 0 && x < GRID_WIDTH && y >= 0 && y < GRID_HEIGHT) matchState.territory[y * GRID_WIDTH + x] = player.id;
    }
  }
}

function paintMovementTerritory(matchState, player) {
  const radius = 1;
  const cx = Math.floor(player.x / CELL_SIZE);
  const cy = Math.floor(player.y / CELL_SIZE);
  let added = 0;
  for (let y = cy - radius; y <= cy + radius; y += 1) {
    for (let x = cx - radius; x <= cx + radius; x += 1) {
      if (x < 0 || x >= GRID_WIDTH || y < 0 || y >= GRID_HEIGHT) continue;
      const index = y * GRID_WIDTH + x;
      if (matchState.territory[index] !== player.id) {
        matchState.territory[index] = player.id;
        added += 1;
      }
    }
  }
  player.territory += added;
}

function playerSnapshot(player) {
  return {
    id: player.id,
    username: player.username,
    x: Math.round(player.x),
    y: Math.round(player.y),
    angle: player.angle,
    territory: player.territory,
    connected: player.socket.readyState === WebSocket.OPEN
  };
}

function matchSnapshot(matchState) {
  return {
    type: 'state',
    world: { width: WORLD_WIDTH, height: WORLD_HEIGHT, cell_size: CELL_SIZE, grid_width: GRID_WIDTH, grid_height: GRID_HEIGHT },
    self_id: null,
    players: Array.from(matchState.players.values()).map(playerSnapshot),
    territory: Array.from(matchState.territory)
  };
}

function send(socket, payload) {
  if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(payload));
}

function broadcast(matchState, payload) {
  for (const player of matchState.players.values()) send(player.socket, payload);
}

function removePlayer(matchState, player) {
  if (!player) return;
  matchState.players.delete(player.id);
  connections.delete(player.socket);
  broadcast(matchState, { type: 'player_left', id: player.id });
}

function handleGameMessage(player, raw) {
  let message;
  try { message = JSON.parse(raw.toString()); } catch { return; }
  if (!message || typeof message !== 'object') return;
  if (message.type === 'input') {
    const x = Number(message.x);
    const y = Number(message.y);
    if (!Number.isFinite(x) || !Number.isFinite(y)) return;
    const length = Math.hypot(x, y);
    if (length > 1) {
      player.inputX = x / length;
      player.inputY = y / length;
    } else {
      player.inputX = Math.max(-1, Math.min(1, x));
      player.inputY = Math.max(-1, Math.min(1, y));
    }
    player.lastInputAt = Date.now();
  }
}

const gameWss = new WebSocketServer({ noServer: true });

gameWss.on('connection', (socket, req, account) => {
  if (match.players.size >= MAX_PLAYERS_PER_MATCH) {
    send(socket, { type: 'error', message: 'Match is full' });
    socket.close();
    return;
  }
  const id = match.nextPlayerNumber++;
  const spawn = spawnForNumber(id);
  const player = {
    id,
    accountId: account.id,
    username: account.username,
    socket,
    x: spawn[0],
    y: spawn[1],
    angle: 0,
    inputX: 0,
    inputY: 0,
    territory: 25,
    lastInputAt: Date.now()
  };
  match.players.set(player.id, player);
  connections.set(socket, player);
  paintStartTerritory(match, player);

  const snapshot = matchSnapshot(match);
  snapshot.self_id = player.id;
  send(socket, snapshot);
  broadcast(match, { type: 'player_joined', player: playerSnapshot(player) });

  socket.on('message', (data) => handleGameMessage(player, data));
  socket.on('close', () => removePlayer(match, player));
  socket.on('error', () => removePlayer(match, player));
});

setInterval(() => {
  const now = Date.now();
  for (const player of match.players.values()) {
    const idle = now - player.lastInputAt > 1000;
    if (idle) { player.inputX = 0; player.inputY = 0; }
    const length = Math.hypot(player.inputX, player.inputY);
    if (length > 0.001) {
      player.x += (player.inputX / Math.max(1, length)) * PLAYER_SPEED * (TICK_MS / 1000);
      player.y += (player.inputY / Math.max(1, length)) * PLAYER_SPEED * (TICK_MS / 1000);
      player.x = Math.max(20, Math.min(WORLD_WIDTH - 20, player.x));
      player.y = Math.max(20, Math.min(WORLD_HEIGHT - 20, player.y));
      player.angle = Math.atan2(player.inputY, player.inputX);
      paintMovementTerritory(match, player);
    }
  }
  if (match.players.size > 0) broadcast(match, matchSnapshot(match));
}, TICK_MS);

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
      return res.end(JSON.stringify({ status: 'ok', database: database ? 'connected' : 'disconnected', game: 'ConquerX', realtime: 'websocket' }));
    } catch (error) {
      console.error('Database health check failed:', error.message);
      res.writeHead(503);
      return res.end(JSON.stringify({ status: 'error', database: 'disconnected', game: 'ConquerX' }));
    }
  }
  if (req.method === 'GET' && pathname === '/') {
    res.writeHead(200);
    return res.end(JSON.stringify({ name: 'ConquerX', status: 'online', version: '0.4.0', realtime: 'websocket', world: { width: WORLD_WIDTH, height: WORLD_HEIGHT } }));
  }
  res.writeHead(404);
  res.end(JSON.stringify({ error: 'Not Found' }));
});

const gamePath = '/ws';
server.on('upgrade', async (req, socket, head) => {
  try {
    const requestUrl = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
    if (requestUrl.pathname !== gamePath) { socket.destroy(); return; }
    const token = requestUrl.searchParams.get('token') || '';
    const account = await getAccountFromToken(token);
    if (!account) { socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n'); socket.destroy(); return; }
    gameWss.handleUpgrade(req, socket, head, (ws) => gameWss.emit('connection', ws, req, account));
  } catch (error) {
    console.error('WebSocket authentication failed:', error.message);
    socket.destroy();
  }
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
