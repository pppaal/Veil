# Server-side metadata retention

VEIL's threat model promises the server keeps as little as possible. Message
bodies are always ciphertext, and the disappearing-message sweep hard-deletes
expired messages. But some **operational metadata** otherwise lived on the
server forever — which the 20-agent audit flagged as finding **#5 (metadata
retained forever)**. This is the track that bounds it.

## Implemented: call-record retention

`RetentionService` (`apps/api/src/modules/retention/`) runs a sweep every 10
minutes that hard-deletes **terminal call records** older than a configurable
window:

```bash
VEIL_CALL_RECORD_RETENTION_DAYS=30   # 0 = retain forever
```

- Only **finished** calls are eligible (`ended`, `missed`, `declined`). An
  in-flight call (`ringing`, `active`) is never deleted out from under the
  participants.
- The sweep logs a **count only** (`retention.call_records_pruned`) — never a
  conversation/device/user id, so we don't log the very metadata we're deleting.
- Best-effort: a failed sweep is swallowed and retried next interval; the timer
  never throws.

Why call records first: they are pure server-side history (who called whom,
when, how long) with **no delivery-correctness coupling** — safe to bound
immediately. Clients keep their own call log locally, consistent with the
E2E "the server is just a relay" principle.

Covered by `apps/api/test/unit/retention.service.spec.ts`: terminal-only
filter, cutoff math, disabled at 0, count-only logging, failure swallowed.

## Follow-ups (deliberately not in this slice)

Each touches delivery or UX and deserves its own careful change:

- **Absolute message-age cap** — hard-delete delivered messages past a maximum
  age regardless of disappearing timer. Needs a delivery-window policy so a
  device offline longer than the cap doesn't silently lose messages.
- **Read-receipt pruning** — receipts are metadata, but dropping them changes
  read-state UX; bound them once the product decision is made. (Receipts
  already cascade-delete with their message.)
- **Attachment metadata** (`sha256`/size/MIME) and **contact-graph** minimization
  — larger redesigns tracked against audit #5.

## Relationship to other tracks

This is the present-day complement to the **sealed sender** spec (PR #8): sealed
sender stops the server from learning the *sender* of a message; retention stops
it from *keeping* the metadata it does see. Together they move VEIL toward the
SimpleX metadata bar.
