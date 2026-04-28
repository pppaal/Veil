// Dev runner: tsc --watch builds into dist/, node --watch restarts on file changes.
// Replaces `tsx watch` because tsx (esbuild) does not emit decorator metadata,
// which NestJS's DI relies on to wire constructor parameters.
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';

const tsc = spawn(
  './node_modules/.bin/tsc',
  ['-w', '-p', 'tsconfig.build.json', '--preserveWatchOutput'],
  { stdio: 'inherit', shell: false },
);

let node = null;
function startNode() {
  if (node) return;
  if (!existsSync('dist/main.js')) {
    setTimeout(startNode, 300);
    return;
  }
  node = spawn('node', ['--watch', '--watch-path', 'dist', 'dist/main.js'], {
    stdio: 'inherit',
    shell: false,
  });
  node.on('exit', (code) => {
    if (code !== 0 && code !== null) console.error(`[dev] node exited with code ${code}`);
    tsc.kill('SIGTERM');
    process.exit(code ?? 0);
  });
}
startNode();

const shutdown = () => {
  try { node?.kill('SIGTERM'); } catch {}
  try { tsc.kill('SIGTERM'); } catch {}
  process.exit(0);
};
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
