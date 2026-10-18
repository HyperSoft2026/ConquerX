const http = require('node:http');
const { Pool } = require('pg');

const PUBLIC_PORT = Number(process.env.PORT || 8080);
const INTERNAL_PORT = Number(process.env.CONQUERX_INTERNAL_PORT || 3001);
process.env.PORT = String(INTERNAL_PORT);

const originalWriteHead = http.ServerResponse.prototype.writeHead;
http.ServerResponse.prototype.writeHead = function patchedWriteHead(...args) {
  if (this.headersSent) return this;
  return originalWriteHead.apply(this, args);
};

const pool = new Pool(process.env.POSTGRESQL_ADDON_URI
  ? { connectionString: process.env.POSTGRESQL_ADDON_URI, ssl: { rejectUnauthorized: false } }
  : { host: process.env.POSTGRESQL_ADDON_HOST, port: Number(process.env.POSTGRESQL_ADDON_PORT || 5432), database: process.env.POSTGRESQL_ADDON_DB, user: process.env.POSTGRESQL_ADDON_USER, password: process.env.POSTGRESQL_ADDON_PASSWORD, ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false });

const SEASON_ID = 'S01';
const SEASON_NAME_EN = 'ConquerX: Genesis';
const SEASON_NAME_AR = 'ConquerX: البداية';
const CHALLENGES = [
  { id: 'play_3', en: 'Play 3 matches', ar: 'العب 3 مباريات', target: 3, reward_gold: 250, reward_xp: 120, kind: 'matches' },
  { id: 'win_1', en: 'Win a match', ar: 'اربح مباراة', target: 1, reward_gold: 300, reward_xp: 180, kind: 'wins' },
  { id: 'kill_3', en: 'Get 3 eliminations', ar: 'حقق 3 إقصاءات', target: 3, reward_gold: 350, reward_xp: 160, kind: 'kills' },
  { id: 'territory_500', en: 'Capture 500 territory', ar: 'سيطر على 500 منطقة', target: 500, reward_gold: 400, reward_xp: 220, kind: 'territory' }
];

function bearer(req) {
  const value = req.headers.authorization || '';
  return value.startsWith('Bearer ') ? value.slice(7).trim() : '';
}

function json(res, status, body) {
  if (res.headersSent) return;
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(body));
}

async function accountFromToken(token) {
  if (!token) return null;
  const crypto = require('node:crypto');
  const hash = crypto.createHash('sha256').update(token).digest('hex');
  const r = await pool.query(`SELECT a.id,a.username FROM app_sessions s JOIN accounts a ON a.id=s.account_id WHERE s.token_hash=$1 AND s.expires_at>NOW()`, [hash]);
  return r.rows[0] || null;
}

