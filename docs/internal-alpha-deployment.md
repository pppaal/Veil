# VEIL Internal Alpha Deployment

This document describes how to deploy the current VEIL scaffold for internal alpha use.

This is not a production deployment guide.

## Purpose

Use this path for:

- internal demos
- design validation
- product QA
- API and mobile integration testing

Do not use this deployment for public traffic or real private communications.

## 1. Prepare the alpha API environment

Copy the alpha example environment:

```bash
cp apps/api/.env.alpha.example apps/api/.env.alpha
```

Set at least these values before boot:

- `VEIL_JWT_SECRET`
- `VEIL_S3_PUBLIC_ENDPOINT`
- `VEIL_ALLOWED_ORIGINS`

The alpha compose file expects service hostnames:

- `postgres`
- `redis`
- `minio`

Use `VEIL_S3_ENDPOINT` for container-to-MinIO traffic and `VEIL_S3_PUBLIC_ENDPOINT` for the signed attachment URLs returned to the client. The default alpha example uses `http://127.0.0.1:9000` for host-side desktop smoke tests.
Restrict `VEIL_ALLOWED_ORIGINS` to the exact private-beta web or desktop origins you expect. Do not leave wildcard browser origins in place.

## 2. Start the alpha stack

```bash
pnpm docker:alpha:up
```

This starts:

- Postgres
- Redis
- MinIO
- MinIO bucket bootstrap
- the NestJS API container

The API is exposed on:

```text
http://localhost:3000/v1
```

## 3. Verify the deployment

Check the health endpoint:

```text
GET http://localhost:3000/v1/health
```

Expected response:

```json
{"status":"ok","service":"veil-api"}
```

Then run the internal alpha smoke:

```bash
pnpm alpha:smoke
```

This validates:

- register -> challenge -> verify
- direct conversation creation
- attachment upload ticket -> upload -> complete
- encrypted envelope send/list
- attachment download ticket
- old-device-required transfer

## 4. Connect the mobile app

Use the same API endpoints in the mobile runtime:

```bash
pnpm dev:mobile:api
```

Or run Flutter manually with matching `--dart-define` values.

## 5. Tear down

```bash
pnpm docker:alpha:down
```

## 6. Current limits

- Mock crypto is still active.
- Device auth now uses device-held signing, but the overall crypto stack is still internal-alpha only.
- Local mobile cache is encrypted at rest for this alpha path, but it still depends on the current dev crypto boundary and app-lock posture.
- Attachment storage still uses alpha placeholder blobs.
- Push fallback is metadata-only and the real APNs/FCM provider seam is still not wired.
- External endpoints must use TLS in the mobile runtime. Non-local plain HTTP or WS endpoints are rejected at app startup.
- This deployment path is for internal alpha only.
