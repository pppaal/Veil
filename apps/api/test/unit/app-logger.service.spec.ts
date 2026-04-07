import { AppLoggerService } from '../../src/common/logger/app-logger.service';

describe('AppLoggerService', () => {
  it('redacts nested sensitive fields', () => {
    const logger = new AppLoggerService() as any;

    const redacted = logger.redact({
      authorization: 'Bearer secret-token',
      challenge: 'ephemeral-challenge',
      ciphertext: 'opaque-ciphertext',
      nested: {
        transferToken: 'transfer-token',
        authPublicKey: 'public-key-material',
        attachment: {
          storageKey: 'attachments/device/key',
          encryptedKey: 'wrapped-key',
          sha256: 'hash-value',
        },
      },
      events: [
        {
          uploadUrl: 'https://signed-upload.invalid/object',
          pushToken: 'push-token',
        },
      ],
    });

    expect(redacted.authorization).toBe('[REDACTED]');
    expect(redacted.challenge).toBe('[REDACTED]');
    expect(redacted.ciphertext).toBe('[REDACTED]');
    expect((redacted.nested as { transferToken: string }).transferToken).toBe('[REDACTED]');
    expect((redacted.nested as { authPublicKey: string }).authPublicKey).toBe('[REDACTED]');
    expect(
      ((redacted.nested as { attachment: { storageKey: string } }).attachment.storageKey),
    ).toBe('[REDACTED]');
    expect(
      ((redacted.events as Array<{ uploadUrl: string }>)[0]!.uploadUrl),
    ).toBe('[REDACTED]');
  });
});
