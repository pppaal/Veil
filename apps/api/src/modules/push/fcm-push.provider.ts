import { createPrivateKey, createSign } from 'node:crypto';

import { badRequest } from '../../common/errors/api-error';
import { AppConfigService } from '../../common/config/app-config.service';

import type { MessagePushHint, PushProvider } from './push.types';

type FcmRequestShape = {
  endpoint: string;
  headers: Record<string, string>;
  body: {
    message: {
      token: string;
      data: Record<string, string>;
      android: {
        priority: 'high';
      };
      apns: {
        payload: {
          aps: {
            'content-available': 1;
          };
        };
      };
    };
  };
};

export class FcmMetadataPushProvider implements PushProvider {
  readonly kind = 'fcm' as const;
  private cachedAccessToken:
    | {
        value: string;
        expiresAt: number;
      }
    | undefined;

  constructor(private readonly config: AppConfigService) {
    if (!config.fcmProjectId || !config.fcmServiceAccountJson) {
      throw badRequest(
        'internal_error',
        'FCM provider selected but required FCM credentials are missing',
      );
    }
  }

  buildRequest(pushToken: string, hint: MessagePushHint): FcmRequestShape {
    return {
      endpoint: `https://fcm.googleapis.com/v1/projects/${this.config.fcmProjectId!}/messages:send`,
      headers: {
        'Content-Type': 'application/json',
      },
      body: {
        message: {
          token: pushToken,
          data: {
            kind: hint.kind,
          },
          android: {
            priority: 'high',
          },
          apns: {
            payload: {
              aps: {
                'content-available': 1,
              },
            },
          },
        },
      },
    };
  }

  async sendMessageHint(pushToken: string, hint: MessagePushHint): Promise<void> {
    const request = this.buildRequest(pushToken, hint);
    if (!this.config.pushDeliveryEnabled) {
      return;
    }

    const accessToken = await this.issueAccessToken();
    const response = await fetch(request.endpoint, {
      method: 'POST',
      headers: {
        ...request.headers,
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify(request.body),
    });
    if (!response.ok) {
      throw new Error(
        `FCM delivery failed with status ${response.status}: ${await response.text()}`,
      );
    }
  }

  private async issueAccessToken(): Promise<string> {
    const now = Math.floor(Date.now() / 1000);
    if (
      this.cachedAccessToken != null &&
      this.cachedAccessToken.expiresAt > now + 60
    ) {
      return this.cachedAccessToken.value;
    }

    const serviceAccount = JSON.parse(this.config.fcmServiceAccountJson!) as {
      client_email: string;
      private_key: string;
      token_uri?: string;
    };
    const tokenUri = serviceAccount.token_uri ?? 'https://oauth2.googleapis.com/token';
    const assertion = issueServiceAccountJwt({
      clientEmail: serviceAccount.client_email,
      privateKeyPem: serviceAccount.private_key,
      tokenUri,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      now,
    });
    const response = await fetch(tokenUri, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion,
      }),
    });
    if (!response.ok) {
      throw new Error(
        `FCM token request failed with status ${response.status}: ${await response.text()}`,
      );
    }
    const payload = (await response.json()) as {
      access_token: string;
      expires_in: number;
    };
    this.cachedAccessToken = {
      value: payload.access_token,
      expiresAt: now + Math.max(60, payload.expires_in - 60),
    };
    return payload.access_token;
  }
}

function issueServiceAccountJwt({
  clientEmail,
  privateKeyPem,
  tokenUri,
  scope,
  now,
}: {
  clientEmail: string;
  privateKeyPem: string;
  tokenUri: string;
  scope: string;
  now: number;
}): string {
  const header = base64UrlEncode({
    alg: 'RS256',
    typ: 'JWT',
  });
  const claims = base64UrlEncode({
    iss: clientEmail,
    sub: clientEmail,
    aud: tokenUri,
    scope,
    iat: now,
    exp: now + 3600,
  });
  const signingInput = `${header}.${claims}`;
  const signer = createSign('RSA-SHA256');
  signer.update(signingInput);
  signer.end();
  const signature = signer.sign(createPrivateKey(privateKeyPem));
  return `${signingInput}.${base64UrlBuffer(signature)}`;
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