async function setupSeasonDatabase() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS season_progress (
      account_id BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
      season_id TEXT NOT NULL,
      season_xp INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (account_id, season_id)
    );
    CREATE TABLE IF NOT EXISTS daily_challenges (
      account_id BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
      season_id TEXT NOT NULL,
      challenge_date DATE NOT NULL,
      challenge_id TEXT NOT NULL,
      progress INTEGER NOT NULL DEFAULT 0,
      claimed BOOLEAN NOT NULL DEFAULT FALSE,
      claimed_at TIMESTAMPTZ,
      PRIMARY KEY (account_id, season_id, challenge_date, challenge_id)
    );
    CREATE INDEX IF NOT EXISTS idx_daily_challenges_account ON daily_challenges(account_id, season_id, challenge_date);
  `);

  await pool.query(`
    CREATE OR REPLACE FUNCTION conquerx_apply_match_challenges() RETURNS trigger AS $$
    DECLARE
      today DATE := CURRENT_DATE;
      c RECORD;
      inc INTEGER;
      new_progress INTEGER;
      was_claimed BOOLEAN;
    BEGIN
      INSERT INTO season_progress(account_id, season_id, season_xp)
      VALUES(NEW.account_id, '${SEASON_ID}', 50 + NEW.kills * 10 + CASE WHEN NEW.place = 1 THEN 100 ELSE 0 END)
      ON CONFLICT(account_id, season_id) DO UPDATE
      SET season_xp = season_progress.season_xp + EXCLUDED.season_xp;

      FOR c IN SELECT * FROM (VALUES
        ('play_3', 3, 250, 120, 'matches'),
        ('win_1', 1, 300, 180, 'wins'),
        ('kill_3', 3, 350, 160, 'kills'),
        ('territory_500', 500, 400, 220, 'territory')
      ) AS x(id,target,reward_gold,reward_xp,kind) LOOP
        inc := CASE c.kind
          WHEN 'matches' THEN 1
          WHEN 'wins' THEN CASE WHEN NEW.place = 1 THEN 1 ELSE 0 END
          WHEN 'kills' THEN NEW.kills
          ELSE NEW.territory
        END;

        INSERT INTO daily_challenges(account_id,season_id,challenge_date,challenge_id,progress)
        VALUES(NEW.account_id,'${SEASON_ID}',today,c.id,LEAST(c.target,inc))
        ON CONFLICT(account_id,season_id,challenge_date,challenge_id) DO UPDATE
        SET progress = LEAST(c.target, daily_challenges.progress + EXCLUDED.progress)
        RETURNING progress INTO new_progress;

        SELECT claimed INTO was_claimed
        FROM daily_challenges
        WHERE account_id=NEW.account_id AND season_id='${SEASON_ID}' AND challenge_date=today AND challenge_id=c.id;

        IF new_progress >= c.target AND NOT was_claimed THEN
          UPDATE daily_challenges SET claimed=TRUE,claimed_at=NOW()
          WHERE account_id=NEW.account_id AND season_id='${SEASON_ID}' AND challenge_date=today AND challenge_id=c.id;
          UPDATE accounts SET gold=gold+c.reward_gold, xp=xp+c.reward_xp, updated_at=NOW() WHERE id=NEW.account_id;
        END IF;
      END LOOP;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;

    DROP TRIGGER IF EXISTS conquerx_match_challenges ON match_results;
    CREATE TRIGGER conquerx_match_challenges
    AFTER INSERT ON match_results
    FOR EACH ROW EXECUTE FUNCTION conquerx_apply_match_challenges();
  `);
}

async function seasonPayload(account) {
  const progress = await pool.query(`SELECT season_xp FROM season_progress WHERE account_id=$1 AND season_id=$2`, [account.id, SEASON_ID]);
  const xp = Number(progress.rows[0]?.season_xp || 0);
  const day = await pool.query(`SELECT challenge_id,progress,claimed FROM daily_challenges WHERE account_id=$1 AND season_id=$2 AND challenge_date=CURRENT_DATE`, [account.id, SEASON_ID]);
  const byId = new Map(day.rows.map(row => [row.challenge_id, row]));
  const challenges = CHALLENGES.map(c => ({ ...c, progress: Math.min(c.target, Number(byId.get(c.id)?.progress || 0)), claimed: Boolean(byId.get(c.id)?.claimed || false) }));
  return { season_id: SEASON_ID, name_en: SEASON_NAME_EN, name_ar: SEASON_NAME_AR, season_xp: xp, season_level: Math.floor(xp / 1000) + 1, daily_date: new Date().toISOString().slice(0, 10), challenges };
}

async function waitForCoreTables() {
  for (let i = 0; i < 60; i++) {
    try {
      const r = await pool.query(`SELECT to_regclass('public.accounts') AS accounts, to_regclass('public.match_results') AS results`);
      if (r.rows[0]?.accounts && r.rows[0]?.results) return;
    } catch (_) {}
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  throw new Error('ConquerX core database tables were not ready');
}

require('./server.js');

(async () => {
  try {
    await waitForCoreTables();
    await setupSeasonDatabase();
    console.log('ConquerX server-authoritative season system ready');
  } catch (error) {
    console.error('Season database initialization failed:', error);
    process.exit(1);
  }
})();

const gateway = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
    if ((req.method === 'GET' || req.method === 'HEAD') && (url.pathname === '/season' || url.pathname === '/daily-challenges')) {
      const account = await accountFromToken(bearer(req));
      if (!account) return json(res, 401, { error: 'Unauthorized' });
      return json(res, 200, await seasonPayload(account));
    }
    const proxy = http.request({ hostname: '127.0.0.1', port: INTERNAL_PORT, method: req.method, path: req.url, headers: req.headers }, upstream => {
      res.writeHead(upstream.statusCode || 502, upstream.headers);
      upstream.pipe(res);
    });
    proxy.on('error', error => json(res, 502, { error: 'Backend unavailable', detail: error.code || error.message }));
    req.pipe(proxy);
  } catch (error) {
    console.error('Gateway error:', error);
    json(res, 500, { error: 'Gateway error' });
  }
});

gateway.on('upgrade', (req, socket, head) => {
  const upstream = require('node:net').connect(INTERNAL_PORT, '127.0.0.1', () => {
    upstream.write(`${req.method} ${req.url} HTTP/${req.httpVersion}\r\n`);
    for (const [key, value] of Object.entries(req.headers)) upstream.write(`${key}: ${value}\r\n`);
    upstream.write('\r\n');
    if (head.length) upstream.write(head);
    socket.pipe(upstream).pipe(socket);
  });
  upstream.on('error', () => socket.destroy());
});

gateway.listen(PUBLIC_PORT, () => console.log(`ConquerX gateway listening on port ${PUBLIC_PORT}`));
