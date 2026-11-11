import { request as httpRequest } from 'node:http';
import { request as httpsRequest } from 'node:https';
import type { LookupFunction } from 'node:net';

import { AppConfigService } from '../../common/config/app-config.service';
import { guardedLookup, validatePushEndpointUrl } from './push-endpoint.validator';
import type { MessagePushHint, PushProvider } from './push.types';

type UnifiedPushRequestShape = {
  endpoint: string;
  headers: Record<string, string>;
  body: string;
};

export interface PushHttpRequest {
  headers: Record<string, string>;
  body: string;
  lookup?: LookupFunction;
  timeoutMs: number;
}

// Resolves with the response status code. Injected so tests can observe
// requests without a network.
export type PushHttpTransport = (url: URL, request: PushHttpRequest) => Promise<number>;

const DELIVERY_TIMEOUT_MS = 10_000;

// node:http(s).request never follows redirects, so a 3xx pointing at an
// internal host is just a failed delivery. No agent: every connection goes
// through the vetted lookup instead of reusing a pooled socket.
export const nodeHttpTransport: PushHttpTransport = (url, request) =>
  new Promise((resolve, reject) => {
    const send = url.protocol === 'http:' ? httpRequest : httpsRequest;
    const outgoing = send(
      url,
      {
        method: 'POST',
        agent: false,
        lookup: request.lookup,
        headers: { ...request.headers, 'Content-Length': Buffer.byteLength(request.body) },
      },
      (response) => {
        clearTimeout(deadline);
        response.resume();
        resolve(response.statusCode ?? 0);
      },
    );
    // An absolute deadline rather than a socket idle timeout, so a
    // distributor dribbling bytes cannot hold the request open indefinitely.
    const deadline = setTimeout(() => {
      outgoing.destroy(
        Object.assign(new Error('UnifiedPush request timed out'), { code: 'ETIMEDOUT' }),
      );
    }, request.timeoutMs);
    outgoing.on('error', (error) => {
      clearTimeout(deadline);
      reject(error);
    });
    outgoing.end(request.body);
  });

const statusClass = (status: number): string => `${Math.floor(status / 100)}xx`;

// UnifiedPush (https://unifiedpush.org) lets the app receive wakes through a
// user-chosen distributor (ntfy, NextPush, a self-hosted server …) with NO
// Google/Apple dependency — the enabler for an F-Droid build of VEIL.
//
// The device registers with its distributor, gets an endpoint URL, and hands
// that URL to the server as its push token. To wake the app the server POSTs
// an opaque body to it. Because the URL is client-chosen, every delivery is
// re-validated (validatePushEndpointUrl) and connects only to addresses the
// guarded lookup vetted. Failures are reported by error code or status class
// alone, so the endpoint never reaches the logs.
export class UnifiedPushProvider implements PushProvider {
  readonly kind = 'unifiedpush' as const;

  constructor(
    private readonly config: AppConfigService,
    private readonly transport: PushHttpTransport = nodeHttpTransport,
    private readonly lookup: LookupFunction = guardedLookup(),
  ) {}

  buildRequest(pushToken: string, hint: MessagePushHint): UnifiedPushRequestShape {
    const endpoint = validatePushEndpointUrl(pushToken, {
      allowedHosts: this.config.unifiedPushAllowedHosts,
      production: this.config.isProduction,
    });
    return {
      endpoint: endpoint.toString(),
      headers: {
        'Content-Type': 'application/json',
        // UnifiedPush v3 headers. Bound how long a distributor may hold an
        // undelivered wake, and mark it time-sensitive.
        TTL: '86400',
        Urgency: 'high',
      },
      // Opaque, constant, metadata-free — identical wake-only contract to the
      // APNs/FCM providers. No conversationId/messageId ever leaves the server.
      body: JSON.stringify({ kind: hint.kind }),
    };
  }

  async sendMessageHint(pushToken: string, hint: MessagePushHint): Promise<void> {
    const request = this.buildRequest(pushToken, hint);
    if (!this.config.pushDeliveryEnabled) {
      return;
    }

    const url = new URL(request.endpoint);
    let status: number;
    try {
      status = await this.transport(url, {
        headers: request.headers,
        body: request.body,
        // The validator admits a localhost endpoint only outside production;
        // there it must resolve to loopback, which the guard would refuse.
        lookup: url.protocol === 'http:' ? undefined : this.lookup,
        timeoutMs: DELIVERY_TIMEOUT_MS,
      });
    } catch (error) {
      const code = (error as NodeJS.ErrnoException | undefined)?.code ?? 'transport_error';
      throw new Error(`UnifiedPush delivery failed: ${code}`);
    }

    if (status < 200 || status >= 300) {
      throw new Error(`UnifiedPush delivery failed with status class ${statusClass(status)}`);
    }
  }
}
