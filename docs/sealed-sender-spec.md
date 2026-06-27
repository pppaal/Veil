# VEIL — Sealed Sender Spec (sender-metadata minimization)

Status: **design proposal** for external-audit review. No code yet. Fixes
the model so the work can be scoped before implementation.

Companion docs: [`threat-model.md`](threat-model.md),
[`crypto-envelope-spec.md`](crypto-envelope-spec.md).

## 1. The gap today

Content is end-to-end encrypted, but on every `POST /messages` the server
sees **who sent it**:

- The handler verifies `envelope.senderDeviceId === auth.deviceId` (the
  JWT identifies the sender device/user).
- Membership and fan-out read `conversationMember` rows — the server knows
  the social graph (who talks to whom).
- Receipts and `conversation_order` are keyed per member.

So a server (or anyone who compromises it / subpoenas it) can reconstruct
**who messaged whom, when** — even though it can't read the messages. Push
payloads already exclude `senderDeviceId` (good), but the send path does
not. Sealed sender closes the *sender* half of that gap: the server should
be able to deliver a message to a conversation **without learning which
member sent it.**

This is metadata minimization, not metadata resistance — see Limits (§6).

## 2. Goal

A delivered message MUST NOT be linkable by the server to a specific sender
device or user. The server still learns the destination conversation,
timing, and transport IP (§6), but not the author.

## 3. Mechanism

Two pieces, mirroring Signal's sealed sender but adapted to VEIL's
conversation-membership model (Signal is identifier-based; VEIL authorizes
by membership, so the unidentified-delivery token is conversation-scoped).

### 3.1 Sender certificate (who you are, hidden from the server)

The real sender identity moves **inside** the encrypted payload. The
GCM plaintext (see `crypto-envelope-spec.md` §"Plaintext payload") gains a
signed sender certificate:

```json
{
  "body": "...",
  "kind": "text",
  "sndr": {
    "deviceId": "<sender device id>",
    "identityPub": "<b64url Ed25519 sender identity public>",
    "sig": "<b64url Ed25519 over (conversationId || ratchetPub || counter)>"
  }
}
```

Only conversation members can decrypt the payload, so only they learn the
author and verify `sig` against the membership's known identity keys. The
server never sees it. (Receivers MUST verify `sig` — otherwise a member
could spoof another member inside the conversation.)

### 3.2 Unidentified delivery (authorize without identifying)

The sender no longer presents their own bearer token on the send. Instead:

- Each conversation has a **delivery token** derived from a per-conversation
  secret shared by members (e.g. `HKDF(conversationRootSecret, "veil-delivery")`),
  rotated on membership change. The server stores only a *blinded* verifier
  (a hash/commitment), never the token itself.
- `POST /messages` is called on an **unidentified-delivery endpoint** that
  accepts the delivery token instead of the sender JWT. The token proves
  "a member of this conversation is sending" without revealing *which*.
- The wire envelope drops `senderDeviceId` (server-visible) entirely — the
  authenticated sender field is gone; authorship lives only in §3.1.

The server authorizes delivery iff the presented token matches the
conversation's verifier, then fans out to members as today.

### 3.3 What changes server-side

- `senderDeviceId` is removed from the server-visible envelope and from the
  stored message row; ordering and receipts must not depend on it (see §5).
- A new unidentified-delivery guard replaces `JwtAuthGuard` for the send
  route, validating the conversation delivery token.
- Blocking stays recipient-side: a member who receives a sealed message
  decrypts the sender cert and applies local block/mute — the server can't
  pre-filter by sender (acceptable trade-off, §6).

## 4. Phasing

1. **Direct (1:1) conversations first.** Single recipient, simplest token
   and ordering story.
2. **Groups later.** Group delivery tokens + membership-change rotation are
   the harder case (a removed member must lose the token).

## 5. Hard parts (call out for audit)

- **Ordering without sender identity.** `conversation_order` currently can
  key off the sender. v-sealed must assign a per-conversation sequence that
  doesn't leak author — e.g. server-assigned monotonic order per
  conversation (server sees order, not who). Confirm this doesn't
  reintroduce linkability across a member's sends.
- **Receipts.** Read/delivery receipts are per member; a receipt still
  reveals *a* member acted. Keep receipts but ensure they don't deanonymize
  the original *sender* (receipts are about the reader, which is fine).
- **Rate-limit / abuse.** Without sender identity, throttling is by
  conversation delivery token (per-conversation budget) + recipient-side
  blocking + token revocation on abuse. Document the abuse posture
  explicitly; this is where sealed sender trades server-side moderation for
  privacy.
- **Token theft.** A leaked delivery token lets a non-member inject to a
  conversation until rotation. Bind tokens to short epochs and rotate on
  membership change; the payload still won't decrypt for a non-member, so
  injected junk fails the GCM tag and is droppable.

## 6. Limits — be honest in the docs and UI

Sealed sender hides the **sender**, not everything:

- The server still sees the **destination conversation**, message **timing**
  and size, and the sender's **transport IP**. Linking IP+timing across
  many messages can still de-anonymize without a mixnet/Tor transport
  (SimpleX / Session go further here; VEIL does not claim to).
- It is **metadata minimization, not resistance.** State the residual
  exposure plainly so the privacy claim isn't overstated.

## 7. Next steps

- [ ] Audit review of the delivery-token construction and the ordering
      change (fold into the external-audit scope).
- [ ] Spec the unidentified-delivery endpoint + token rotation in the API
      contracts.
- [ ] Define the `sndr` certificate fields in `crypto-envelope-spec.md`
      (payload delta, mirroring the v3 PQ delta style).
- [ ] Decide the server-assigned ordering scheme and prove it's
      author-unlinkable.
