const http = require('node:http');
const { Pool } = require('pg');

const port = Number(process.env.PORT || 3000);

const poolConfig = process.env.POSTGRESQL_ADDON_URI
  ? { connectionString: process.env.POSTGRESQL_ADDON_URI, ssl: { rejectUnauthorized: false } }
  : {
      host: process.env.POSTGRESQL_ADDON_HOST,
      port: Number(process.env.POSTGRESQL_ADDON_PORT || 5432),
      database: process.env.POSTGRESQL_ADDON_DB,
      user: process.env.POSTGRESQL_ADDON_USER,
      password: process.env.POSTGRESQL_ADDON_PASSWORD,
      ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false
    };

const pool = new Pool(poolConfig);

async function checkDatabase() {
  const result = await pool.query('SELECT 1 AS ok');
  return result.rows[0]?.ok === 1;
}

const server = http.createServer(async (req, res) => {
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    return res.end();
  }

  if (req.method === 'GET' && req.url === '/health') {
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

  if (req.method === 'GET' && req.url === '/') {
    res.writeHead(200);
    return res.end(JSON.stringify({ name: 'ConquerX', status: 'online', version: '0.1.0' }));
  }

  res.writeHead(404);
  res.end(JSON.stringify({ error: 'Not Found' }));
});

server.listen(port, '0.0.0.0', () => {
  console.log(`ConquerX server listening on port ${port}`);
});

async function shutdown(signal) {
  console.log(`${signal}: shutting down ConquerX server...`);
  server.close(async () => {
    await pool.end();
    process.exit(0);
  });
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
