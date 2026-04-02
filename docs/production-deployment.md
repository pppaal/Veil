# Production Deployment Checklist

VEIL is not production-ready yet. This checklist is the minimum path to get there without violating the product philosophy.

The current API intentionally blocks `VEIL_ENV=production` at startup because the mock crypto boundary is still wired.

## 1. Replace mock crypto

- Replace the mock `CryptoEngine` adapters on mobile with audited real messaging/session primitives.
- Keep the existing envelope and adapter boundary intact.
- Do not add server-side decryption helpers.
- Add cross-platform crypto interoperability tests before rollout.

## 2. Harden device auth

- Keep challenge verification on uploaded device auth public keys only.
- Add secure hardware or platform keystore integration where supported.
- Add explicit device-key lifecycle review for revoke, transfer, and local wipe.
- Keep device transfer dependent on old-device possession.
- Rotate and invalidate bearer tokens on revoke/transfer in production infrastructure.

## 3. Harden storage

- Move from local/dev object storage tickets to real presigned URL generation.
- Enforce strict bucket policies for encrypted blobs only.
- Add object retention, content-size controls, and abuse controls.
- Keep the mobile local cache encrypted at rest and review key lifecycle on logout/revoke.

## 4. Harden operations

- Move all secrets to a managed secret store.
- Use TLS everywhere.
- Isolate Postgres, Redis, and object storage in private networks.
- Add structured log sinks that never store plaintext message content.
- Review metrics and traces for accidental payload leakage.

## 5. Mobile release work

- Add iOS and Android signing configuration.
- Validate biometric and PIN flows on real devices.
- Run Drift codegen in CI for mobile builds.
- Add release QA for onboarding, chat, attachments, app lock, revoke, and transfer.

## 6. Delivery and infra

- Add environment-specific deploy manifests.
- Add migration automation for Prisma.
- Publish API images from CI.
- Add staged deployment with smoke checks against `/v1/health`.
- Remove the production boot guard only after the mock auth and crypto adapters are fully replaced.

## 7. Security review

- Conduct a formal threat model review against the implemented system.
- Run application and infrastructure penetration tests.
- Verify there is no plaintext in logs, analytics, push payloads, or storage.
- Verify there is no hidden recovery path, server-side decryption, or admin message viewer.
