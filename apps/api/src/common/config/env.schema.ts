import { z } from 'zod';

export const envSchema = z.object({
  VEIL_ENV: z.enum(['development', 'test', 'production']).default('development'),
  VEIL_API_PORT: z.coerce.number().int().positive().default(3000),
  VEIL_DATABASE_URL: z.string().min(1),
  VEIL_REDIS_URL: z.string().url().optional(),
  VEIL_ALLOWED_ORIGINS: z.string().optional(),
  VEIL_TRUST_PROXY: z.coerce.boolean().default(false),
  VEIL_ENABLE_SWAGGER: z.coerce.boolean().default(true),
  VEIL_S3_ENDPOINT: z.string().url(),
  VEIL_S3_PUBLIC_ENDPOINT: z.string().url().optional(),
  VEIL_S3_REGION: z.string().min(1),
  VEIL_S3_ACCESS_KEY: z.string().min(1),
  VEIL_S3_SECRET_KEY: z.string().min(1),
  VEIL_S3_BUCKET: z.string().min(1),
  VEIL_JWT_SECRET: z.string().min(1),
  VEIL_JWT_AUDIENCE: z.string().min(1).default('veil-mobile'),
  VEIL_JWT_ISSUER: z.string().min(1).default('veil-api'),
  VEIL_LOG_LEVEL: z.enum(['debug', 'info', 'warn', 'error']).default('info'),
  VEIL_TRANSFER_TOKEN_TTL_SECONDS: z.coerce.number().int().positive().default(300),
  VEIL_AUTH_CHALLENGE_TTL_SECONDS: z.coerce.number().int().positive().default(120),
});

export type EnvConfig = z.infer<typeof envSchema>;
