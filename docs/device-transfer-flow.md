# Device Transfer Flow

## Rule

Device join is allowed only when an already trusted old device is still available and active.

## Flow

1. Old device calls `POST /v1/device-transfer/init`.
2. API creates a short-lived session (default 300 s) and returns a transfer token.
3. New device receives the session payload via QR or equivalent local handoff.
4. New device calls `POST /v1/device-transfer/claim` with its own public material and an auth proof over `transfer-claim:<sessionId>:<transferToken>`.
5. Both devices show the claimant fingerprint; the user compares them group by group.
6. Old device calls `POST /v1/device-transfer/approve` for that specific `claimId`, with `approvalProof`: its auth key's signature over `transfer-approve:<sessionId>:<claimId>:<claimantFingerprint>` (the fingerprint exactly as the claim and status responses give it).
7. New device calls `POST /v1/device-transfer/complete` with the approved `claimId` and a fresh proof over `transfer-complete:<sessionId>:<claimId>:<transferToken>` from the same new-device auth key used during claim.
8. API verifies token, session freshness, claim approval, old-device activity, and final new-device possession proof.
9. API creates the new trusted device, links it to the approving old device, moves preferred routing to the new device, and revokes the old device in the same transaction.

## First claim wins

Anyone who sees the QR code holds a valid transfer token, so a claim on its own
proves nothing about *which* device made it. The server therefore never lets a
later claim replace an earlier one:

- The claim is stored with `SET NX` (`EphemeralStoreService.setJsonIfAbsent`).
  The first valid claim wins.
- A second valid claim means the code leaked. The server invalidates the whole
  session, deletes the stored claim and answers `409 transfer_claim_invalid`.
- From then on `GET /v1/device-transfer/sessions/:id` reports `invalidated`
  (never `completed`, which would make the old device log itself out), and
  `approve` and `complete` answer `403 transfer_session_inactive`. The user
  starts a new transfer.
- `approve` only accepts the first claim's `claimId`; any other id answers
  `403 transfer_claim_required`.

Invalidation is durable: the session's token hash is replaced by a marker that
can never match a token, and the session is closed. It does not depend on the
ephemeral store keeping a flag alive.

## Ending without a transfer

The old device logs itself out when status reports `completed`, so only a
transfer that actually happened may report it. A session that ends any other
way keeps a marker in place of its token hash and reports:

| How the session ended | Status |
| --- | --- |
| A second valid claim | `invalidated` |
| It expired (including when a late claim, approve or complete closes it) | `expired` |
| The old device started a newer transfer | `expired` |
| `complete` succeeded | `completed` |

## Claimant fingerprint

`claimantFingerprint` is the full SHA-256, in lowercase hex, of the new
device's raw auth public key followed by its raw identity public key (both
base64url-decoded), shown as 16 groups of 4 characters:

```
3f1a 09c2 77de 4b10 ... (16 groups)
```

It binds both keys the new device will be trusted with. The earlier 6+4
character preview of the auth key alone was cheap to collide. The auth key has
been verified as a 32-byte Ed25519 key before the fingerprint is computed, so
the concatenation is unambiguous.

## Approval needs the old device's key, not only its token

Approving hands the account to the claimant's keys for good, so a bearer
token is not enough: a stolen access or refresh token of the old device would
otherwise let a thief run init, claim with keys of their own, approve and
complete, revoke the real device and take the handle (there is no recovery).
The approval therefore carries `approvalProof`, the old device's signature
with the auth key it logs in with over
`transfer-approve:<sessionId>:<claimId>:<claimantFingerprint>`. Binding the
fingerprint means the signature covers exactly the keys the user compared on
both screens; the `transfer-approve:` prefix keeps it apart from a login
proof. A missing or wrong proof answers `401 invalid_device_signature` and
leaves the claim unapproved, so `complete` keeps answering
`403 transfer_approval_required`.

A production relay requires the proof. A development relay checks a proof it
receives and accepts an approval without one, so clients released before the
proof keep working until they sign; the production boot gate means no public
relay runs that way. This does not help against malware or same-origin script
on the old device itself, which can use its key.

The same step-up guards the other requests a stolen token could use to lock
the owner out for good: `DELETE /v1/account` and `POST /v1/devices/revoke`
for the calling device or the account's last active device carry
`{challengeId, signature}`, a challenge from `POST /v1/auth/challenge` for the
calling device signed over `account-delete:<challengeId>:<challenge>` or
`device-revoke:<deviceId>:<challengeId>:<challenge>`.

## Retrying `complete`

`complete` commits (the new device created, the old one revoked) before its
answer leaves the server, and the old device then logs itself out. If that
answer is lost, the new device sends the same request again: a completed
session whose token matches answers with the original completion (same
`newDeviceId`, `handle` and `completedAt`) when the proof verifies against the
new device's stored auth key, and changes nothing. A proof by any other key
answers `401 transfer_completion_invalid`; once the new device has been
revoked, `403 transfer_session_inactive`. Clients keep the new device's keys
until they have its id and a session, and retry `complete` on a network error
or 5xx instead of discarding them.

## Explicit failure condition

If the old trusted device is unavailable, inactive, or already revoked, completion fails. There is no fallback recovery route.

## Security note

The transfer session coordinates trusted-device join. It must not become a hidden recovery mechanism. Keep TTLs short, require a new-device claim, and require explicit old-device approval for that exact claim every time.
