# UnifiedPush — Google-free push & the F-Droid path

VEIL's wake-only push now has a third provider alongside APNs and FCM:
**UnifiedPush** (<https://unifiedpush.org>). It lets the app receive "you have a
message, reconnect" wakes through a **user-chosen distributor** (ntfy,
NextPush, a self-hosted server …) with **no Google or Apple dependency** — the
prerequisite for shipping VEIL on **F-Droid** and to de-Googled Android.

This is a positioning lever for the Korea launch: a genuinely Google-free
privacy messenger, installable without a Play account.

## How it works

```
┌────────────┐  register   ┌──────────────┐
│  VEIL app  │────────────▶│ Distributor  │  (ntfy app, NextPush, self-hosted)
│ (Android)  │◀────────────│              │
└────────────┘ endpoint URL└──────────────┘
      │                            ▲
      │ POST /devices              │ POST <endpoint>  (opaque wake)
      │ { pushToken: endpoint }    │
      ▼                            │
┌────────────┐  new message  ┌─────┴───────┐
│ VEIL server│──────────────▶│ VEIL server │
└────────────┘   wake hint    └─────────────┘
```

1. The app registers with its distributor and gets an **HTTPS endpoint URL**.
2. It sends that URL to the VEIL server as its **push token** (same field APNs/FCM
   tokens use today).
3. On a new message the server **POSTs an opaque, constant body** (`{"kind":"wake"}`)
   to the endpoint. The distributor relays it; the app wakes and reconnects over
   the normal E2E channel. **No conversation metadata ever leaves the server** —
   identical wake-only contract to APNs/FCM.

## Server configuration

```bash
VEIL_PUSH_PROVIDER=unifiedpush
VEIL_PUSH_ENABLE_DELIVERY=true
# STRONGLY recommended in production (see SSRF below):
VEIL_UNIFIEDPUSH_ALLOWED_HOSTS=ntfy.sh,push.mydomain.example
```

UnifiedPush needs **no server-side credentials** — the device's distributor
endpoint is the token — so delivery is valid as soon as the provider is
selected (the production boot check was updated accordingly).

## Security — SSRF (read this before enabling)

The "push token" is a **URL the client fully controls**, and the server makes an
outbound request to it. Without a guard a malicious registrant could point it at
cloud metadata (`169.254.169.254`) or internal services. `UnifiedPushProvider`
validates **every** endpoint before any request is built:

- **https only** — `http://` and other schemes are rejected.
- **Allowlist** — if `VEIL_UNIFIEDPUSH_ALLOWED_HOSTS` is set, the host must be on
  it. **This is the real defense** and also closes DNS-rebinding, because the
  decision is on the hostname, not a resolved-then-reconnected IP. **Set it in
  production.**
- **IP screen** — with no allowlist, literal private/loopback/link-local/CGNAT
  addresses (IPv4 and IPv6, incl. IPv4-mapped) are rejected as a best effort.
  Note: this does **not** resolve DNS hostnames, so it cannot stop a hostname
  that resolves to a private IP. Hence the allowlist.

Covered by `apps/api/test/unit/unifiedpush-push.provider.spec.ts` (28 cases:
wake-only body, scheme/allowlist/IP rejection, delivery on/off, non-2xx throw,
and an exhaustive `isPrivateHost` table).

## Mobile integration — follow-up (not in this change)

The server provider is complete and CI-tested. The Flutter side needs a real
device + distributor round-trip to validate, so it is a separate, deliberate
step:

1. Add the [`unifiedpush`](https://pub.dev/packages/unifiedpush) Flutter plugin
   (+ `unifiedpush_android` / the platform receivers).
2. On startup, if a distributor is available, `register()` and obtain the
   endpoint; fall back to FCM (Play build) or polling (no distributor).
3. Send the endpoint to the server via the existing device push-token field.
4. On `onMessage`, treat any payload as an opaque wake → reconnect the socket and
   pull new envelopes (never trust the push body for content).
5. Build flavors: a **Play** flavor (FCM) and an **F-Droid** flavor (UnifiedPush
   only, no Google libs) so the F-Droid build is reproducible and dependency-clean.

## Play / F-Droid notes

- The Play build can keep FCM; UnifiedPush is additive, selected per build flavor.
- For F-Droid, the app must be free of proprietary Google libraries in that
  flavor — UnifiedPush is what makes that possible.
- Data-safety answers are unchanged: push remains wake-only, no message content
  or conversation identifiers are sent to any push intermediary.
