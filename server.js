const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { Pool } = require('pg');
const { WebSocketServer, WebSocket } = require('ws');

const port = Number(process.env.PORT || 3000);
const pool = new Pool(process.env.POSTGRESQL_ADDON_URI
  ? { connectionString: process.env.POSTGRESQL_ADDON_URI, ssl: { rejectUnauthorized: false } }
  : { host: process.env.POSTGRESQL_ADDON_HOST, port: Number(process.env.POSTGRESQL_ADDON_PORT || 5432), database: process.env.POSTGRESQL_ADDON_DB, user: process.env.POSTGRESQL_ADDON_USER, password: process.env.POSTGRESQL_ADDON_PASSWORD, ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false });

const SERVER_URL = 'https://app-4729a9fe-87fc-4f1b-9248-112725e0db57.cleverapps.io';
const DISCORD_CLIENT_ID = process.env.DISCORD_CLIENT_ID || '';
const DISCORD_CLIENT_SECRET = process.env.DISCORD_CLIENT_SECRET || '';
const DISCORD_REDIRECT_URI = process.env.DISCORD_REDIRECT_URI || `${SERVER_URL}/auth/discord/callback`;
const LOGIN_SESSION_TTL_MS = 10 * 60 * 1000;
const WORLD_WIDTH = 4000;
const WORLD_HEIGHT = 2400;
const CELL_SIZE = 50;
const GRID_WIDTH = WORLD_WIDTH / CELL_SIZE;
const GRID_HEIGHT = WORLD_HEIGHT / CELL_SIZE;
const TICK_MS = 50;
const PLAYER_SPEED = 340;
const MAX_PLAYERS_PER_MATCH = 20;
const MATCH_MIN_PLAYERS = 2;
const MATCH_START_DELAY_MS = 5000;
const MATCH_DURATION_MS = 180000;
const RESPAWN_MS = 2500;
const COMBAT_DISTANCE = 48;

const publicRoot = path.join(__dirname, 'public');
const staticRoot = path.join(__dirname, 'assets');
const pages = { '/terms-of-service': 'terms-of-service.html', '/privacy-policy': 'privacy-policy.html' };
const mimeTypes = { '.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.png':'image/png','.jpg':'image/jpeg','.jpeg':'image/jpeg','.webp':'image/webp','.gif':'image/gif','.svg':'image/svg+xml' };

function sendJson(res, code, body) { res.writeHead(code, {'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'}); res.end(JSON.stringify(body)); }
function serveFile(res, file) { try { const ext=path.extname(file).toLowerCase(); res.writeHead(200, {'Content-Type':mimeTypes[ext] || 'application/octet-stream'}); res.end(fs.readFileSync(file)); return true; } catch { return false; } }
function createToken() { return crypto.randomBytes(32).toString('base64url'); }
function bearer(req) { const h=req.headers.authorization || ''; return h.startsWith('Bearer ') ? h.slice(7).trim() : ''; }
async function readJson(req) { return new Promise((resolve,reject)=>{ let body=''; req.on('data',c=>{body+=c; if(body.length>20000) req.destroy();}); req.on('end',()=>{try{resolve(body?JSON.parse(body):{});}catch(e){reject(e);}}); req.on('error',reject); }); }
function signedState(id) { const payload=`${id}.${Date.now()}`; const sig=crypto.createHmac('sha256',DISCORD_CLIENT_SECRET).update(payload).digest('base64url'); return `${Buffer.from(payload).toString('base64url')}.${sig}`; }
function readState(state) { try { const [enc,sig]=String(state||'').split('.'); const payload=Buffer.from(enc,'base64url').toString('utf8'); const expected=crypto.createHmac('sha256',DISCORD_CLIENT_SECRET).update(payload).digest('base64url'); if(!sig||sig!==expected)return null; const dot=payload.lastIndexOf('.'); const id=payload.slice(0,dot); const issued=Number(payload.slice(dot+1)); return Date.now()-issued<=LOGIN_SESSION_TTL_MS && /^[a-f0-9-]{36}$/i.test(id) ? id : null; } catch { return null; } }

