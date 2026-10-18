const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { Pool } = require('pg');

const port = Number(process.env.PORT || 3000);
const poolConfig = process.env.POSTGRESQL_ADDON_URI
  ? { connectionString: process.env.POSTGRESQL_ADDON_URI, ssl: { rejectUnauthorized: false } }
  : { host: process.env.POSTGRESQL_ADDON_HOST, port: Number(process.env.POSTGRESQL_ADDON_PORT || 5432), database: process.env.POSTGRESQL_ADDON_DB, user: process.env.POSTGRESQL_ADDON_USER, password: process.env.POSTGRESQL_ADDON_PASSWORD, ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false };
const pool = new Pool(poolConfig);

async function checkDatabase() {
  const result = await pool.query('SELECT 1 AS ok');
  return result.rows[0]?.ok === 1;
}

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

const server = http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') { res.writeHead(204); return res.end(); }

  const requestUrl = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const pathname = requestUrl.pathname;

  if (req.method === 'GET' && pages[pathname]) {
    if (serveFile(res, path.join(publicRoot, pages[pathname]))) return;
  }
  if (req.method === 'GET' && pathname === '/legal.css') {
    if (serveFile(res, path.join(publicRoot, 'legal.css'))) return;
  }
  if (req.method === 'GET' && pathname.startsWith('/assets/')) {
    const relativePath = pathname.slice('/assets/'.length);
    const filePath = path.resolve(staticRoot, relativePath);
    if (filePath.startsWith(staticRoot + path.sep) && serveFile(res, filePath)) return;
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
    return res.end(JSON.stringify({ name: 'ConquerX', status: 'online', version: '0.1.0' }));
  }
  res.writeHead(404);
  res.end(JSON.stringify({ error: 'Not Found' }));
});

server.listen(port, '0.0.0.0', () => console.log(`ConquerX server listening on port ${port}`));

async function shutdown(signal) {
  console.log(`${signal}: shutting down ConquerX server...`);
  server.close(async () => { await pool.end(); process.exit(0); });
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
