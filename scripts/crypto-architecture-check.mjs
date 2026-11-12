import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { dirname, join, normalize, relative, sep } from 'node:path';

const failures = [];

const read = (file) => readFileSync(file, 'utf8');

const assertNoMatch = (file, pattern, message) => {
  if (pattern.test(read(file))) {
    failures.push(`${message}: ${file}`);
  }
};

const assertMatch = (file, pattern, message) => {
  if (!pattern.test(read(file))) {
    failures.push(`${message}: ${file}`);
  }
};

const mobileSrc = 'apps/mobile/lib/src';
const messengerFacade = `${mobileSrc}/features/conversations/data/veil_messenger_controller.dart`;
const messengerServicesDir = `${mobileSrc}/features/conversations/data/messenger`;

// What app_state.dart used to declare now lives in these files; app_state.dart
// only re-exports them. None may reach for a mock or concrete implementation.
const appStateSuccessors = [
  `${mobileSrc}/app/app_state.dart`,
  `${mobileSrc}/core/di/core_providers.dart`,
  `${mobileSrc}/app/session/app_session_controller.dart`,
  `${mobileSrc}/app/session/session_providers.dart`,
  `${mobileSrc}/features/conversations/data/messenger_providers.dart`,
];

for (const file of appStateSuccessors) {
  assertNoMatch(
    file,
    /mock_crypto_engine\.dart/,
    'App wiring must not depend on the mock crypto implementation directly',
  );
  assertNoMatch(
    file,
    /device_auth_signer\.dart/,
    'App wiring must not depend on a concrete auth signer implementation directly',
  );
}

assertMatch(
  `${mobileSrc}/core/di/core_providers.dart`,
  /crypto_adapter_registry\.dart/,
  'Core providers must bootstrap crypto through the adapter registry',
);

const dartFiles = (dir) =>
  readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return dartFiles(path);
    return entry.name.endsWith('.dart') ? [path] : [];
  });

const lineCount = (file) => (read(file).match(/\n/g) ?? []).length;

for (const file of [messengerFacade, ...dartFiles(messengerServicesDir)]) {
  assertNoMatch(
    file,
    /MockCryptoEngine|createDefaultCryptoAdapter|devEnvelopeVersion|devAttachmentWrapAlgorithmHint/,
    'Messaging controller and services must not depend on mock protocol internals',
  );
}

assertNoMatch(
  'apps/mobile/lib/src/core/storage/conversation_cache_service.dart',
  /devEnvelopeVersion|devAttachmentWrapAlgorithmHint/,
  'Conversation cache must not depend on mock protocol internals',
);

assertMatch(
  'apps/mobile/lib/src/core/crypto/crypto_engine.dart',
  /abstract class DeviceIdentityProvider/,
  'Crypto boundary must expose a device identity provider interface',
);

assertMatch(
  'apps/mobile/lib/src/core/crypto/crypto_engine.dart',
  /abstract class DeviceAuthChallengeSigner/,
  'Crypto boundary must expose a device auth signer interface',
);

assertMatch(
  'apps/mobile/lib/src/core/crypto/crypto_engine.dart',
  /abstract class CryptoEnvelopeCodec/,
  'Crypto boundary must expose an envelope codec interface',
);

assertMatch(
  'apps/mobile/lib/src/core/crypto/crypto_engine.dart',
  /abstract class ConversationSessionBootstrapper/,
  'Crypto boundary must expose a session bootstrap interface',
);

assertMatch(
  'apps/mobile/lib/src/core/crypto/crypto_engine.dart',
  /final int sessionSchemaVersion;/,
  'Session bootstrap material must expose a schema version for future adapter migrations',
);

assertMatch(
  'apps/mobile/lib/src/core/crypto/crypto_engine.dart',
  /final String localDeviceId;/,
  'Session bootstrap material must bind persisted state to the local device',
);

assertMatch(
  'apps/mobile/lib/src/core/crypto/crypto_engine.dart',
  /final String remoteDeviceId;/,
  'Session bootstrap material must bind persisted state to the remote device',
);

assertMatch(
  'apps/mobile/lib/src/core/crypto/crypto_engine.dart',
  /final String remoteIdentityFingerprint;/,
  'Session bootstrap material must expose a remote identity fingerprint for migration checks',
);

