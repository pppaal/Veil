import { createHmac, randomBytes } from 'node:crypto';

export interface RoutedRequest {
  baseUrl?: string;
  route?: { path?: unknown };
}

export type Clock = () => Date;

const UNMATCHED_ROUTE = 'unmatched';

// The Express route template ('/v1/users/:handle') that matched the request.
// Logs, error telemetry and metrics labels use this instead of the concrete
// path, so handles, ids and query strings never reach durable storage and
// metric cardinality stays bounded by the number of routes. It is never
// derived from the raw URL: prefix-sensitive regex redaction is exactly what
// the /v1 global prefix silently defeated.
export function routeTemplate(request: RoutedRequest): string {
  const path = request.route?.path;
  if (typeof path !== 'string') {
    return UNMATCHED_ROUTE;
  }
  return (request.baseUrl ?? '') + path;
}

const ACTOR_REF_HEX_LENGTH = 16;

const utcDay = (date: Date): string => date.toISOString().slice(0, 10);

// Pseudonymous actor reference for error telemetry. Operators can correlate
// the 5xx lines of one actor within a UTC day, but the key lives only in
// memory and is replaced every day, so a leaked log cannot be joined to a
// user id — or across days — without that day's key.
export class ActorRefGenerator {
  private key = randomBytes(32);
  private keyDay: string;

  constructor(private readonly clock: Clock = () => new Date()) {
    this.keyDay = utcDay(this.clock());
  }

  actorRef(userId: string): string {
    const today = utcDay(this.clock());
    if (today !== this.keyDay) {
      this.key = randomBytes(32);
      this.keyDay = today;
    }
    return createHmac('sha256', this.key)
      .update(userId)
      .digest('hex')
      .slice(0, ACTOR_REF_HEX_LENGTH);
  }
}
