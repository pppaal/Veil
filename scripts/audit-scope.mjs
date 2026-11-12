// What the external crypto audit covers: the documents an auditor gets and
// the code paths they are asked to review. scripts/audit-handoff-bundle.mjs
// (the handoff README and tarball) and scripts/external-review-manifest.mjs
// (the review manifest) both read these lists, so the two cannot drift apart.
//
// The audit is the only thing that may set VEIL_AUDITED_CRYPTO_ATTESTED and
// so unlock a production boot. Code left out of this scope is code the
// attestation does not cover, so a path that no longer exists is a hard
// error, never a warning, and scripts/__tests__/audit-scope.test.mjs fails
// when SECURITY.md declares something in scope that these paths miss.
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

export const SECURITY_POLICY = 'SECURITY.md';

export const AUDIT_DOCS = [
  // Product framing and threat model.
  'docs/no-recovery.md',
  'docs/trusted-device-graph.md',
  'docs/architecture.md',
  'docs/threat-model.md',
  'docs/external-security-review-packet.md',
  // Protocol v2 is normative here, on mobile and web, pinned by
  // packages/shared/test-vectors/crypto-kat.json.
  'docs/crypto-envelope-spec.md',
  'docs/security/crypto-surfaces.md',
  'docs/group-sender-keys-design.md',
  'docs/forward-secrecy-ratchet-design.md',
  'docs/crypto-adapter-architecture.md',
  'docs/web-architecture.md',
  // Superseded and never implemented; history only.
  'docs/envelope-v3-unified-spec.md',
  // Under revision; not implemented.
  'docs/sealed-sender-design.md',
  // Flows and local posture.
  'docs/device-transfer-flow.md',
  'docs/message-flow.md',
  'docs/attachment-flow.md',
  'docs/metadata-retention.md',
  'docs/observability-hygiene.md',
  'docs/mobile-device-security.md',
  // Release posture.
  'docs/mock-crypto-replacement.md',
  'docs/private-beta-audit.md',
  'docs/private-beta-readiness-report.md',
  'docs/production-deployment.md',
  'docs/external-audit-firm-shortlist.md',
];

export const AUDIT_CODE_PATHS = [
  // Relay: authentication, step-up proofs, transfer, message acceptance, the
  // key directory (signed and one-time prekeys, GET /keys/group) and the
  // Sender Keys distribution relay.
  'apps/api/src/modules/auth',
  'apps/api/src/modules/device-transfer',
  'apps/api/src/modules/messages',
  'apps/api/src/modules/prekeys',
  'apps/api/src/modules/groups',
  'apps/api/src/common/guards',
  'apps/api/src/common/errors',
  'apps/api/src/common/interceptors',
  'apps/api/prisma/schema.prisma',
  'apps/api/prisma/migrations',
  // Mobile: protocol v2 (x3dh/, ratchet/, payload/, attachment/), Sender
  // Keys, and the trust layer that decides which identities a conversation
  // may use (identity_trust, peer_session_resolver, conversation_crypto_router,
  // prekey_maintenance).
  'apps/mobile/lib/src/core/crypto',
  'apps/mobile/lib/src/core/security/local_data_cipher.dart',
  'apps/mobile/lib/src/features/conversations/data/messenger',
  'apps/mobile/lib/src/features/conversations/data/group_sender_key_coordinator.dart',
  // Web: the second protocol-v2 implementation, its storage and trust layer.
  'apps/web-demo/src/crypto',
  'apps/web-demo/src/platform',
  'apps/web-demo/src/features',
  'apps/web-demo/src/app/messaging-stack.js',
  'apps/web-demo/src/domain/peer-bindings.js',
  // Shared contracts and the known-answer vectors both clients must match.
  'packages/contracts/src',
  'packages/shared/src',
  'packages/shared/test-vectors',
  'scripts/crypto-test-vectors.mjs',
  'apps/mobile/test/interop/web_mobile_interop_test.dart',
  'scripts/policy-check.mjs',
];

// The protocol question every review artefact asks (the manifest and
// docs/external-security-review-packet.md).
export const PROTOCOL_REVIEW_QUESTION =
  'Is protocol v2 correct as docs/crypto-envelope-spec.md specifies it, and the same on both clients: ' +
  "mutual X3DH authentication (DH1 over the initiator's X25519 identity key, IKx and signed prekeys " +
  'certified by the Ed25519 identity key, one-time prekeys consumed once), the Double Ratchet (PN, ' +
  'skipped-key bounds, replay rejection), TOFU identity-trust gating before any session is installed, ' +
  'opened or sealed, and Sender Keys distribution and epochs on mobile? Do the mobile (Dart) and web ' +
  '(WebCrypto) implementations produce byte-identical results for packages/shared/test-vectors/crypto-kat.json?';

/** Audit-scope paths (documents and code) that do not exist under rootDir. */
export function missingAuditPaths(rootDir) {
  return [...AUDIT_DOCS, ...AUDIT_CODE_PATHS].filter((path) => !existsSync(join(rootDir, path)));
}

/** Throws when any audit-scope path is missing: a renamed file must not leave the scope silently. */
export function assertAuditScope(rootDir) {
  const missing = missingAuditPaths(rootDir);
  if (missing.length > 0) {
    throw new Error(
      `Audit scope names paths that do not exist (update scripts/audit-scope.mjs): ${missing.join(', ')}`,
    );
  }
}

/** The backticked repository paths in the "In scope:" list of SECURITY.md. */
export function securityInScopePaths(markdown) {
  const start = markdown.indexOf('In scope:');
  const end = markdown.indexOf('Out of scope', start);
  if (start === -1 || end === -1) {
    throw new Error(`${SECURITY_POLICY} has no "In scope:" list followed by "Out of scope"`);
  }
  return [...markdown.slice(start, end).matchAll(/`([^`]+)`/g)]
    .map((match) => match[1].replace(/\/+$/, ''))
    .filter((path) => /^(?:apps|packages|scripts)\//.test(path));
}

/** In-scope paths of SECURITY.md that no audit code path covers. */
export function uncoveredSecurityPaths(rootDir, codePaths = AUDIT_CODE_PATHS) {
  const markdown = readFileSync(join(rootDir, SECURITY_POLICY), 'utf8');
  return securityInScopePaths(markdown).filter(
    (path) => !codePaths.some((code) => path === code || path.startsWith(`${code}/`)),
  );
}
