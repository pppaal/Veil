import { badRequest } from '../../common/errors/api-error';
import { AppConfigService } from '../../common/config/app-config.service';

import type { MessagePushHint, PushProvider } from './push.types';

type UnifiedPushRequestShape = {
  endpoint: string;
  headers: Record<string, string>;
  body: string;
};

// UnifiedPush (https://unifiedpush.org) lets the app receive wakes through a
// user-chosen distributor (ntfy, NextPush, a self-hosted server …) with NO
// Google/Apple dependency — the enabler for an F-Droid build of VEIL.
//
// The device registers with its distributor, gets an HTTPS *endpoint URL*, and
// hands that URL to the server as its push token. To wake the app the server
// POSTs an opaque body to that URL; the distributor relays it.
//
// Security note — SSRF: the "push token" is therefore a URL the client fully
// controls, and the server makes an outbound request to it. Left unguarded a
// malicious registrant could point it at cloud metadata (169.254.169.254) or
// internal services. Every endpoint is validated before a request is built:
//   * https only,
//   * if VEIL_UNIFIEDPUSH_ALLOWED_HOSTS is set, the host must be on it
//     (the production posture — also defeats DNS rebinding),
//   * otherwise literal private/loopback/link-local IPs are rejected.
export class UnifiedPushProvider implements PushProvider {
  readonly kind = 'unifiedpush' as const;
  private readonly allowedHosts: ReadonlySet<string> | null;

  constructor(private readonly config: AppConfigService) {
    const hosts = config.unifiedPushAllowedHosts;
    this.allowedHosts = hosts.length > 0 ? new Set(hosts.map((h) => h.toLowerCase())) : null;
  }

  buildRequest(pushToken: string, hint: MessagePushHint): UnifiedPushRequestShape {
    const endpoint = this.validateEndpoint(pushToken);
    return {
      endpoint,
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

    const response = await fetch(request.endpoint, {
      method: 'POST',
      headers: request.headers,
      body: request.body,
    });
    if (!response.ok) {
      throw new Error(`UnifiedPush delivery failed with status ${response.status}`);
    }
  }

  private validateEndpoint(pushToken: string): string {
    let url: URL;
    try {
      url = new URL(pushToken);
    } catch {
      throw badRequest('validation_failed', 'UnifiedPush endpoint is not a valid URL');
    }
    if (url.protocol !== 'https:') {
      throw badRequest('validation_failed', 'UnifiedPush endpoint must use https');
    }

    const host = url.hostname.toLowerCase();
    if (this.allowedHosts) {
      if (!this.allowedHosts.has(host)) {
        throw badRequest('validation_failed', 'UnifiedPush endpoint host is not allowlisted');
      }
    } else if (isPrivateHost(host)) {
      throw badRequest('validation_failed', 'UnifiedPush endpoint resolves to a private address');
    }

    return url.toString();
  }
}

// Best-effort SSRF screen for IP-literal and loopback hosts. DNS hostnames are
// NOT resolved here — VEIL_UNIFIEDPUSH_ALLOWED_HOSTS is the real defense in
// production (it also closes DNS rebinding). Kept dependency-free and pure so
// it is exhaustively unit-testable.
export function isPrivateHost(host: string): boolean {
  if (host === 'localhost' || host.endsWith('.localhost')) {
    return true;
  }

  // Strip IPv6 brackets / zone id if a raw new URL().hostname kept them.
  const bare = host.replace(/^\[/, '').replace(/\]$/, '').split('%', 1)[0];

  const ipv4 = bare.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (ipv4) {
    const [a, b] = ipv4.slice(1).map((n) => Number(n));
    if (a === 10) return true; // 10.0.0.0/8
    if (a === 127) return true; // loopback
    if (a === 0) return true; // 0.0.0.0/8
    if (a === 169 && b === 254) return true; // link-local incl. cloud metadata
    if (a === 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12
    if (a === 192 && b === 168) return true; // 192.168.0.0/16
    if (a === 100 && b >= 64 && b <= 127) return true; // CGNAT 100.64.0.0/10
    return false;
  }

  if (bare.includes(':')) {
    const v6 = bare.toLowerCase();
    if (v6 === '::1' || v6 === '::') return true; // loopback / unspecified
    if (v6.startsWith('fe80')) return true; // link-local
    if (v6.startsWith('fc') || v6.startsWith('fd')) return true; // unique-local fc00::/7
    if (v6.startsWith('::ffff:')) return true; // IPv4-mapped — screen conservatively
    return false;
  }

  return false;
}
