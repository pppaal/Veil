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

Every relay requires the proof, whatever `VEIL_ENV` says; there is no
development-mode exception. This does not help against malware or same-origin
script on the old device itself, which can use its key.

The same step-up guards the other requests a stolen token could use to lock
the owner out for good: `DELETE /v1/account` and `POST /v1/devices/revoke`
for the calling device or the account's last active device carry
`{challengeId, signature}`, a challenge from `POST /v1/auth/challenge` for the
calling device signed over `account-delete:<challengeId>:<challenge>` or
`device-revoke:<deviceId>:<challengeId>:<challenge>`. Without the proof these
answer `401 challenge_invalid`; with a signature by another key or for another
purpose, `401 invalid_device_signature`. The challenge is consumed on first
presentation either way.

## Retrying `complete`

`complete` commits (the new device created, the old one revoked) before its
answer leaves the server, and the old device then logs itself out. If that
answer is lost, the new device sends the same request again: a completed
session whose token matches answers with the original completion (same
`newDeviceId`, `handle` and `completedAt`) when the proof verifies against the
new device's stored auth key, and changes nothing. A proof by any other key
answers `401 transfer_completion_invalid`; once the new device has been
revoked, `403 transfer_session_inactive`. This only helps a client that still
has the new device's keys. The client contract (C-TRANSFER-RETRY):

- persist the completion (the new device's id and keys) before signing in
  with `POST /v1/auth/challenge` and `/v1/auth/verify`, and keep the keys
  until it has a session;
- retry `complete` with the same request on a network error or a 5xx;
- keep polling `complete` only while it answers `403 transfer_approval_required`;
- stop on `403 transfer_session_inactive` or any other 4xx, without
  discarding keys it has not stored yet.

What the clients do:

- **Mobile** (`AppSessionController`) keeps the claim (its keys, session,
  token and claim id) in the keystore from the moment the relay accepts it,
  records that a `complete` went out before sending one, and stores the
  completion before signing in, so all of it survives an app restart. It
  sends `complete` up to three times through network failures and 5xx, polls
  while the old device has not approved, and stops on any other refusal
  without dropping the keys. A claim whose completion went unanswered (the
  relay may have committed it) or whose sign-in did not finish is resumed on
  the next start and stays completable on the transfer screen however long
  ago the claim window closed; the relay decides, answering a committed
  transfer with the same completion, and only its
  `403 transfer_session_inactive` ends the claim and shows it as expired.
  Such a claim is never replaced by a new one. The window alone expires only
  a claim with no `complete` left unanswered.
- **Web** (`awaitCompletion` in `app/services/device-transfer.js`) sends the
  same request again after a network failure or a 5xx for as long as the tab
  is open, even if the dialog was closed, polls while the old device has not
  approved, and stops on any other refusal, offering the same claim again
  until a new code is claimed. Once `complete` answers, it saves the keys
  before the first sign-in and keeps them in memory until a save succeeds.
  Limitation: until that save, the keys exist only in the tab's memory, so
  closing or reloading the tab while `complete` is unanswered, or before the
  save, loses them; if the relay had committed, the account is lost, as there
  is no recovery. The dialog says to keep the tab open when a save fails.

## Explicit failure condition

If the old trusted device is unavailable, inactive, or already revoked, completion fails. There is no fallback recovery route.

## Security note

The transfer session coordinates trusted-device join. It must not become a hidden recovery mechanism. Keep TTLs short, require a new-device claim, and require explicit old-device approval for that exact claim every time.
