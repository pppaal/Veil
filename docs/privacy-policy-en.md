# VEIL Privacy Policy

Effective: 2026-04-20
Last updated: 2026-04-20

VEIL ("the service") collects the absolute minimum data required to operate an end-to-end encrypted messenger. This policy describes what we collect, why, how long we keep it, and the rights users hold. It is written to satisfy Korea's Personal Information Protection Act (PIPA) alongside general privacy expectations.

## 1. Data we collect

The service collects only:

- An anonymous user ID and device ID generated on the device.
- A user-chosen handle and optional display name.
- End-to-end encrypted message payloads that the server cannot decrypt.

The service does **not** collect:

- Phone numbers, email addresses, or real names.
- National ID numbers, address books, or location data.
- Payment information or purchase history.
- Advertising identifiers (IDFA/AAID) or third-party analytics identifiers.

## 2. How we use data

- Service delivery: routing conversations, device authentication, session management.
- Security: abuse prevention and anomalous-access blocking.
- Legal compliance where required.

We do **not** use data for advertising, marketing, or profiling.

## 3. Retention

- Account identifiers and device records are deleted immediately when an account is deleted.
- Ciphertext message payloads are held briefly until the recipient device fetches them, then deleted — and in any case purged after at most 30 days.
- Anything retained for legal reasons is kept only for the period that law requires.

## 4. Third parties and cross-border transfers

We do not sell, share, or transfer user data to third parties, advertising partners, analytics vendors, or data brokers.

## 5. User rights

Users may at any time:

- Request access, correction, or deletion of personal information.
- Request a halt to processing.
- Delete their account in-app; this is executed immediately from the settings screen.

Deleting an account purges all associated server-side identifiers and queued ciphertext.

## 6. No-recovery posture

VEIL has **no account recovery path by design.** If a device is lost or wiped, conversations cannot be restored. This is not a defect; it is the privacy guarantee the product is built around.

## 7. Security controls

- End-to-end encryption: X25519 + AES-256-GCM + Ed25519 + HKDF-SHA256.
- The server cannot decrypt message content, attachments, or metadata payloads.
- On-device storage is protected by OS-level keychain / secure storage.
- The app supports local lock via PIN and biometrics.

## 8. Children

The service is not directed to users under the age of 14, and we do not knowingly collect their personal data.

## 9. Privacy officer

- Email: privacy@veil.app

## 10. Changes to this policy

Changes will be announced in-app and at https://veil.app/privacy before taking effect.