const skins = Array.from({length:50},(_,i)=>({ id:i+1, name:`Skin ${String(i+1).padStart(2,'0')}`, rarity:i<25?'Common':i<40?'Rare':i<48?'Epic':'Legendary', gold_cost:i===0?0:(i<25?250+i*50:i<40?1500+i*75:3500+i*120), gems_cost:i<25?0:(i<40?20+i:50+i*2), hue:Math.round(i*360/50) }));
const shopItems = [
  {id:'gold_500',name:'500 Gold',type:'gold',gold_cost:0,gems_cost:25,amount:500},
  {id:'gold_2500',name:'2500 Gold',type:'gold',gold_cost:0,gems_cost:100,amount:2500},
  {id:'gems_50',name:'50 Gems',type:'gems',gold_cost:5000,gems_cost:0,amount:50},
  {id:'gems_250',name:'250 Gems',type:'gems',gold_cost:20000,gems_cost:0,amount:250}
];

async function schema() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS accounts (
      id BIGSERIAL PRIMARY KEY, discord_user_id TEXT UNIQUE, username TEXT NOT NULL, avatar TEXT,
      gold INTEGER NOT NULL DEFAULT 500, gems INTEGER NOT NULL DEFAULT 25, kills INTEGER NOT NULL DEFAULT 0,
      wins INTEGER NOT NULL DEFAULT 0, level INTEGER NOT NULL DEFAULT 1, xp INTEGER NOT NULL DEFAULT 0,
      selected_skin INTEGER NOT NULL DEFAULT 1, unlocked_skins JSONB NOT NULL DEFAULT '[1]'::jsonb,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    ALTER TABLE accounts ADD COLUMN IF NOT EXISTS gold INTEGER NOT NULL DEFAULT 500;
    ALTER TABLE accounts ADD COLUMN IF NOT EXISTS gems INTEGER NOT NULL DEFAULT 25;
    ALTER TABLE accounts ADD COLUMN IF NOT EXISTS kills INTEGER NOT NULL DEFAULT 0;
    ALTER TABLE accounts ADD COLUMN IF NOT EXISTS wins INTEGER NOT NULL DEFAULT 0;
    ALTER TABLE accounts ADD COLUMN IF NOT EXISTS level INTEGER NOT NULL DEFAULT 1;
    ALTER TABLE accounts ADD COLUMN IF NOT EXISTS xp INTEGER NOT NULL DEFAULT 0;
    ALTER TABLE accounts ADD COLUMN IF NOT EXISTS selected_skin INTEGER NOT NULL DEFAULT 1;
    ALTER TABLE accounts ADD COLUMN IF NOT EXISTS unlocked_skins JSONB NOT NULL DEFAULT '[1]'::jsonb;
    CREATE TABLE IF NOT EXISTS login_sessions(id UUID PRIMARY KEY,status TEXT NOT NULL DEFAULT 'pending',account_id BIGINT REFERENCES accounts(id) ON DELETE SET NULL,created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),expires_at TIMESTAMPTZ NOT NULL,completed_at TIMESTAMPTZ,session_token TEXT);
    CREATE TABLE IF NOT EXISTS app_sessions(token_hash TEXT PRIMARY KEY,account_id BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),expires_at TIMESTAMPTZ NOT NULL);
    CREATE TABLE IF NOT EXISTS matches(id TEXT PRIMARY KEY,status TEXT NOT NULL DEFAULT 'waiting',started_at TIMESTAMPTZ,ended_at TIMESTAMPTZ,created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),winner_account_id BIGINT REFERENCES accounts(id) ON DELETE SET NULL);
    CREATE TABLE IF NOT EXISTS match_results(id BIGSERIAL PRIMARY KEY,match_id TEXT NOT NULL,account_id BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,territory INTEGER NOT NULL DEFAULT 0,kills INTEGER NOT NULL DEFAULT 0,place INTEGER NOT NULL DEFAULT 0,gold_reward INTEGER NOT NULL DEFAULT 0,gems_reward INTEGER NOT NULL DEFAULT 0,xp_reward INTEGER NOT NULL DEFAULT 0,created_at TIMESTAMPTZ NOT NULL DEFAULT NOW());
    CREATE INDEX IF NOT EXISTS idx_app_sessions_account_id ON app_sessions(account_id);
    CREATE INDEX IF NOT EXISTS idx_match_results_account_id ON match_results(account_id);
  `);
}
async function accountFromToken(token) { if(!token)return null; const hash=crypto.createHash('sha256').update(token).digest('hex'); const r=await pool.query(`SELECT a.id,a.username,a.avatar,a.gold,a.gems,a.kills,a.wins,a.level,a.xp,a.selected_skin,a.unlocked_skins FROM app_sessions s JOIN accounts a ON a.id=s.account_id WHERE s.token_hash=$1 AND s.expires_at>NOW()`,[hash]); return r.rows[0]||null; }
async function upsertDiscordAccount(user) { const username=user.global_name||user.username||`Player_${String(user.id).slice(-6)}`; const r=await pool.query(`INSERT INTO accounts(discord_user_id,username,avatar) VALUES($1,$2,$3) ON CONFLICT(discord_user_id) DO UPDATE SET username=EXCLUDED.username,avatar=EXCLUDED.avatar,updated_at=NOW() RETURNING id,username,avatar,gold,gems,kills,wins,level,xp,selected_skin,unlocked_skins`,[user.id,username,user.avatar||null]); return r.rows[0]; }
async function completeLogin(id,accountId) { const token=createToken(),hash=crypto.createHash('sha256').update(token).digest('hex'); const c=await pool.connect(); try{await c.query('BEGIN'); await c.query(`UPDATE login_sessions SET status='completed',account_id=$2,completed_at=NOW(),session_token=$3 WHERE id=$1 AND status='pending'`,[id,accountId,token]); await c.query(`INSERT INTO app_sessions(token_hash,account_id,expires_at) VALUES($1,$2,NOW()+INTERVAL '30 days')`,[hash,accountId]); await c.query('COMMIT'); return token;}catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();} }
async function getAccount(id){ const r=await pool.query(`SELECT id,username,avatar,gold,gems,kills,wins,level,xp,selected_skin,unlocked_skins FROM accounts WHERE id=$1`,[id]); return r.rows[0]||null; }
function levelNeed(level){return 500 + Math.max(0,level-1)*250;}
async function addProgress(accountId,xp,gold,gems,win=false){ const r=await pool.query(`SELECT level,xp FROM accounts WHERE id=$1`,[accountId]); if(!r.rowCount)return; let level=Number(r.rows[0].level),total=Number(r.rows[0].xp)+xp; let levels=0; while(total>=levelNeed(level)){total-=levelNeed(level);level++;levels++;} await pool.query(`UPDATE accounts SET xp=$2,level=$3,gold=gold+$4,gems=gems+$5,wins=wins+$6,updated_at=NOW() WHERE id=$1`,[accountId,total,level,gold,gems,win?1:0]); return {level,levels}; }

const queue=[];
const matches=new Map();
let nextMatch=1;
let nextPlayer=1;
function newMatch(){ const id=`match-${Date.now().toString(36)}-${nextMatch++}`; const m={id,status:'waiting',players:new Map(),territory:new Uint32Array(GRID_WIDTH*GRID_HEIGHT),createdAt:Date.now(),startedAt:0,endedAt:0}; matches.set(id,m); pool.query(`INSERT INTO matches(id,status) VALUES($1,'waiting') ON CONFLICT(id) DO NOTHING`,[id]).catch(()=>{}); return m; }
function spawn(slot){const margin=250;const slots=[[margin,margin],[WORLD_WIDTH-margin,margin],[margin,WORLD_HEIGHT-margin],[WORLD_WIDTH-margin,WORLD_HEIGHT-margin],[WORLD_WIDTH/2,WORLD_HEIGHT/2],[WORLD_WIDTH/2,margin],[WORLD_WIDTH/2,WORLD_HEIGHT-margin],[margin,WORLD_HEIGHT/2],[WORLD_WIDTH-margin,WORLD_HEIGHT/2]];return slots[slot%slots.length].slice();}
function paintStart(m,p){const cx=Math.floor(p.x/CELL_SIZE),cy=Math.floor(p.y/CELL_SIZE);let n=0;for(let y=cy-2;y<=cy+2;y++)for(let x=cx-2;x<=cx+2;x++)if(x>=0&&x<GRID_WIDTH&&y>=0&&y<GRID_HEIGHT){const i=y*GRID_WIDTH+x;if(m.territory[i]===0){m.territory[i]=p.accountId;n++;}}p.territory+=n;}
function clearTerritory(m,id){for(let i=0;i<m.territory.length;i++)if(m.territory[i]===id)m.territory[i]=0;}
function runtimeTerritory(m){const map=new Map();for(const p of m.players.values())map.set(p.accountId,p.id);return Array.from(m.territory,v=>map.get(v)||0);}
function snapPlayer(p){return{id:p.id,username:p.username,x:Math.round(p.x),y:Math.round(p.y),angle:p.angle,territory:p.territory,kills:p.kills,dead:p.dead,respawn_ms:p.dead?Math.max(0,p.respawnAt-Date.now()):0,skin:p.skin};}
function send(ws,p){if(ws.readyState===WebSocket.OPEN)ws.send(JSON.stringify(p));}
function broadcast(m,p){for(const x of m.players.values())send(x.socket,p);}
function state(m,p){return{type:'state',match_id:m.id,match_status:m.status,match_remaining_ms:m.status==='playing'?Math.max(0,MATCH_DURATION_MS-(Date.now()-m.startedAt)):0,world:{width:WORLD_WIDTH,height:WORLD_HEIGHT,cell_size:CELL_SIZE,grid_width:GRID_WIDTH,grid_height:GRID_HEIGHT},self_id:p.id,players:Array.from(m.players.values()).map(snapPlayer),territory:runtimeTerritory(m)};}
function enqueue(account,socket){let m=matches.get(queue[0]?.matchId); if(!m||m.status!=='waiting'||m.players.size>=MAX_PLAYERS_PER_MATCH)m=newMatch(); const p={accountId:Number(account.id),username:account.username,socket,skin:Number(account.selected_skin)||1,id:nextPlayer++,x:0,y:0,angle:0,inputX:0,inputY:0,territory:0,kills:0,dead:false,respawnAt:0,match:m}; const slot=m.players.size; [p.x,p.y]=spawn(slot); m.players.set(p.id,p); queue.push({matchId:m.id,player:p}); send(socket,{type:'matchmaking',match_id:m.id,players:m.players.size,max_players:MAX_PLAYERS_PER_MATCH,eta_ms:Math.max(0,MATCH_START_DELAY_MS-(Date.now()-m.createdAt))}); return p; }
function startReadyMatches(){for(const m of matches.values()){if(m.status!=='waiting')continue;const age=Date.now()-m.createdAt;if(m.players.size>=MATCH_MIN_PLAYERS&&(age>=MATCH_START_DELAY_MS||m.players.size>=MAX_PLAYERS_PER_MATCH)){m.status='playing';m.startedAt=Date.now();m.players.forEach(p=>{paintStart(m,p);send(p.socket,{type:'match_found',match_id:m.id,players:m.players.size,starts_in_ms:0});send(p.socket,state(m,p));});pool.query(`UPDATE matches SET status='playing',started_at=NOW() WHERE id=$1`,[m.id]).catch(()=>{});}}}
function removeQueuePlayer(p){const i=queue.findIndex(x=>x.player===p);if(i>=0)queue.splice(i,1);}
async function finishMatch(m,reason='time'){if(m.status==='finished')return;m.status='finished';m.endedAt=Date.now();const ranked=Array.from(m.players.values()).sort((a,b)=>b.territory-a.territory||b.kills-a.kills);const winner=ranked[0];for(let i=0;i<ranked.length;i++){const p=ranked[i];const place=i+1;const win=place===1;const gold=win?500:Math.max(50,300-(place-1)*15);const gems=win?10:(place<=3?4:1);const xp=win?700:350;await addProgress(p.accountId,xp,gold,gems,win);await pool.query(`INSERT INTO match_results(match_id,account_id,territory,kills,place,gold_reward,gems_reward,xp_reward) VALUES($1,$2,$3,$4,$5,$6,$7,$8)`,[m.id,p.accountId,p.territory,p.kills,place,gold,gems,xp]);send(p.socket,{type:'match_end',reason,winner_id:winner?.id||0,place,gold_reward:gold,gems_reward:gems,xp_reward:xp,level_up:false,results:ranked.slice(0,10).map((r,j)=>({place:j+1,username:r.username,territory:r.territory,kills:r.kills}))});}await pool.query(`UPDATE matches SET status='finished',ended_at=NOW(),winner_account_id=$2 WHERE id=$1`,[m.id,winner?.accountId||null]);}
async function killPlayer(m,killer,victim){if(victim.dead)return;victim.dead=true;victim.respawnAt=Date.now()+RESPAWN_MS;clearTerritory(m,victim.accountId);victim.territory=0;if(killer){killer.kills++;await pool.query(`UPDATE accounts SET kills=kills+1,updated_at=NOW() WHERE id=$1`,[killer.accountId]);broadcast(m,{type:'kill',killer_id:killer.id,killer:killer.username,victim_id:victim.id,victim:victim.username});send(victim.socket,{type:'death',killer:killer.username,respawn_ms:RESPAWN_MS});}else send(victim.socket,{type:'death',killer:'the arena',respawn_ms:RESPAWN_MS});}
function handleMessage(p,raw){let m;try{m=JSON.parse(raw.toString());}catch{return;}if(m.type==='input'&&p.match.status==='playing'&&!p.dead){let x=Number(m.x),y=Number(m.y);if(!Number.isFinite(x)||!Number.isFinite(y))return;const l=Math.hypot(x,y);p.inputX=l>1?x/l:Math.max(-1,Math.min(1,x));p.inputY=l>1?y/l:Math.max(-1,Math.min(1,y));}}
const wss=new WebSocketServer({noServer:true});
wss.on('connection',(socket,_req,account)=>{const p=enqueue(account,socket);socket.on('message',d=>handleMessage(p,d));socket.on('close',()=>{removeQueuePlayer(p);p.match.players.delete(p.id);});socket.on('error',()=>{removeQueuePlayer(p);p.match.players.delete(p.id);});});

setInterval(async()=>{startReadyMatches();const now=Date.now();for(const m of matches.values()){if(m.status!=='playing')continue;for(const p of m.players.values()){if(p.dead){if(now>=p.respawnAt){const slot=(p.id-1)%9;[p.x,p.y]=spawn(slot);p.inputX=0;p.inputY=0;p.dead=false;paintStart(m,p);send(p.socket,{type:'respawned',match_id:m.id});}continue;}p.x=Math.max(0,Math.min(WORLD_WIDTH,p.x+p.inputX*PLAYER_SPEED*TICK_MS/1000));p.y=Math.max(0,Math.min(WORLD_HEIGHT,p.y+p.inputY*PLAYER_SPEED*TICK_MS/1000));if(Math.hypot(p.inputX,p.inputY)>0.05){p.angle=Math.atan2(p.inputY,p.inputX);const cx=Math.floor(p.x/CELL_SIZE),cy=Math.floor(p.y/CELL_SIZE);for(let y=cy-1;y<=cy+1;y++)for(let x=cx-1;x<=cx+1;x++)if(x>=0&&x<GRID_WIDTH&&y>=0&&y<GRID_HEIGHT)m.territory[y*GRID_WIDTH+x]=p.accountId;p.territory=0;for(const owner of m.territory)if(owner===p.accountId)p.territory++;}}
const active=Array.from(m.players.values()).filter(p=>!p.dead);for(let i=0;i<active.length;i++)for(let j=i+1;j<active.length;j++){const a=active[i],b=active[j];if(Math.hypot(a.x-b.x,a.y-b.y)<=COMBAT_DISTANCE){const aOwn=m.territory[Math.floor(a.y/CELL_SIZE)*GRID_WIDTH+Math.floor(a.x/CELL_SIZE)]===a.accountId;const bOwn=m.territory[Math.floor(b.y/CELL_SIZE)*GRID_WIDTH+Math.floor(b.x/CELL_SIZE)]===b.accountId;if(aOwn&&!bOwn)await killPlayer(m,a,b);else if(bOwn&&!aOwn)await killPlayer(m,b,a);}}
if(now-m.startedAt>=MATCH_DURATION_MS){await finishMatch(m,'time');}else{for(const p of m.players.values())send(p.socket,{type:'state_tick',match_id:m.id,match_remaining_ms:Math.max(0,MATCH_DURATION_MS-(now-m.startedAt)),territory:runtimeTerritory(m),players:Array.from(m.players.values()).map(snapPlayer)});}}
},TICK_MS);
setInterval(()=>{for(const [id,m] of matches){if((m.status==='finished'||m.players.size===0)&&Date.now()-Math.max(m.endedAt,m.createdAt)>60000)matches.delete(id);}},30000);

async function discordUser(code){const tokenRes=await fetch('https://discord.com/api/oauth2/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({client_id:DISCORD_CLIENT_ID,client_secret:DISCORD_CLIENT_SECRET,grant_type:'authorization_code',code,redirect_uri:DISCORD_REDIRECT_URI})});if(!tokenRes.ok)throw new Error('Discord token exchange failed');const token=await tokenRes.json();const userRes=await fetch('https://discord.com/api/users/@me',{headers:{Authorization:`Bearer ${token.access_token}`}});if(!userRes.ok)throw new Error('Discord user fetch failed');return userRes.json();}

const server=http.createServer(async(req,res)=>{try{const url=new URL(req.url,SERVER_URL);if(req.method==='GET'&&url.pathname==='/health')return sendJson(res,200,{ok:true,service:'ConquerX',rooms:Array.from(matches.values()).filter(m=>m.status==='playing').length});if(req.method==='GET'&&url.pathname==='/'){return serveFile(res,path.join(publicRoot,'index.html'))||sendJson(res,200,{service:'ConquerX'});}if(req.method==='GET'&&pages[url.pathname])return serveFile(res,path.join(publicRoot,pages[url.pathname]))||sendJson(res,404,{error:'Not found'});
if(req.method==='GET'&&url.pathname==='/auth/discord/start'){const id=url.searchParams.get('session');if(!id)return sendJson(res,400,{error:'session required'});await pool.query(`INSERT INTO login_sessions(id,status,expires_at) VALUES($1,'pending',NOW()+INTERVAL '10 minutes') ON CONFLICT(id) DO UPDATE SET status='pending',expires_at=NOW()+INTERVAL '10 minutes',session_token=NULL`,[id]);const state=signedState(id);const auth=`https://discord.com/oauth2/authorize?client_id=${encodeURIComponent(DISCORD_CLIENT_ID)}&response_type=code&redirect_uri=${encodeURIComponent(DISCORD_REDIRECT_URI)}&scope=identify&state=${encodeURIComponent(state)}`;res.writeHead(302,{Location:auth});return res.end();}
if(req.method==='GET'&&url.pathname==='/auth/discord/callback'){const id=readState(url.searchParams.get('state'));const code=url.searchParams.get('code');if(!id||!code){res.writeHead(400);return res.end('Invalid Discord login state.');}try{const user=await discordUser(code);const account=await upsertDiscordAccount(user);await completeLogin(id,account.id);res.writeHead(200,{'Content-Type':'text/html; charset=utf-8'});return res.end('<!doctype html><html><head><meta name="viewport" content="width=device-width"><title>ConquerX</title></head><body style="background:#101827;color:white;font-family:sans-serif;text-align:center;padding:60px"><h1>ConquerX</h1><p>Discord connected successfully.</p><p>You can return to the game now.</p></body></html>');}catch(e){res.writeHead(500);return res.end(`Discord login failed: ${e.message}`);}}
if(req.method==='GET'&&url.pathname==='/auth/discord/status'){const id=url.searchParams.get('session');const r=await pool.query(`SELECT ls.status,ls.session_token,a.id,a.username,a.avatar,a.gold,a.gems,a.kills,a.wins,a.level,a.xp,a.selected_skin,a.unlocked_skins FROM login_sessions ls LEFT JOIN accounts a ON a.id=ls.account_id WHERE ls.id=$1 AND ls.expires_at>NOW()`,[id]);if(!r.rowCount)return sendJson(res,404,{status:'expired'});const x=r.rows[0];return sendJson(res,200,{status:x.status,session_token:x.session_token||null,account:x.id?x:null});}
const account=await accountFromToken(bearer(req));
if(req.method==='GET'&&url.pathname==='/me'){if(!account)return sendJson(res,401,{error:'Unauthorized'});return sendJson(res,200,{account});}
if(req.method==='GET'&&url.pathname==='/profile'){if(!account)return sendJson(res,401,{error:'Unauthorized'});return sendJson(res,200,{profile:account});}
if(req.method==='GET'&&url.pathname==='/shop'){return sendJson(res,200,{skins,items:shopItems});}
if(req.method==='POST'&&url.pathname==='/profile/skin'){if(!account)return sendJson(res,401,{error:'Unauthorized'});const body=await readJson(req);const id=Number(body.skin_id);const unlocked=Array.isArray(account.unlocked_skins)?account.unlocked_skins.map(Number):[1];if(!unlocked.includes(id))return sendJson(res,403,{error:'Skin is locked'});await pool.query('UPDATE accounts SET selected_skin=$2,updated_at=NOW() WHERE id=$1',[account.id,id]);return sendJson(res,200,{selected_skin:id});}
if(req.method==='POST'&&url.pathname==='/shop/buy'){if(!account)return sendJson(res,401,{error:'Unauthorized'});const body=await readJson(req);const type=String(body.type||'skin');const id=Number(body.id||0);const c=await pool.connect();try{await c.query('BEGIN');const a=(await c.query('SELECT gold,gems,unlocked_skins FROM accounts WHERE id=$1 FOR UPDATE',[account.id])).rows[0];if(type==='skin'){const s=skins.find(x=>x.id===id);if(!s)throw new Error('Skin not found');const unlocked=Array.isArray(a.unlocked_skins)?a.unlocked_skins.map(Number):[1];if(unlocked.includes(id)){await c.query('ROLLBACK');return sendJson(res,400,{error:'Already unlocked'});}if(a.gold<s.gold_cost||a.gems<s.gems_cost){await c.query('ROLLBACK');return sendJson(res,400,{error:'Not enough currency'});}const next=[...unlocked,id];await c.query(`UPDATE accounts SET gold=gold-$2,gems=gems-$3,unlocked_skins=$4::jsonb,updated_at=NOW() WHERE id=$1`,[account.id,s.gold_cost,s.gems_cost,JSON.stringify(next)]);await c.query('COMMIT');return sendJson(res,200,{ok:true,purchased:id,unlocked_skins:next});}const item=shopItems.find(x=>x.id===String(body.id));if(!item)throw new Error('Item not found');if(a.gold<item.gold_cost||a.gems<item.gems_cost){await c.query('ROLLBACK');return sendJson(res,400,{error:'Not enough currency'});}const addGold=item.type==='gold'?item.amount:0,addGems=item.type==='gems'?item.amount:0;await c.query(`UPDATE accounts SET gold=gold-$2+${addGold?'$4':'0'},gems=gems-$3+${addGems?'$5':'0'},updated_at=NOW() WHERE id=$1`,[account.id,item.gold_cost,item.gems_cost,addGold,addGems]);await c.query('COMMIT');return sendJson(res,200,{ok:true});}catch(e){await c.query('ROLLBACK');return sendJson(res,400,{error:e.message});}finally{c.release();}}
if(req.method==='GET'&&url.pathname==='/leaderboard'){const limit=Math.min(500,Math.max(1,Number(url.searchParams.get('limit')||500)));const sort=url.searchParams.get('sort')==='wins'?'wins':url.searchParams.get('sort')==='level'?'level':'gold';const r=await pool.query(`SELECT ROW_NUMBER() OVER(ORDER BY ${sort} DESC,level DESC,gold DESC) rank,username,gold,gems,kills,wins,level,xp FROM accounts ORDER BY ${sort} DESC,level DESC,gold DESC LIMIT $1`,[limit]);return sendJson(res,200,{leaderboard:r.rows});}
if(req.method==='GET'&&url.pathname==='/matchmaking/status'){if(!account)return sendJson(res,401,{error:'Unauthorized'});const q=queue.find(x=>x.player.accountId===Number(account.id));if(!q)return sendJson(res,200,{queued:false});return sendJson(res,200,{queued:true,match_id:q.matchId,players:q.player.match.players.size,max_players:MAX_PLAYERS_PER_MATCH});}
if(req.method==='POST'&&url.pathname==='/settings'){if(!account)return sendJson(res,401,{error:'Unauthorized'});return sendJson(res,200,{ok:true});}
return sendJson(res,404,{error:'Not found'});}catch(e){console.error(e);return sendJson(res,500,{error:'Server error'});}});

server.on('upgrade',async(req,socket,head)=>{try{const url=new URL(req.url,SERVER_URL);if(url.pathname!=='/ws'){socket.destroy();return;}const account=await accountFromToken(url.searchParams.get('token'));if(!account){socket.destroy();return;}wss.handleUpgrade(req,socket,head,ws=>wss.emit('connection',ws,req,account));}catch{socket.destroy();}});

schema().then(()=>server.listen(port,()=>console.log(`ConquerX server listening on port ${port}`))).catch(e=>{console.error('Database initialization failed:',e);process.exit(1);});
