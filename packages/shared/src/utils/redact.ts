const REDACTION = '[REDACTED]';
const SENSITIVE_KEYS = new Set([
  'accessToken',
  'authorization',
  'authProof',
  'authPrivateKey',
  'authPrivateKeyRef',
  'authPublicKey',
  'body',
  'challenge',
  'challengeId',
  'ciphertext',
  'downloadUrl',
  'encryptedKey',
  'identityPrivateKeyRef',
  'identityPublicKey',
  'nonce',
  'proof',
  'pushToken',
  'refreshToken',
  'secret',
  'sessionToken',
  'sessionLocator',
  'sha256',
  'signature',
  'signedPrekeyBundle',
  'storageKey',
  'token',
  'transferToken',
  'uploadUrl',
]);

const SENSITIVE_SUFFIXES = ['Token', 'Secret', 'Signature', 'Proof', 'PrivateKey', 'PrivateKeyRef'];

export interface RedactionTarget {
  accessToken?: string | null;
  authorization?: string | null;
  authProof?: string | null;
  authPrivateKey?: string | null;
  authPrivateKeyRef?: string | null;
  authPublicKey?: string | null;
  challenge?: string | null;
  challengeId?: string | null;
  ciphertext?: string | null;
  downloadUrl?: string | null;
  encryptedKey?: string | null;
  identityPrivateKeyRef?: string | null;
  identityPublicKey?: string | null;
  nonce?: string | null;
  body?: string | null;
  pushToken?: string | null;
  refreshToken?: string | null;
  secret?: string | null;
  sessionLocator?: string | null;
  sha256?: string | null;
  signature?: string | null;
  signedPrekeyBundle?: string | null;
  storageKey?: string | null;
  token?: string | null;
  transferToken?: string | null;
  uploadUrl?: string | null;
}

const shouldRedactKey = (key: string): boolean => {
  if (SENSITIVE_KEYS.has(key)) {
    return true;
  }

  return SENSITIVE_SUFFIXES.some((suffix) => key.endsWith(suffix));
};

const redactValue = (value: unknown, seen: WeakSet<object>): unknown => {
  if (Array.isArray(value)) {
    return value.map((item) => redactValue(item, seen));
  }

  if (value && typeof value === 'object') {
    if (seen.has(value)) {
      return '[Circular]';
    }
    seen.add(value);

    return Object.fromEntries(
      Object.entries(value).map(([key, nested]) => [
        key,
        shouldRedactKey(key) && nested != null ? REDACTION : redactValue(nested, seen),
      ]),
    );
  }

  return value;
};

export const redactSensitiveFields = <T extends RedactionTarget>(value: T): T =>
  redactValue(value, new WeakSet<object>()) as T;
