import { Injectable, Logger } from '@nestjs/common';
import { redactSensitiveFields } from '@veil/shared';

@Injectable()
export class AppLoggerService {
  private readonly logger = new Logger('VEIL');

  info(event: string, meta: Record<string, unknown> = {}): void {
    this.logger.log(JSON.stringify({ level: 'info', event, ...this.redact(meta) }));
  }

  warn(event: string, meta: Record<string, unknown> = {}): void {
    this.logger.warn(JSON.stringify({ level: 'warn', event, ...this.redact(meta) }));
  }

  error(event: string, meta: Record<string, unknown> = {}): void {
    this.logger.error(JSON.stringify({ level: 'error', event, ...this.redact(meta) }));
  }

  private redact(meta: Record<string, unknown>): Record<string, unknown> {
    return redactSensitiveFields(this.normalize(meta) as {
      accessToken?: string | null;
      authProof?: string | null;
      authPrivateKey?: string | null;
      authPrivateKeyRef?: string | null;
      authPublicKey?: string | null;
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
      sha256?: string | null;
      signature?: string | null;
      signedPrekeyBundle?: string | null;
      storageKey?: string | null;
      token?: string | null;
      transferToken?: string | null;
      uploadUrl?: string | null;
    });
  }

  private normalize(value: unknown): unknown {
    if (value instanceof Error) {
      return {
        name: value.name,
        message: value.message,
      };
    }

    if (Array.isArray(value)) {
      return value.map((item) => this.normalize(item));
    }

    if (value && typeof value === 'object') {
      return Object.fromEntries(
        Object.entries(value).map(([key, nested]) => [key, this.normalize(nested)]),
      );
    }

    return value;
  }
}