assertMatch(
  'apps/mobile/lib/src/core/crypto/crypto_engine.dart',
  /abstract class CryptoAdapter/,
  'Crypto boundary must expose an adapter facade',
);

assertMatch(
  'apps/mobile/lib/src/core/crypto/crypto_engine.dart',
  /ConversationSessionBootstrapper get sessions/,
  'Crypto adapter facade must expose session bootstrap services',
);

assertNoMatch(
  'packages/shared/src/index.ts',
  /mock-engine/,
  'Shared package root must not export the mock crypto adapter by default',
);

// ---------------------------------------------------------------------------
// Mobile layering: core is the bottom layer, the messenger stays decomposed.
// ---------------------------------------------------------------------------

const packagePrefix = 'package:veil_mobile/';

// Every import and export of [file] inside the app, as repo paths.
const directivesOf = (file) =>
  [...read(file).matchAll(/^\s*(import|export)\s+'([^']+)'/gm)].flatMap(([, kind, uri]) => {
    if (uri.startsWith(packagePrefix))
      return [{ kind, target: join('apps/mobile/lib', uri.slice(packagePrefix.length)) }];
    if (uri.includes(':')) return [];
    return [{ kind, target: normalize(join(dirname(file), uri)) }];
  });

const layerOf = (path) => relative(mobileSrc, path).split(sep)[0];

// The old core/router paths stay importable for existing callers. They may
// only re-export app/router, and nothing else in core may reach up.
const compatibilityShims = new Set([
  `${mobileSrc}/core/router/app_router.dart`,
  `${mobileSrc}/core/router/route_guard.dart`,
]);

for (const file of dartFiles(`${mobileSrc}/core`)) {
  for (const { kind, target } of directivesOf(file)) {
    const layer = layerOf(target);
    if (layer !== 'features' && layer !== 'app') continue;
    if (kind === 'export' && compatibilityShims.has(file)) continue;
    failures.push(
      `lib/src/core must not ${kind} ${layer}/ (${relative(mobileSrc, target)}): ${file}`,
    );
  }
}

for (const shim of compatibilityShims) {
  const code = read(shim)
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith('//'));
  if (!code.every((line) => /^export '[^']+';$/.test(line))) {
    failures.push(`Compatibility path must hold re-exports only: ${shim}`);
  }
}

if (lineCount(messengerFacade) > 400) {
  failures.push(
    `Messenger facade must stay at or under 400 lines (has ${lineCount(messengerFacade)}): ${messengerFacade}`,
  );
}

for (const file of dartFiles(messengerServicesDir)) {
  if (lineCount(file) > 450) {
    failures.push(
      `Messenger service files must stay at or under 450 lines (has ${lineCount(file)}): ${file}`,
    );
  }
}

// No backup exists, and there is to be no place for one.
if (existsSync(`${mobileSrc}/core/backup`)) {
  failures.push(`Mobile must not ship a backup module: ${mobileSrc}/core/backup`);
}

// The facade must lie on no import cycle, above all not with app_state.dart
// or the provider files that replaced it, which import the facade.
const importGraph = new Map(
  dartFiles('apps/mobile/lib').map((file) => [
    file,
    directivesOf(file).map(({ target }) => target),
  ]),
);
const reachableFrom = (start) => {
  const seen = new Set();
  const pending = [...(importGraph.get(start) ?? [])];
  while (pending.length > 0) {
    const next = pending.pop();
    if (seen.has(next)) continue;
    seen.add(next);
    pending.push(...(importGraph.get(next) ?? []));
  }
  return seen;
};
const facadeReaches = reachableFrom(messengerFacade);
if (facadeReaches.has(messengerFacade)) {
  const onCycle = [...facadeReaches].filter((file) => reachableFrom(file).has(messengerFacade));
  failures.push(`Messenger facade is on an import cycle through ${onCycle.join(', ')}`);
}
for (const successor of appStateSuccessors) {
  if (facadeReaches.has(successor)) {
    failures.push(
      `Messenger facade must not depend on app wiring (${successor}): ${messengerFacade}`,
    );
  }
}

if (failures.length > 0) {
  for (const failure of failures) {
    console.error(failure);
  }
  process.exit(1);
}

console.log('Crypto architecture checks passed.');
