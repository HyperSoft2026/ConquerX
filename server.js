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
const RESPAWN_MS = 2500;
const SAVE_MS = 5000;
const COMBAT_DISTANCE = 48;

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
  } catch { return false; }
}
function sendJson(res, statusCode, body) {
  res.writeHead(statusCode, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(body));
}
function createSignedState(id) {
  const payload = `${id}.${Date.now()}`;
  const signature = crypto.createHmac('sha256', OAUTH_STATE_SECRET).update(payload).digest('base64url');
  return `${Buffer.from(payload).toString('base64url')}.${signature}`;
}
function readSignedState(state) {
  if (!OAUTH_STATE_SECRET || !state) return null;
  const [encoded, signature] = state.split('.');
  if (!encoded || !signature) return null;
  let payload;
  try { payload = Buffer.from(encoded, 'base64url').toString('utf8'); } catch { return null; }
  const expected = crypto.createHmac('sha256', OAUTH_STATE_SECRET).update(payload).digest('base64url');
  const a = Buffer.from(signature); const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  const dot = payload.lastIndexOf('.');
  if (dot <= 0) return null;
  const id = payload.slice(0, dot); const issued = Number(payload.slice(dot + 1));
  if (!Number.isFinite(issued) || Date.now() - issued > LOGIN_SESSION_TTL_MS || !/^[a-f0-9-]{36}$/i.test(id)) return null;
  return id;
}
function createToken() { return crypto.randomBytes(32).toString('base64url'); }
function getBearerToken(req) {
  const h = req.headers.authorization || '';
  return h.startsWith('Bearer ') ? h.slice(7).trim() : '';
}
async function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => { body += chunk; if (body.length > 20000) req.destroy(); });
    req.on('end', () => { try { resolve(body ? JSON.parse(body) : {}); } catch { reject(new Error('Invalid JSON')); } });
    req.on('error', reject);
  });
}

const skins = Array.from({ length: 50 }, (_, i) => ({
  id: i + 1,
  name: `Skin ${String(i + 1).padStart(2, '0')}`,
  hue: Math.round((i * 360) / 50),
  rarity: i < 25 ? 'Common' : i < 40 ? 'Rare' : i < 48 ? 'Epic' : 'Legendary',
  unlocked_by_default: i === 0
}));

