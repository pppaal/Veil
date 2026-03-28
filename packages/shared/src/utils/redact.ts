const REDACTION = '[REDACTED]';

export interface RedactionTarget {
  ciphertext?: string | null;
  nonce?: string | null;
  body?: string | null;
  pushToken?: string | null;
  token?: string | null;
}

export const redactSensitiveFields = <T extends RedactionTarget>(value: T): T => ({
  ...value,
  ciphertext: value.ciphertext ? REDACTION : value.ciphertext,
  nonce: value.nonce ? REDACTION : value.nonce,
  body: value.body ? REDACTION : value.body,
  pushToken: value.pushToken ? REDACTION : value.pushToken,
  token: value.token ? REDACTION : value.token,
});
