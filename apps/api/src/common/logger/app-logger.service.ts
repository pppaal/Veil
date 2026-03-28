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
    return redactSensitiveFields(meta as {
      ciphertext?: string | null;
      nonce?: string | null;
      body?: string | null;
      pushToken?: string | null;
      token?: string | null;
    });
  }
}
