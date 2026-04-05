import { createPrivateKey, createSign } from 'node:crypto';
import { connect } from 'node:http2';

import { badRequest } from '../../common/errors/api-error';
import { AppConfigService } from '../../common/config/app-config.service';

import type { MessagePushHint, PushProvider } from './push.types';

type ApnsRequestShape = {
  endpoint: string;
  headers: Record<string, string>;
  body: {
    aps: {
      'content-available': 1;
    };
    veil: MessagePushHint;
  };
};

export class ApnsMetadataPushProvider implements PushProvider {
  readonly kind = 'apns' as const;
  private cachedBearerToken:
    | {
        value: string;
        expiresAt: number;
      }
    | undefined;

  constructor(private readonly config: AppConfigService) {
    if (!config.apnsBundleId || !config.apnsTeamId || !config.apnsKeyId || !config.apnsPrivateKeyPem) {
      throw badRequest(
        'internal_error',
        'APNs provider selected but required APNs credentials are missing',
      );
    }
  }

  buildRequest(pushToken: string, hint: MessagePushHint): ApnsRequestShape {
    return {
      endpoint: `https://${this.config.apnsUseSandbox ? 'api.sandbox.push.apple.com' : 'api.push.apple.com'}/3/device/${pushToken}`,
      headers: {
        'apns-push-type': 'background',
        'apns-priority': '5',
        'apns-topic': this.config.apnsBundleId!,
      },
      body: {
        aps: {
          'content-available': 1,
        },
        veil: hint,
      },
    };
  }

  async sendMessageHint(pushToken: string, hint: MessagePushHint): Promise<void> {
    const request = this.buildRequest(pushToken, hint);
    if (!this.config.pushDeliveryEnabled) {
      return;
    }

    const endpoint = new URL(request.endpoint);
    const client = connect(endpoint.origin);

    await new Promise<void>((resolve, reject) => {
      client.on('error', reject);
      const stream = client.request({
        ':method': 'POST',
        ':path': endpoint.pathname,
        authorization: `bearer ${this.issueBearerToken()}`,
        'content-type': 'application/json',
        ...request.headers,
      });

      let statusCode = 0;
      let responseBody = '';
      stream.setEncoding('utf8');
      stream.on('response', (headers) => {
        statusCode = Number(headers[':status'] ?? 0);
      });
      stream.on('data', (chunk) => {
        responseBody += chunk;
      });
      stream.on('end', () => {
        client.close();
        if (statusCode >= 200 && statusCode < 300) {
          resolve();
          return;
        }
        reject(
          new Error(
            `APNs delivery failed with status ${statusCode}: ${responseBody || 'empty body'}`,
          ),
        );
      });
      stream.on('error', (error) => {
        client.close();
        reject(error);
      });
      stream.end(JSON.stringify(request.body));
    });
  }

  private issueBearerToken(): string {
    const now = Math.floor(Date.now() / 1000);
    if (
      this.cachedBearerToken != null &&
      this.cachedBearerToken.expiresAt > now + 60
    ) {
      return this.cachedBearerToken.value;
    }

    const header = base64UrlEncode({
      alg: 'ES256',
      kid: this.config.apnsKeyId,
    });
    const claims = base64UrlEncode({
      iss: this.config.apnsTeamId,
      iat: now,
    });
    const signingInput = `${header}.${claims}`;
    const signer = createSign('SHA256');
    signer.update(signingInput);
    signer.end();
    const signature = signer.sign(createPrivateKey(this.config.apnsPrivateKeyPem!));
    const token = `${signingInput}.${base64UrlBuffer(signature)}`;
    this.cachedBearerToken = {
      value: token,
      expiresAt: now + 50 * 60,
    };
    return token;
  }
}

function base64UrlEncode(value: Record<string, unknown>): string {
  return base64UrlBuffer(Buffer.from(JSON.stringify(value)));
}

function base64UrlBuffer(value: Uint8Array): string {
  return Buffer.from(value)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}
