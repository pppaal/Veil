# Device Transfer Flow

## Rule

Device transfer is allowed only when the old device is still available and active.

## Flow

1. Old device calls `POST /v1/device-transfer/init`.
2. API creates a short-lived session and returns a transfer token.
3. New device receives the session payload via QR or equivalent local handoff.
4. Old device calls `POST /v1/device-transfer/approve` with the new device public material.
5. New device calls `POST /v1/device-transfer/complete`.
6. API verifies token, session freshness, approval presence, and old-device activity.
7. API creates the new device, marks it active, and revokes the old device.

## Explicit failure condition

If the old device is unavailable, inactive, or already revoked, completion fails. There is no fallback recovery route.

## Security note

The transfer session coordinates device replacement. It must not become a hidden recovery mechanism. Keep TTLs short and require explicit old-device approval every time.
