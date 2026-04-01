import { existsSync, lstatSync, mkdirSync, readFileSync, rmSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
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

function maybeCleanNativeAssetOutputs(args, basePath = projectPath) {
  if (process.platform !== 'win32') {
    return;
  }

  if (args[0] !== 'test') {
    return;
  }

  const buildPath = resolve(basePath, 'build');
  const externalBuildPath = resolve(tmpdir(), 'veil_mobile_flutter_build');

  mkdirSync(externalBuildPath, { recursive: true });

  try {
    const buildStats = lstatSync(buildPath);
    if (!buildStats.isSymbolicLink()) {
      rmSync(buildPath, { recursive: true, force: true });
    }
  } catch {
    // Build path does not exist yet.
  }

  if (!existsSync(buildPath)) {
    spawnSync(
      'cmd',
      ['/c', 'mklink', '/J', buildPath, externalBuildPath],
      {
        stdio: 'ignore',
        shell: true,
      },
    );
  }

  spawnSync('taskkill', ['/IM', 'veil_mobile.exe', '/F', '/T'], {
    stdio: 'ignore',
    shell: true,
  });

  const cleanupTargets = [
    resolve(externalBuildPath, 'native_assets'),
    resolve(externalBuildPath, 'windows', 'x64', 'runner'),
  ];

  const escapedTargets = cleanupTargets
    .map((target) => `'${target.replace(/'/g, "''")}'`)
    .join(', ');

  spawnSync(
    'powershell',
    [
      '-NoProfile',
      '-Command',
      [
        `$targets = @(${escapedTargets})`,
        'foreach ($target in $targets) {',
        '  if (Test-Path -LiteralPath $target) {',
        '    attrib -R "$target\\*" /S /D 2>$null | Out-Null',
        '    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue',
        '  }',
        '}',
      ].join(' '),
    ],
    {
      stdio: 'ignore',
      shell: true,
    },
  );

  for (const target of cleanupTargets) {
    if (existsSync(target)) {
      try {
        rmSync(target, { recursive: true, force: true });
      } catch {
        // Ignore best-effort cleanup failures and let Flutter continue.
      }
    }
  }
}

function prepareWindowsTestWorkspace(args) {
  if (process.platform !== 'win32' || args[0] !== 'test') {
    return projectPath;
  }

  const workspacePath = resolve(tmpdir(), 'veil_mobile_flutter_test_workspace');

  mkdirSync(workspacePath, { recursive: true });

  const robocopy = spawnSync(
    'robocopy',
    [
      projectPath,
      workspacePath,
      '/MIR',
      '/XD',
      'build',
      '.dart_tool',
      '.idea',
      '.vscode',
      '/XF',
      'flutter_*.log',
    ],
    {
      stdio: 'ignore',
      shell: true,
    },
  );

  const robocopyCode = robocopy.status ?? 16;
  if (robocopyCode > 7) {
    console.error(`Failed to prepare Flutter test workspace (robocopy exit ${robocopyCode}).`);
    process.exit(1);
  }

  return workspacePath;
}

const flutterWorkingDirectory = prepareWindowsTestWorkspace(flutterArgs);

maybeCleanNativeAssetOutputs(flutterArgs, flutterWorkingDirectory);

const result = spawnSync(flutterExecutable, flutterArgs, {
  cwd: flutterWorkingDirectory,
  stdio: 'inherit',
  shell: process.platform === 'win32',
});

if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}

process.exit(result.status ?? 0);
