import { isIP } from 'node:net';

import type { ClientIpSource } from './config/env.schema';

export interface ClientAddressRequest {
  headers?: Record<string, string | string[] | undefined>;
  ip?: string;
  socket?: { remoteAddress?: string };
}

/**
 * The client's address, read only from the single source the operator
 * configured in VEIL_CLIENT_IP_SOURCE. A forwarding header the configured edge
 * does not overwrite is attacker-controlled, so no other header is consulted.
 */
export const clientAddress = (
  req: ClientAddressRequest,
  source: ClientIpSource,
): string | undefined => {
  switch (source) {
    case 'cf-connecting-ip': {
      // Duplicate headers arrive comma-joined and fail isIP, so a client
      // cannot smuggle a second value past a proxy that appends.
      const header = req.headers?.['cf-connecting-ip'];
      const candidate = typeof header === 'string' ? header.trim() : '';
      return isIP(candidate) ? candidate : req.socket?.remoteAddress;
    }
    case 'x-forwarded-for':
      // Express resolves req.ip from X-Forwarded-For using exactly
      // VEIL_TRUSTED_PROXY_HOPS trusted hops (main.ts sets `trust proxy`).
      return req.ip;
    case 'socket':
    default:
      return req.socket?.remoteAddress;
  }
};

const IPV4_MAPPED = /^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/i;

/**
 * The network a client address stands for, for quotas a client must not dodge
 * by moving between addresses it holds. An IPv4 address is its own network
 * (an IPv4-mapped IPv6 form counts as that IPv4 address). An IPv6 address is
 * reduced to its /64: a single subscriber or host is routinely handed a whole
 * /64, so counting its addresses one by one would give it 2^64 quotas.
 * Anything else, including no address at all, shares one 'unknown' network.
 */
export const clientNetwork = (address: string | undefined): string => {
  const plain = address?.trim().replace(/%.*$/, '') ?? '';
  const mapped = IPV4_MAPPED.exec(plain);
  if (mapped && isIP(mapped[1]) === 4) {
    return mapped[1];
  }
  switch (isIP(plain)) {
    case 4:
      return plain;
    case 6:
      return `${ipv6Groups(plain).slice(0, 4).join(':')}::/64`;
    default:
      return 'unknown';
  }
};

// The eight 16-bit groups of a valid IPv6 address, in lowercase hex without
// leading zeros, with "::" expanded. An embedded dotted IPv4 tail fills the
// last two groups.
const ipv6Groups = (address: string): string[] => {
  const toGroups = (part: string): string[] => {
    if (part === '') {
      return [];
    }
    return part.split(':').flatMap((group) => {
      if (!group.includes('.')) {
        return [group];
      }
      const [a, b, c, d] = group.split('.').map(Number);
      return [((a << 8) | b).toString(16), ((c << 8) | d).toString(16)];
    });
  };
  const [head, tail] = address.includes('::') ? address.split('::') : [address, undefined];
  const headGroups = toGroups(head);
  const tailGroups = tail === undefined ? [] : toGroups(tail);
  const zeros = Array<string>(8 - headGroups.length - tailGroups.length).fill('0');
  return [...headGroups, ...zeros, ...tailGroups].map((group) =>
    Number.parseInt(group, 16).toString(16),
  );
};
