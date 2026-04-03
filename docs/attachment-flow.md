# Attachment Flow

## Send path

1. Sender stages an opaque local temp blob on the device.
2. Sender asks the API for an upload ticket.
3. API creates attachment metadata, validates relay policy, and returns a scoped presigned upload target.
4. Sender uploads only the encrypted blob to S3-compatible storage.
5. Sender marks the upload complete. API verifies object metadata, content type, and size before accepting it.
6. Sender sends a message envelope containing the attachment reference and wrapped key material.
7. The local temp blob is deleted after the encrypted envelope has been finalized for send.

## Backend guarantees

- object storage receives encrypted blobs only
- API stores metadata only
- plaintext file contents never touch backend business logic
- plaintext file keys are never stored server-side
- upload/download URLs are short-lived and policy-scoped
- failed or explicitly canceled uploads are marked failed and object cleanup is attempted

## Private beta relay policy

- allowed MIME types are restricted to:
  - `image/jpeg`
  - `image/png`
  - `image/webp`
  - `application/pdf`
  - `application/octet-stream`
- max attachment size is controlled by relay configuration
- filenames are not sent to the backend or object storage metadata

## Device-side reliability behavior

- attachment uploads are resumable at the workflow level, not at the byte-range protocol level
- the device persists the temp blob path, upload ticket state, and retry metadata in the local queue
- if the network drops or the ticket expires, retry reuses the local opaque temp blob and requests a fresh ticket
- cancel stops the active upload, marks the draft failed locally, and preserves the temp blob for retry
- orphaned temp blobs are evicted locally on startup and on explicit local wipe/revoke/logout

## Current scaffold limitation

The upload/download pipeline in this repository is hardened for private beta, but it is still not production cryptography. Production still needs audited real crypto, storage policy review, encrypted media processing review, and provider-specific hardening.
