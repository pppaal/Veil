# Trusted Device Graph

VEIL private beta uses a trusted-device graph, not cloud recovery and not Telegram-style cloud sync.

## Core rules

- A user can have multiple concurrently trusted devices.
- Joining a new device requires an already trusted old device to initiate and approve the handoff.
- Losing every trusted device still means account and message access are unrecoverable.
- Sensitive key material remains device-side.
- The server stores device graph metadata, ciphertext-like message envelopes, and per-device sync cursors only.

## Preferred device vs trusted devices

- `users.active_device_id` remains the preferred routing device for directory and compatibility purposes.
- Authentication and realtime access are granted to any trusted device that is still active and not revoked.
- The preferred device can change without revoking older trusted devices.
- UI trust states are exposed as `current`, `preferred`, `trusted`, `stale`, and `revoked`.

## Join flow

1. A trusted device initiates a short-lived join session.
2. The new device imports the session payload and creates a signed claim with its own auth key material.
3. The old device approves the exact `claimId`.
4. The new device completes the join with a second proof.
5. The new device is added to the trusted graph with `joined_from_device_id` pointing at the approving device.
6. The old device remains trusted until it is explicitly revoked.

## Revoke flow

- Revoking a device invalidates that device's bearer usage and websocket session.
- If the revoked device was the preferred device, VEIL selects another trusted device as the preferred device when available.
- Revoke does not create a recovery path.

## Per-device sync state

VEIL tracks device-local sync metadata on the server to support multi-device reliability without storing plaintext:

- `last_synced_conversation_order`
- `last_read_conversation_order`
- device `last_sync_at`

These values are metadata only. Message bodies remain ciphertext-like payloads.

## Stale device handling

- A device becomes `stale` when it has no recent trusted activity for an extended window.
- `trusted activity` uses the newest of device `last_seen_at` and device `last_sync_at`.
- `stale` does not mean revoked. It is still trusted until explicitly revoked.
- The settings UI should surface stale devices clearly so the user can retire them deliberately.

## What stays unchanged for real crypto

- Join still requires an existing trusted device.
- Device graph metadata can remain server-side.
- Per-device sync cursors can remain server-side.
- Ciphertext-only message relay architecture stays intact.

## What must change for audited real crypto

- Preferred-device key bundle routing must evolve into a per-device bundle directory and encrypted fanout model.
- Joined devices will need audited per-device session bootstrap and persisted session state.
- Local cache and search indexing will need to account for real encrypted session material.

## Remaining risks

- Current crypto is still mock-only and not production E2EE.
- Device bundle selection is still compatibility-oriented around the preferred device.
- Push remains metadata-only; provider integration will need a dedicated privacy review.
