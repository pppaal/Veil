# Device Transfer Flow

## Rule

Device join is allowed only when an already trusted old device is still available and active.

## Flow

1. Old device calls `POST /v1/device-transfer/init`.
2. API creates a short-lived session and returns a transfer token.
3. New device receives the session payload via QR or equivalent local handoff.
4. New device calls `POST /v1/device-transfer/claim` with its own public material and auth proof.
5. Old device calls `POST /v1/device-transfer/approve` for that specific `claimId`.
6. New device calls `POST /v1/device-transfer/complete` with the approved `claimId` and a fresh proof from the same new-device auth key used during claim.
7. API verifies token, session freshness, claim approval, old-device activity, and final new-device possession proof.
8. API creates the new trusted device, links it to the approving old device, and moves preferred routing to the new device.
9. The old device remains trusted until it is explicitly revoked.

## Explicit failure condition

If the old trusted device is unavailable, inactive, or already revoked, completion fails. There is no fallback recovery route.

## Security note

The transfer session coordinates trusted-device join. It must not become a hidden recovery mechanism. Keep TTLs short, require a new-device claim, and require explicit old-device approval for that exact claim every time.
