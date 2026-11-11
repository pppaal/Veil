import { lookup as dnsLookup, type LookupAddress } from 'node:dns';
import { BlockList, isIP, type LookupFunction } from 'node:net';

import { badRequest } from '../../common/errors/api-error';
import type { PushProviderKind } from './push.types';

export interface PushEndpointPolicy {
  allowedHosts: readonly string[];
  production: boolean;
}

export interface PushTokenPolicySource {
  pushProvider: PushProviderKind;
  unifiedPushAllowedHosts: string[];
  isProduction: boolean;
}

// Addresses a push endpoint may never reach: private, loopback, link-local,
// unique-local, CGNAT, multicast, unspecified and reserved space. BlockList
// also matches IPv4-mapped IPv6 forms (::ffff:127.0.0.1) against the IPv4
// rules, which is how mapped literals and resolver answers are caught.
const FORBIDDEN_ADDRESSES = new BlockList();
for (const [network, prefix] of [
  ['0.0.0.0', 8],
  ['10.0.0.0', 8],
  ['100.64.0.0', 10],
  ['127.0.0.0', 8],
  ['169.254.0.0', 16],
  ['172.16.0.0', 12],
  ['192.168.0.0', 16],
  ['224.0.0.0', 4],
  ['240.0.0.0', 4],
] as const) {
  FORBIDDEN_ADDRESSES.addSubnet(network, prefix, 'ipv4');
}
for (const [network, prefix] of [
  ['::', 128],
  ['::1', 128],
  ['fe80::', 10],
  ['fec0::', 10],
  ['fc00::', 7],
  ['ff00::', 8],
] as const) {
  FORBIDDEN_ADDRESSES.addSubnet(network, prefix, 'ipv6');
}

export function isForbiddenAddress(address: string): boolean {
  const family = isIP(address);
  if (family === 0) {
    return false;
  }
  return FORBIDDEN_ADDRESSES.check(address, family === 6 ? 'ipv6' : 'ipv4');
}

const isLocalhostName = (host: string): boolean =>
  host === 'localhost' || host.endsWith('.localhost');

const reject = (reason: string): never => {
  throw badRequest('validation_failed', `UnifiedPush endpoint ${reason}`);
};

// A UnifiedPush "token" is a URL the client fully controls and the server
// POSTs to, i.e. a server-side request primitive. This is the static half of
// the SSRF defence; the provider's resolving lookup (guardedLookup) is the
// dynamic half that catches hostnames which resolve into forbidden space.
export function validatePushEndpointUrl(endpoint: string, policy: PushEndpointPolicy): URL {
  let url: URL;
  try {
    url = new URL(endpoint);
  } catch {
    return reject('is not a valid URL');
  }

  if (url.username || url.password) {
    reject('must not carry credentials');
  }

  const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, '');
  const developmentLocalhost = !policy.production && isLocalhostName(host);
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && developmentLocalhost)) {
    reject('must use https');
  }
  if (isLocalhostName(host) && policy.production) {
    reject('must not target localhost');
  }
  if (isForbiddenAddress(host)) {
    reject('must not target a private address');
  }

  const allowedHosts = policy.allowedHosts.map((allowed) => allowed.toLowerCase());
  if (
    allowedHosts.length > 0 &&
    !allowedHosts.some((allowed) => host === allowed || host.endsWith(`.${allowed}`))
  ) {
    reject('host is not allowlisted');
  }

  return url;
}

// Endpoints are recognised by shape when another provider is configured, so
// an operator who later switches to UnifiedPush never inherits unvetted URLs.
const URL_SHAPED_TOKEN = /^[a-z][a-z0-9+.-]*:\/\//i;

export function validatePushTokenOnRegistration(
  pushToken: string,
  source: PushTokenPolicySource,
): void {
  if (source.pushProvider !== 'unifiedpush' && !URL_SHAPED_TOKEN.test(pushToken)) {
    return;
  }
  validatePushEndpointUrl(pushToken, {
    allowedHosts: source.unifiedPushAllowedHosts,
    production: source.isProduction,
  });
}

export type AddressResolver = (hostname: string) => Promise<LookupAddress[]>;

const systemResolver: AddressResolver = (hostname) =>
  new Promise((resolve, reject) => {
    dnsLookup(hostname, { all: true }, (error, addresses) =>
      error ? reject(error) : resolve(addresses),
    );
  });

// net/tls `lookup` hook that resolves every address and refuses the
// connection if ANY of them is forbidden, so DNS rebinding cannot pick the
// one private answer out of a mixed set. The socket then connects to an
// address this function vetted, never to a fresh resolution.
export function guardedLookup(resolver: AddressResolver = systemResolver): LookupFunction {
  return (hostname, options, callback) => {
    resolver(hostname)
      .then((addresses) => {
        if (addresses.length === 0) {
          throw Object.assign(new Error('UnifiedPush endpoint did not resolve'), {
            code: 'ENOTFOUND',
          });
        }
        if (addresses.some((entry) => isForbiddenAddress(entry.address))) {
          throw Object.assign(new Error('UnifiedPush endpoint resolves to a private address'), {
            code: 'EPUSHPRIVATE',
          });
        }
        if (options.all) {
          callback(null, addresses);
        } else {
          callback(null, addresses[0].address, addresses[0].family);
        }
      })
      .catch((error: NodeJS.ErrnoException) => callback(error, '', 0));
  };
}
