import { readFileSync } from 'node:fs';

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

assertNoMatch(
  'apps/mobile/lib/src/app/app_state.dart',
  /mock_crypto_engine\.dart/,
  'App state must not depend on the mock crypto implementation directly',
);

assertNoMatch(
  'apps/mobile/lib/src/app/app_state.dart',
  /device_auth_signer\.dart/,
  'App state must not depend on a concrete auth signer implementation directly',
);

assertMatch(
  'apps/mobile/lib/src/app/app_state.dart',
  /crypto_adapter_registry\.dart/,
  'App state must bootstrap crypto through the adapter registry',
);

assertNoMatch(
  'apps/mobile/lib/src/features/conversations/data/veil_messenger_controller.dart',
  /MockCryptoEngine|createDefaultCryptoAdapter|devEnvelopeVersion|devAttachmentWrapAlgorithmHint/,
  'Messaging controller must not depend on mock protocol internals',
);

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

if (failures.length > 0) {
  for (const failure of failures) {
    console.error(failure);
  }
  process.exit(1);
}

console.log('Crypto architecture checks passed.');