async function ensureDatabaseSchema() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS accounts (
      id BIGSERIAL PRIMARY KEY, discord_user_id TEXT UNIQUE, username TEXT NOT NULL, avatar TEXT,
      gold INTEGER NOT NULL DEFAULT 0, gems INTEGER NOT NULL DEFAULT 0, kills INTEGER NOT NULL DEFAULT 0,
      wins INTEGER NOT NULL DEFAULT 0, level INTEGER NOT NULL DEFAULT 1, selected_skin INTEGER NOT NULL DEFAULT 1,
      unlocked_skins JSONB NOT NULL DEFAULT '[1]'::jsonb, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    ALTER TABLE accounts ADD COLUMN IF NOT EXISTS selected_skin INTEGER NOT NULL DEFAULT 1;
    ALTER TABLE accounts ADD COLUMN IF NOT EXISTS unlocked_skins JSONB NOT NULL DEFAULT '[1]'::jsonb;
    CREATE TABLE IF NOT EXISTS login_sessions (
      id UUID PRIMARY KEY, status TEXT NOT NULL DEFAULT 'pending', account_id BIGINT REFERENCES accounts(id) ON DELETE SET NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), expires_at TIMESTAMPTZ NOT NULL, completed_at TIMESTAMPTZ, session_token TEXT
    );
    CREATE TABLE IF NOT EXISTS app_sessions (
      token_hash TEXT PRIMARY KEY, account_id BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), expires_at TIMESTAMPTZ NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_login_sessions_expires_at ON login_sessions(expires_at);
    CREATE INDEX IF NOT EXISTS idx_app_sessions_account_id ON app_sessions(account_id);
    CREATE TABLE IF NOT EXISTS match_states (
      id TEXT PRIMARY KEY, territory JSONB NOT NULL, updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `);
}
async function checkDatabase() { const r = await pool.query('SELECT 1 AS ok'); return r.rows[0]?.ok === 1; }
async function getAccountFromToken(token) {
  if (!token) return null;
  const hash = crypto.createHash('sha256').update(token).digest('hex');
  const r = await pool.query(`SELECT a.id,a.username,a.avatar,a.gold,a.gems,a.kills,a.wins,a.level,a.selected_skin,a.unlocked_skins FROM app_sessions s JOIN accounts a ON a.id=s.account_id WHERE s.token_hash=$1 AND s.expires_at>NOW()`, [hash]);
  return r.rows[0] || null;
}
async function upsertDiscordAccount(user) {
  const username = user.global_name || user.username || `Player_${user.id.slice(-6)}`;
  const r = await pool.query(`INSERT INTO accounts(discord_user_id,username,avatar) VALUES($1,$2,$3)
    ON CONFLICT(discord_user_id) DO UPDATE SET username=EXCLUDED.username,avatar=EXCLUDED.avatar,updated_at=NOW()
    RETURNING id,username,avatar,gold,gems,kills,wins,level,selected_skin,unlocked_skins`, [user.id, username, user.avatar || null]);
  return r.rows[0];
}
async function completeLogin(loginId, accountId) {
  const token = createToken(); const hash = crypto.createHash('sha256').update(token).digest('hex');
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    await c.query(`UPDATE login_sessions SET status='completed',account_id=$2,completed_at=NOW(),session_token=$3 WHERE id=$1 AND status='pending'`, [loginId, accountId, token]);
    await c.query(`INSERT INTO app_sessions(token_hash,account_id,expires_at) VALUES($1,$2,NOW()+INTERVAL '30 days')`, [hash, accountId]);
    await c.query('COMMIT'); return token;
  } catch (e) { await c.query('ROLLBACK'); throw e; } finally { c.release(); }
}
async function consumeLoginSession(id) {
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    const r = await c.query(`SELECT ls.status,ls.session_token,a.id,a.username,a.avatar,a.gold,a.gems,a.kills,a.wins,a.level,a.selected_skin,a.unlocked_skins FROM login_sessions ls LEFT JOIN accounts a ON a.id=ls.account_id WHERE ls.id=$1 AND ls.expires_at>NOW() FOR UPDATE`, [id]);
    if (!r.rowCount) { await c.query('ROLLBACK'); return null; }
    const row = r.rows[0];
    if (row.status !== 'completed' || !row.session_token) { await c.query('ROLLBACK'); return { pending: true }; }
    await c.query('UPDATE login_sessions SET session_token=NULL WHERE id=$1', [id]); await c.query('COMMIT');
    return { pending:false, token:row.session_token, account: row };
  } catch (e) { await c.query('ROLLBACK'); throw e; } finally { c.release(); }
}
async function getAccountById(id) {
  const r = await pool.query(`SELECT id,username,avatar,gold,gems,kills,wins,level,selected_skin,unlocked_skins FROM accounts WHERE id=$1`, [id]);
  return r.rows[0] || null;
}

const match = { id:'main', players:new Map(), territory:new Uint32Array(GRID_WIDTH*GRID_HEIGHT), nextPlayerNumber:1, loaded:false };
async function loadMatchState() {
  const r = await pool.query('SELECT territory FROM match_states WHERE id=$1', [match.id]);
  if (r.rowCount && Array.isArray(r.rows[0].territory)) {
    const saved = r.rows[0].territory;
    for (let i=0;i<match.territory.length && i<saved.length;i++) match.territory[i] = Number(saved[i]) || 0;
  }
  match.loaded = true;
}
let saveQueued = false;
async function saveMatchState() {
  if (!match.loaded || saveQueued) return;
  saveQueued = true;
  try {
    await pool.query(`INSERT INTO match_states(id,territory,updated_at) VALUES($1,$2,NOW()) ON CONFLICT(id) DO UPDATE SET territory=EXCLUDED.territory,updated_at=NOW()`, [match.id, JSON.stringify(Array.from(match.territory))]);
  } catch (e) { console.error('Match persistence failed:', e.message); }
  finally { saveQueued = false; }
}
function spawnForNumber(n) {
  const margin=250; const slots=[[margin,margin],[WORLD_WIDTH-margin,margin],[margin,WORLD_HEIGHT-margin],[WORLD_WIDTH-margin,WORLD_HEIGHT-margin],[WORLD_WIDTH/2,WORLD_HEIGHT/2]];
  return slots[(n-1)%slots.length].slice();
}
function paintStartTerritory(player) {
  const cx=Math.floor(player.x/CELL_SIZE), cy=Math.floor(player.y/CELL_SIZE);
  let count=0;
  for(let y=cy-2;y<=cy+2;y++) for(let x=cx-2;x<=cx+2;x++) if(x>=0&&x<GRID_WIDTH&&y>=0&&y<GRID_HEIGHT){ const i=y*GRID_WIDTH+x; if(match.territory[i]===0){match.territory[i]=player.accountId;count++;} }
  player.territory += count;
}
function paintMovementTerritory(player) {
  const cx=Math.floor(player.x/CELL_SIZE), cy=Math.floor(player.y/CELL_SIZE); let added=0;
  for(let y=cy-1;y<=cy+1;y++) for(let x=cx-1;x<=cx+1;x++) if(x>=0&&x<GRID_WIDTH&&y>=0&&y<GRID_HEIGHT){ const i=y*GRID_WIDTH+x; if(match.territory[i]!==player.accountId){match.territory[i]=player.accountId;added++;} }
  player.territory += added;
}
function clearPlayerTerritory(accountId) { for(let i=0;i<match.territory.length;i++) if(match.territory[i]===accountId) match.territory[i]=0; }
function respawnPlayer(player) {
  const spawn=spawnForNumber(player.id); player.x=spawn[0]; player.y=spawn[1]; player.inputX=0; player.inputY=0; player.dead=false; player.respawnAt=0; player.territory=0; paintStartTerritory(player);
}
async function recordKill(killer,victim) {
  await pool.query(`UPDATE accounts SET kills=kills+1,updated_at=NOW() WHERE id=$1`, [killer.accountId]);
  await pool.query(`UPDATE accounts SET wins=wins+0,updated_at=NOW() WHERE id=$1`, [victim.accountId]);
}
function runtimeTerritory() {
  const ownerToRuntime=new Map(); for(const p of match.players.values()) ownerToRuntime.set(p.accountId,p.id);
  return Array.from(match.territory, owner => ownerToRuntime.get(owner)||0);
}
function playerSnapshot(p) { return { id:p.id,username:p.username,x:Math.round(p.x),y:Math.round(p.y),angle:p.angle,territory:p.territory,kills:p.kills,dead:p.dead,respawn_ms:p.dead?Math.max(0,p.respawnAt-Date.now()):0,skin:p.skin,connected:p.socket.readyState===WebSocket.OPEN }; }
function snapshotFor(p) { return { type:'state',world:{width:WORLD_WIDTH,height:WORLD_HEIGHT,cell_size:CELL_SIZE,grid_width:GRID_WIDTH,grid_height:GRID_HEIGHT},self_id:p.id,players:Array.from(match.players.values()).map(playerSnapshot),territory:runtimeTerritory() }; }
function send(ws,payload){if(ws.readyState===WebSocket.OPEN)ws.send(JSON.stringify(payload));}
function broadcast(payload){for(const p of match.players.values())send(p.socket,payload);}
function removePlayer(p){if(!p)return;match.players.delete(p.id);broadcast({type:'player_left',id:p.id});}
function handleGameMessage(p,raw){
  let m; try{m=JSON.parse(raw.toString());}catch{return;} if(!m||typeof m!=='object')return;
  if(m.type==='input'&&!p.dead){let x=Number(m.x),y=Number(m.y);if(!Number.isFinite(x)||!Number.isFinite(y))return;const l=Math.hypot(x,y);p.inputX=l>1?x/l:Math.max(-1,Math.min(1,x));p.inputY=l>1?y/l:Math.max(-1,Math.min(1,y));p.lastInputAt=Date.now();}
}
const gameWss=new WebSocketServer({noServer:true});
gameWss.on('connection',(socket,req,account)=>{
  if(match.players.size>=MAX_PLAYERS_PER_MATCH){send(socket,{type:'error',message:'Match is full'});socket.close();return;}
  const id=match.nextPlayerNumber++,spawn=spawnForNumber(id),skin=Number(account.selected_skin)||1;
  const p={id,accountId:Number(account.id),username:account.username,socket,x:spawn[0],y:spawn[1],angle:0,inputX:0,inputY:0,territory:0,kills:0,lastInputAt:Date.now(),dead:false,respawnAt:0,skin};
  match.players.set(id,p); paintStartTerritory(p);
  send(socket,snapshotFor(p)); broadcast({type:'player_joined',player:playerSnapshot(p)});
  socket.on('message',data=>handleGameMessage(p,data)); socket.on('close',()=>removePlayer(p)); socket.on('error',()=>removePlayer(p));
});

setInterval(async()=>{
  const now=Date.now();
  for(const p of match.players.values()){
    if(p.dead){if(now>=p.respawnAt){respawnPlayer(p);send(p.socket,{type:'respawned'});}continue;}
    if(now-p.lastInputAt>1000){p.inputX=0;p.inputY=0;}
    const l=Math.hypot(p.inputX,p.inputY);
    if(l>0.001){p.x+=(p.inputX/l)*PLAYER_SPEED*(TICK_MS/1000);p.y+=(p.inputY/l)*PLAYER_SPEED*(TICK_MS/1000);p.x=Math.max(20,Math.min(WORLD_WIDTH-20,p.x));p.y=Math.max(20,Math.min(WORLD_HEIGHT-20,p.y));p.angle=Math.atan2(p.inputY,p.inputX);paintMovementTerritory(p);}
  }
  const alive=[...match.players.values()].filter(p=>!p.dead);
  for(let i=0;i<alive.length;i++) for(let j=i+1;j<alive.length;j++){
    const a=alive[i],b=alive[j],d=Math.hypot(a.x-b.x,a.y-b.y);
    if(d<=COMBAT_DISTANCE){
      const attacker=Math.hypot(a.inputX,a.inputY)>0.15?a:b;
      const victim=attacker===a?b:a;
      clearPlayerTerritory(victim.accountId); victim.dead=true; victim.respawnAt=Date.now()+RESPAWN_MS; victim.territory=0; attacker.kills+=1;
      recordKill(attacker,victim).catch(e=>console.error('Kill persistence failed:',e.message));
      send(victim.socket,{type:'death',killer:attacker.username,respawn_ms:RESPAWN_MS});
      broadcast({type:'kill',killer_id:attacker.id,victim_id:victim.id,killer:attacker.username,victim:victim.username});
    }
  }
  if(match.players.size) broadcast({type:'state_tick',players:[...match.players.values()].map(playerSnapshot),territory:runtimeTerritory()});
},TICK_MS);
setInterval(()=>saveMatchState().catch(()=>{}),SAVE_MS);

const server=http.createServer(async(req,res)=>{
  res.setHeader('Access-Control-Allow-Origin','*');res.setHeader('Access-Control-Allow-Methods','GET,POST,OPTIONS');res.setHeader('Access-Control-Allow-Headers','Content-Type,Authorization');
  if(req.method==='OPTIONS'){res.writeHead(204);return res.end();}
  const u=new URL(req.url,`http://${req.headers.host||'localhost'}`),pathname=u.pathname;
  if(req.method==='GET'&&pages[pathname]){if(serveFile(res,path.join(publicRoot,pages[pathname])))return;}
  if(req.method==='GET'&&pathname==='/legal.css'){if(serveFile(res,path.join(publicRoot,'legal.css')))return;}
  if(req.method==='GET'&&pathname.startsWith('/assets/')){const rel=pathname.slice(8),fp=path.resolve(staticRoot,rel);if(fp.startsWith(staticRoot+path.sep)&&serveFile(res,fp))return;}
  if(req.method==='GET'&&pathname==='/auth/discord/start'){
    if(!DISCORD_CLIENT_ID||!DISCORD_CLIENT_SECRET||!OAUTH_STATE_SECRET)return sendJson(res,503,{error:'Discord login is not configured'});
    const supplied=u.searchParams.get('session'),id=supplied&&/^[a-f0-9-]{36}$/i.test(supplied)?supplied:crypto.randomUUID();
    await pool.query(`INSERT INTO login_sessions(id,expires_at)VALUES($1,NOW()+INTERVAL '10 minutes') ON CONFLICT(id)DO UPDATE SET status='pending',account_id=NULL,created_at=NOW(),expires_at=NOW()+INTERVAL '10 minutes',completed_at=NULL,session_token=NULL`,[id]);
    const state=createSignedState(id),params=new URLSearchParams({client_id:DISCORD_CLIENT_ID,response_type:'code',redirect_uri:DISCORD_REDIRECT_URI,scope:'identify',state});res.writeHead(302,{Location:`https://discord.com/oauth2/authorize?${params}`, 'Cache-Control':'no-store'});return res.end();
  }
  if(req.method==='GET'&&pathname==='/auth/discord/callback'){
    const code=u.searchParams.get('code'),state=u.searchParams.get('state'),id=readSignedState(state);if(!code||!id)return sendJson(res,400,{error:'Invalid Discord OAuth callback'});
    try{const check=await pool.query(`SELECT id FROM login_sessions WHERE id=$1 AND status='pending' AND expires_at>NOW()`,[id]);if(!check.rowCount)return sendJson(res,400,{error:'Login session expired or already used'});
      const body=new URLSearchParams({client_id:DISCORD_CLIENT_ID,client_secret:DISCORD_CLIENT_SECRET,grant_type:'authorization_code',code,redirect_uri:DISCORD_REDIRECT_URI});
      const tr=await fetch('https://discord.com/api/v10/oauth2/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body});if(!tr.ok)throw new Error('Discord token exchange failed');const tokenData=await tr.json();
      const ur=await fetch('https://discord.com/api/v10/users/@me',{headers:{Authorization:`Bearer ${tokenData.access_token}`}});if(!ur.ok)throw new Error('Discord user lookup failed');const user=await ur.json();const account=await upsertDiscordAccount(user);await completeLogin(id,account.id);
      res.writeHead(200,{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store'});return res.end('<!doctype html><html><body style="background:#090d16;color:#eef3ff;font-family:Arial;text-align:center;padding:60px"><h1>Discord connected</h1><p>تم تسجيل الدخول إلى ConquerX بنجاح. يمكنك العودة إلى اللعبة.</p></body></html>');
    }catch(e){console.error('Discord OAuth callback failed:',e.message);return sendJson(res,500,{error:'Discord login failed'});}
  }
  if(req.method==='GET'&&pathname==='/auth/discord/status'){
    const id=u.searchParams.get('session');if(!id||!/^[a-f0-9-]{36}$/i.test(id))return sendJson(res,400,{error:'Invalid session'});try{const login=await consumeLoginSession(id);if(!login)return sendJson(res,404,{status:'expired'});if(login.pending)return sendJson(res,200,{status:'pending'});return sendJson(res,200,{status:'completed',session_token:login.token,account:login.account});}catch(e){return sendJson(res,500,{error:'Login status failed'});}
  }
  const account=await getAccountFromToken(getBearerToken(req));
  if(req.method==='GET'&&pathname==='/me'){if(!account)return sendJson(res,401,{error:'Unauthorized'});return sendJson(res,200,{account});}
  if(req.method==='GET'&&pathname==='/profile'){if(!account)return sendJson(res,401,{error:'Unauthorized'});return sendJson(res,200,{profile:account,skins});}
  if(req.method==='GET'&&pathname==='/skins'){return sendJson(res,200,{skins});}
  if(req.method==='POST'&&pathname==='/profile/skin'){
    if(!account)return sendJson(res,401,{error:'Unauthorized'});try{const data=await readJsonBody(req),skinId=Number(data.skin_id);if(!skins.some(s=>s.id===skinId))return sendJson(res,400,{error:'Invalid skin'});const unlocked=Array.isArray(account.unlocked_skins)?account.unlocked_skins.map(Number):[1];if(!unlocked.includes(skinId))return sendJson(res,403,{error:'Skin locked'});await pool.query('UPDATE accounts SET selected_skin=$2,updated_at=NOW() WHERE id=$1',[account.id,skinId]);return sendJson(res,200,{selected_skin:skinId});}catch(e){return sendJson(res,400,{error:'Invalid request'});}
  }
  if(req.method==='GET'&&pathname==='/leaderboard'){
    const limit=Math.min(500,Math.max(1,Number(u.searchParams.get('limit')||500)));const sort=['gold','kills','gems','wins'].includes(u.searchParams.get('sort'))?u.searchParams.get('sort'):'gold';
    const r=await pool.query(`SELECT id,username,avatar,gold,gems,kills,wins,level,ROW_NUMBER() OVER(ORDER BY ${sort} DESC,id ASC) AS rank FROM accounts ORDER BY ${sort} DESC,id ASC LIMIT $1`,[limit]);return sendJson(res,200,{sort,leaderboard:r.rows});
  }
  res.setHeader('Content-Type','application/json; charset=utf-8');
  if(req.method==='GET'&&pathname==='/health'){try{const db=await checkDatabase();res.writeHead(200);return res.end(JSON.stringify({status:'ok',database:db?'connected':'disconnected',game:'ConquerX',realtime:'websocket',persistent_match:true}));}catch{res.writeHead(503);return res.end(JSON.stringify({status:'error',database:'disconnected'}));}}
  if(req.method==='GET'&&pathname==='/'){res.writeHead(200);return res.end(JSON.stringify({name:'ConquerX',status:'online',version:'0.5.0',features:['combat','respawn','leaderboard','profiles','50-skins','persistent-territory']}));}
  res.writeHead(404);res.end(JSON.stringify({error:'Not Found'}));
});

const gameWss=new WebSocketServer({noServer:true});
server.on('upgrade',async(req,socket,head)=>{try{const u=new URL(req.url,`http://${req.headers.host||'localhost'}`);if(u.pathname!=='/ws'){socket.destroy();return;}const account=await getAccountFromToken(u.searchParams.get('token')||'');if(!account){socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');socket.destroy();return;}gameWss.handleUpgrade(req,socket,head,ws=>gameWss.emit('connection',ws,req,account));}catch(e){socket.destroy();}});

gameWss.on('connection',(socket,req,account)=>{if(match.players.size>=MAX_PLAYERS_PER_MATCH){send(socket,{type:'error',message:'Match is full'});socket.close();return;}const id=match.nextPlayerNumber++,spawn=spawnForNumber(id),p={id,accountId:Number(account.id),username:account.username,socket,x:spawn[0],y:spawn[1],angle:0,inputX:0,inputY:0,territory:0,kills:0,lastInputAt:Date.now(),dead:false,respawnAt:0,skin:Number(account.selected_skin)||1};match.players.set(id,p);paintStartTerritory(p);send(socket,snapshotFor(p));broadcast({type:'player_joined',player:playerSnapshot(p)});socket.on('message',d=>handleGameMessage(p,d));socket.on('close',()=>removePlayer(p));socket.on('error',()=>removePlayer(p));});

server.listen(port,'0.0.0.0',async()=>{console.log(`ConquerX server listening on port ${port}`);try{await ensureDatabaseSchema();await loadMatchState();console.log('ConquerX database schema ready');}catch(e){console.error('Database schema initialization failed:',e.message);}});
async function shutdown(signal){console.log(`${signal}: shutting down ConquerX...`);await saveMatchState();server.close(async()=>{await pool.end();process.exit(0);});}
process.on('SIGTERM',()=>shutdown('SIGTERM'));process.on('SIGINT',()=>shutdown('SIGINT'));
