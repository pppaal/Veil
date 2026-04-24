# Call Infrastructure Plan

Voice and video calls need two pieces of infrastructure that Veil does not
ship yet:

1. **TURN relay** for NAT traversal when peers can't reach each other
   directly (roughly 15–20% of real-world calls).
2. **SFU** (Selective Forwarding Unit) for group calls or for any case
   where we don't want to burn the sender's uplink on every recipient.

This document captures the target topology and the credential flow. It is
deliberately short on product decisions — those live in the call-module
module's design docs — and focuses on what has to exist in the deployment
plane.

## Target stack

- **Coturn** for STUN/TURN. Self-hosted, OSS, small ops surface.
- **LiveKit** for SFU. Self-hosted OSS option or LiveKit Cloud. LiveKit's
  server-side room-create API fits cleanly behind our existing auth layer.

Both can be hot-swapped. The mobile client treats TURN URLs and SFU tokens
as opaque strings from the API; rotating providers requires no client
change beyond an app config push.

## Topology

```
            +-------------------+
            |   Veil API        |
  (auth) -->|  /calls/start     |-- create LiveKit room
            |  /calls/turn-creds|-- mint HMAC-TURN credential
            +-------------------+
                     |
                     v
  +----------+   +----------+   +----------+
  | Sender   |   | Receiver |   | Receiver |
  |  (iOS)   |   |  (iOS)   |   | (Android)|
  +----+-----+   +-----+----+   +-----+----+
       |               |              |
       +---- P2P or ---+              |
       |     via Coturn               |
       +------------- via LiveKit SFU-+
```

## Credential flow

### TURN

Coturn runs in `--use-auth-secret` mode with a shared secret
`TURN_SHARED_SECRET`. The API mints a short-lived (10 min) credential on
demand:

```
POST /v1/calls/turn-creds   Auth: <bearer>
--
200
{
  "uris": ["turn:turn.veil.app:3478?transport=udp",
           "turn:turn.veil.app:3478?transport=tcp",
           "turns:turn.veil.app:5349?transport=tcp"],
  "username": "1745020800:<deviceId>",    // expiry-prefixed
  "credential": base64(hmacSha1(TURN_SHARED_SECRET, username)),
  "expiresAt": "2026-04-24T12:00:00Z"
}
```

Client passes the pair straight into the WebRTC `RTCPeerConnection` config.

### LiveKit

Participant JWTs are issued by the API after validating the caller has
permission to join the conversation. Token claims include `sub = userId`,
`video.room = callId`, `video.canPublish`, `video.canSubscribe`.

```
POST /v1/calls/livekit-token  Auth: <bearer>
Body: { callId }
--
200 { "token": "<jwt>", "url": "wss://livekit.veil.app", "expiresAt": "..." }
```

## Deploy unit

Coturn lives in `infra/docker/coturn/`. LiveKit can be deployed via their
published Helm chart or LiveKit Cloud; no repo-hosted compose because the
deployment decision is environmental.

The Coturn compose is written so it can be run on any VPS with a public IP
and two open ports (3478/UDP+TCP and 5349/TCP for TURNS). Production
deployment is expected behind a stable DNS name with a real TLS cert.

## Secrets that need to exist

| Name                      | Shape     | Where it lives          |
|---------------------------|-----------|-------------------------|
| `TURN_SHARED_SECRET`      | 32-byte hex | API env + Coturn conf |
| `LIVEKIT_API_KEY`         | string    | API env                 |
| `LIVEKIT_API_SECRET`      | string    | API env                 |
| `LIVEKIT_URL`             | wss URL   | API env + mobile config |
| `TURN_URL`                | turn(s) URL | mobile config fallback |

Production launch is blocked until these exist. Rotation runbook lives at
`docs/ops/secrets-rotation.md`.

## Minimum-viable test plan before shipping calls

1. **Direct call on same NAT**: should succeed via direct P2P, TURN
   untouched. Verify by checking TURN allocation count stays 0.
2. **Direct call across NATs (asymmetric NAT)**: should succeed via TURN
   relay. Verify bandwidth accounting on the TURN server.
3. **Group call (3 participants)**: should route through the SFU. Verify
   uplink bandwidth stays flat as participants increase.
4. **Mobile → backgrounded → foreground**: re-ICE completes within 5s.
5. **TURNS (TLS)** path works on a network that blocks UDP.

## What this plan does NOT handle

- call recording (deliberately out of scope — privacy product)
- end-to-end encryption of call media (LiveKit E2EE add-on is possible but
  requires a separate design doc — SFU sees ciphertext only if configured
  for E2EE mode, which has UX implications on reconnect)
- SIP/PSTN bridges (explicitly out of scope)
