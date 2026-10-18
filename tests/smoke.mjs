import { readFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';

const server = await readFile('server.js', 'utf8');
const game = await readFile('game/scripts/game.gd', 'utf8');
const main = await readFile('game/scripts/main.gd', 'utf8');

const checks = [
  ['WebSocket server', /WebSocketServer/],
  ['matchmaking queue', /const queue = \[\]/],
  ['20-player rooms', /MAX_PLAYERS_PER_MATCH = 20/],
  ['3-minute matches', /MATCH_DURATION_MS = 180000/],
  ['match completion', /function finishMatch/],
  ['Gold/Gems shop route', /\/shop\/buy/],
  ['50 skins', /Array\.from\(\{length:50\}/],
  ['leaderboard route', /\/leaderboard/],
  ['profile route', /\/profile/],
  ['game WebSocket client', /WebSocketPeer/],
  ['game matchmaking handling', /t === "matchmaking"/],
  ['match end UI', /_show_match_end/],
  ['shop UI', /_show_shop/],
  ['settings UI', /_show_settings/],
  ['home page', /_show_home/],
  ['Discord login', /discord/]
];

for (const [name, pattern] of checks) {
  if (!pattern.test(server + '\n' + game + '\n' + main)) {
    throw new Error(`Smoke check failed: ${name}`);
  }
}

const syntax = spawnSync(process.execPath, ['--check', 'server.js'], { encoding: 'utf8' });
if (syntax.status !== 0) {
  process.stderr.write(syntax.stderr || syntax.stdout || 'server.js syntax check failed\n');
  process.exit(syntax.status || 1);
}

console.log(`ConquerX smoke checks passed: ${checks.length} feature checks + server syntax`);
