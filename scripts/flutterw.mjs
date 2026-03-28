import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const repoRoot = resolve(__dirname, '..');
const projectPath = resolve(repoRoot, 'apps/mobile');

function resolveFlutterExecutable() {
  if (process.env.VEIL_FLUTTER_BIN && existsSync(process.env.VEIL_FLUTTER_BIN)) {
    return process.env.VEIL_FLUTTER_BIN;
  }

  const puroConfigPath = join(projectPath, '.puro.json');
  if (existsSync(puroConfigPath)) {
    const puroConfig = JSON.parse(readFileSync(puroConfigPath, 'utf8'));
    if (puroConfig.env) {
      const executable =
        process.platform === 'win32'
          ? join(homedir(), '.puro', 'envs', puroConfig.env, 'flutter', 'bin', 'flutter.bat')
          : join(homedir(), '.puro', 'envs', puroConfig.env, 'flutter', 'bin', 'flutter');
      if (existsSync(executable)) {
        return executable;
      }
    }
  }

  return 'flutter';
}

const flutterExecutable = resolveFlutterExecutable();
const flutterArgs = process.argv.slice(2);

if (flutterArgs.length === 0) {
  console.error('Usage: node ./scripts/flutterw.mjs <flutter args...>');
  process.exit(1);
}

const result = spawnSync(flutterExecutable, flutterArgs, {
  cwd: projectPath,
  stdio: 'inherit',
  shell: process.platform === 'win32',
});

if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}

process.exit(result.status ?? 0);
