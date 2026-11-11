import { z } from 'zod';

const BOOLEAN_SPELLINGS = ['true', 'false', '1', '0', 'yes', 'no'] as const;
const TRUE_SPELLINGS: ReadonlySet<string> = new Set(['true', '1', 'yes']);

// Zod's boolean coercion is Boolean(value): every non-empty string, 'false'
// included, became true — which silently satisfied the production
// crypto-audit gate. Only explicit spellings are accepted; anything else
// fails boot instead of guessing.
export const envBoolean = (defaultValue: boolean) =>
  z
    .preprocess(
      (value) => (typeof value === 'string' ? value.trim().toLowerCase() : value),
      z.union([z.boolean(), z.enum(BOOLEAN_SPELLINGS)]),
    )
    .default(defaultValue)
    .transform((value) => (typeof value === 'boolean' ? value : TRUE_SPELLINGS.has(value)));

export const CLIENT_IP_SOURCES = ['socket', 'x-forwarded-for', 'cf-connecting-ip'] as const;
export type ClientIpSource = (typeof CLIENT_IP_SOURCES)[number];

const envObject = z.object({
  VEIL_ENV: z.enum(['development', 'test', 'production']).default('development'),
  VEIL_API_PORT: z.coerce.number().int().positive().default(3000),
  VEIL_DATABASE_URL: z.string().min(1),
  VEIL_REDIS_URL: z.string().url().optional(),
  VEIL_ALLOWED_ORIGINS: z.string().optional(),
  // Where the rate limiter reads the client address from. Only the edge in
  // front of the API can vouch for a forwarding header, so the operator names
  // exactly one: `socket` (no proxy), `x-forwarded-for` (Caddy/nginx, with
  // VEIL_TRUSTED_PROXY_HOPS proxies in front) or `cf-connecting-ip`
  // (Cloudflare Tunnel, where the socket peer is the local cloudflared).
  VEIL_CLIENT_IP_SOURCE: z.enum(CLIENT_IP_SOURCES).default('socket'),
  VEIL_TRUSTED_PROXY_HOPS: z.coerce.number().int().min(1).default(1),
  VEIL_ENABLE_SWAGGER: envBoolean(false),
  VEIL_PUSH_PROVIDER: z.enum(['none', 'apns', 'fcm', 'unifiedpush']).default('none'),
  VEIL_PUSH_ENABLE_DELIVERY: envBoolean(false),
  VEIL_UNIFIEDPUSH_ALLOWED_HOSTS: z.string().optional(),
  VEIL_APNS_BUNDLE_ID: z.string().optional(),
  VEIL_APNS_TEAM_ID: z.string().optional(),
  VEIL_APNS_KEY_ID: z.string().optional(),
  VEIL_APNS_PRIVATE_KEY_PEM: z.string().optional(),
  VEIL_APNS_USE_SANDBOX: envBoolean(true),
  VEIL_FCM_PROJECT_ID: z.string().optional(),
  VEIL_FCM_SERVICE_ACCOUNT_JSON: z.string().optional(),
  VEIL_S3_ENDPOINT: z.string().url(),
  VEIL_S3_PUBLIC_ENDPOINT: z.string().url().optional(),
  VEIL_S3_REGION: z.string().min(1),
  VEIL_S3_ACCESS_KEY: z.string().min(1),
  VEIL_S3_SECRET_KEY: z.string().min(1),
  VEIL_S3_BUCKET: z.string().min(1),
  VEIL_ATTACHMENT_MAX_BYTES: z.coerce
    .number()
    .int()
    .positive()
    .default(50 * 1024 * 1024),
  VEIL_ATTACHMENT_ALLOWED_MIME_TYPES: z
    .string()
    .default(
      ['image/jpeg', 'image/png', 'image/webp', 'application/pdf', 'application/octet-stream'].join(
        ',',
      ),
    ),
  // Refuse weak JWT secrets at boot. 32 bytes is the floor for HS256
  // — anything shorter shrinks the keyspace below the algorithm's
  // security target. Use `openssl rand -base64 32` to generate one.
  VEIL_JWT_SECRET: z.string().min(32),
  VEIL_JWT_AUDIENCE: z.string().min(1).default('veil-mobile'),
  VEIL_JWT_ISSUER: z.string().min(1).default('veil-api'),
  VEIL_LOG_LEVEL: z.enum(['debug', 'info', 'warn', 'error']).default('info'),
  VEIL_TRANSFER_TOKEN_TTL_SECONDS: z.coerce.number().int().positive().default(300),
  VEIL_AUTH_CHALLENGE_TTL_SECONDS: z.coerce.number().int().positive().default(120),
  // Server-side metadata retention. The threat model says the server should
  // not hoard who-called-whom forever; terminal call records older than this
  // are swept. 0 disables the sweep (retain indefinitely). Default 30 days;
  // production accepts 1 to 30, the window the privacy policy publishes.
  VEIL_CALL_RECORD_RETENTION_DAYS: z.coerce.number().int().min(0).default(30),
  // Consumed X3DH one-time prekeys are kept briefly after use (so a keyId is
  // never reused mid-flight), then pruned. Clients issue monotonic keyIds and
  // never resubmit consumed ones, so a bounded window is safe. 0 disables the
  // sweep (retain indefinitely). Default 30 days.
  VEIL_PREKEY_CONSUMED_RETENTION_DAYS: z.coerce.number().int().min(0).default(30),
  // Hard cap on how long any message ciphertext stays on the server, delivered
  // or not, whatever the disappearing timer says. 0 disables the cap (only
  // the timer and view-once then remove messages). Default 30 days;
  // production accepts 1 to 30, the cap the privacy policy publishes.
  VEIL_MESSAGE_MAX_AGE_DAYS: z.coerce.number().int().min(0).default(30),
  // Key for the HMAC that stands in for a deleted account's handle while it
  // is quarantined. Without the key, the retired_handles table cannot be
  // checked against a list of candidate handles. Required in production.
  VEIL_RETIRED_HANDLE_PEPPER: z.preprocess(
    (value) => (value === '' ? undefined : value),
    z.string().min(32).optional(),
  ),
  VEIL_AUDITED_CRYPTO_ATTESTED: envBoolean(false),
  // SHA-256 (lowercase hex) of the signed external audit report. Production
  // refuses to boot without it, so an attestation always names the exact
  // report it rests on. Empty means unset: compose forwards `${VAR:-}`.
  VEIL_AUDIT_REPORT_SHA256: z.preprocess(
    (value) => (value === '' ? undefined : value),
    z
      .string()
      .regex(/^[0-9a-f]{64}$/, 'VEIL_AUDIT_REPORT_SHA256 must be 64 lowercase hex characters')
      .optional(),
  ),
  // Bearer token required to scrape /metrics. Empty disables the
  // endpoint entirely (the route 404s) — preferred default for local
  // dev so we never accidentally expose internals on the public tunnel.
  VEIL_METRICS_AUTH_TOKEN: z.string().optional(),
  // OTel collector — optional. Code is wired but no-ops until set.
  VEIL_OTEL_EXPORTER_OTLP_ENDPOINT: z.string().url().optional(),
  VEIL_OTEL_SERVICE_NAME: z.string().default('veil-api'),
});

const TRUST_PROXY_REMOVED = 'VEIL_TRUST_PROXY was removed; set VEIL_CLIENT_IP_SOURCE';

// A deployment that still sets VEIL_TRUST_PROXY expects proxy-aware client
// addresses; silently ignoring it would put every client behind the proxy in
// one rate-limit bucket. Refuse to boot until the operator picks a source.
export const envSchema = envObject
  .extend({ VEIL_TRUST_PROXY: z.unknown().optional() })
  .superRefine((env, context) => {
    if (env.VEIL_TRUST_PROXY !== undefined) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['VEIL_TRUST_PROXY'],
        message: TRUST_PROXY_REMOVED,
      });
    }
  })
  .transform(({ VEIL_TRUST_PROXY: _removed, ...env }) => env);

export type EnvConfig = z.infer<typeof envSchema>;
