# Attachment Flow

Status: the mobile app sends and opens photos and files, and the web client
(`apps/web-demo`) sends and opens photos, files and voice messages. Both use
the same sealed blob (`encryptAttachmentV2`, pointer v2) and the same message
content, so either opens what the other sent. The phone does not play voice
messages: one from the web shows its kind and size with a line saying this
version can't open it. Paths below are under `apps/mobile/lib/src` unless
they say otherwise.

## Send path (mobile)

1. The plus in the composer opens a sheet with Photos and File. Photos opens
   the system photo picker (`image_picker`, `pickImage` from the gallery with
   `requestFullMetadata: false`: the Android Photo Picker, PHPicker on iOS),
   File the system document picker (`flutter_file_dialog`). Neither needs a
   runtime permission. Each picker runs inside `SystemSheetGrace` (see "App
   lock" below).
2. The picked copy is moved into the staging folder under an opaque name and
   the plugin's own copy is deleted at once; on iOS the system temporary
   folder the plugins write to is emptied too.
3. A photo is prepared on the phone (`image_preparer.dart`): the engine
   decodes it at a long edge of at most 1600 px (never upscaled, EXIF
   orientation applied, first frame only), and the `image` package encodes
   the pixels in an isolate as JPEG at quality 80, or PNG when a pixel is not
   opaque (a PNG over 10 MiB is flattened on white and sent as JPEG). Nothing
   but pixels goes out: location, camera details, XMP, IPTC, the embedded
   thumbnail and the colour profile are gone by construction. The photo shows
   full screen with Send while this runs.
4. A file is sent as it is, up to 25 MiB. A confirm dialog names it and the
   chat. When its bytes or its extension say it is a photo or video (JPEG,
   PNG, WebP, HEIC/HEIF, MP4/MOV/3GP, TIFF, DNG), the dialog adds "A photo or
   video sent as a file keeps any location saved in it."
5. On Send, the same check the router makes before sealing runs first (a held
   1:1 seals and uploads nothing). Then one isolate reads the staged file,
   seals it with `encryptAttachmentV2` under a fresh UUID v4 attachment id,
   and writes the ciphertext straight into the media folder; only the sealed
   reference comes back. The plaintext copy is deleted.
6. The message is stored at once with its kind, body and sealed pointer, so
   the sender's bubble shows the photo or file from the first frame. The
   queued record carries a placeholder that is never sent.
7. The outbox asks the API for an upload ticket (content type
   `application/octet-stream`, the ciphertext's size and SHA-256), uploads
   the sealed blob to the presigned URL, and marks the upload complete. The
   API checks the stored object's size and type before it accepts it.
8. Only then is the message encrypted, once, with the pointer inside the
   encrypted payload, and sent. A disappearing timer is stamped at this
   moment on the relay-corrected clock, as the web stamps it after its
   upload, so a slow upload cannot outlive a short timer.

## Receive path (mobile)

1. A message whose decrypted kind is `image` and whose pointer is eligible
   is prefetched when it is ingested (live or by history sync): the sealed
   blob is downloaded, its SHA-256 checked against the pointer's digest in an
   isolate, and the blob stored sealed. Nothing is decrypted until the photo
   is shown. Eligible: a UUID id, `alg` `aes256gcm-v2`, at most 10 MiB, not
   expired, the app open and unlocked (messages that arrive otherwise wait
   for the next unlock), and the chat with no safety number change or account
   hold waiting and not a 1:1 with a blocked account. At most 2 transfers run
   at once, newest first, and at most 50 wait per chat; the rest download
   when their bubble is built.
2. Files never download by themselves; neither do photos over 10 MiB, nor
   photos in a held or blocked chat. A tap downloads them.
3. A photo is decrypted with `decryptAttachmentV2` (digest first, in constant
   time) in an isolate that reads the sealed file itself. It renders only
   when its bytes are JPEG, PNG or WebP and the header is within the decode
   limits; it is decoded at the bubble's width, and in the full-screen viewer
   at a long edge of at most 4096 px or twice the screen's.
4. A tap on a file downloads it if needed, decrypts it into `veil_open/` and
   opens it. A file whose
   bytes are a JPEG, PNG or WebP within the limits opens in the in-app viewer.
   On iOS any other photo or video goes to Save instead, never to Quick Look.
   Everything else opens in another app through the app's own channel
   `veil/file_open`, with the MIME type taken from the file's extension.
5. Save (in the viewer and in a photo or file message's long-press menu)
   asks first, every time: "Save to your phone?" / "Other apps, and any
   cloud you save it to, can open it." Then the system save screen
   (`flutter_file_dialog`) writes the copy where the user picks.

## Limits

| What | Limit |
|---|---|
| A photo sent | re-encoded at a long edge of at most 1600 px, JPEG quality 80 (or PNG) |
| A photo source | JPEG up to 200 megapixels (decoded scaled); any other format up to 40 megapixels (decoded at full size first) |
| A file sent | 25 MiB (26 214 400 bytes, the web's `FILE_MAX_BYTES`) |
| Prefetch | photos up to 10 MiB |
| Any download | refused above 50 MiB, or for an id that is not a UUID, before any request; the body is cut off at the padded size the pointer allows |
| A photo rendered | JPEG up to 50 megapixels and 16 384 px a side; PNG and WebP up to 16 megapixels and 8 192 px a side; first frame only; at most 2 decodes at once |
| Media folder | 1 GiB, least recently used first |
| Decrypted bytes in memory | 48 MB |

The API's own limit is `VEIL_ATTACHMENT_MAX_BYTES` (50 MiB by default).

## Kinds, names and content types

- A photo from Photos is kind `image` with an empty body, content type
  `image/jpeg` or `image/png`. A file from File is kind `file`, its body the
  file's name, content type from the name's extension through a fixed map
  (else `application/octet-stream`). The web sends the same.
- A name is cleaned exactly as the web's `sanitizeFilename` cleans it
  (control, bidi and isolate characters removed, trimmed, at most 120
  characters keeping its extension, `file` when nothing is left) and travels
  only inside the encrypted message: never in a ticket, a header, storage
  metadata, the media folder or a log.
- Receivers trust bytes, not claims: the authenticated kind decides photo or
  file, a photo renders only when its bytes sniff as JPEG, PNG or WebP, and
  the content type is never used to render or to choose an app. A file card
  shows the real last extension of the cleaned name next to it, so a name
  dressed up to look like a PDF still shows what it is.

## Where blobs and plaintext live, and when they go

- Sealed blobs: one flat folder, `veil_media/` under the app support folder,
  each blob under a random name of 64 hex characters, the ciphertext exactly
  as uploaded or downloaded. Which blob belongs to which message (conversation
  id, attachment id, digest, size, expiry, last use) is kept only in the
  `media_blobs` table of the encrypted database; the key stays in the
  encrypted content store. The folder is excluded from backup.
- A blob goes when its message expires, when its chat leaves the list, when
  the 1 GiB cap reaches it (never a blob whose upload is pending), and on
  sign-out and wipe. At start, files without a row and rows without a file
  are deleted.
- Decrypted bytes: in memory only, keyed by conversation id, attachment id
  and digest, and cleared on lock, sign-out and wipe.
- Plaintext files exist only to open or save a file, in
  `veil_open/<random>/<name>` under the temporary folder. A copy goes when
  Quick Look closes (iOS), when the save screen returns and on lock (a Save
  copy), when its message expires, by a sweep every 60 seconds and on resume
  for copies older than 10 minutes, and at start and wipe. An Android copy
  opened in another app is not deleted on lock, since that app may still be
  reading it, and that app may keep a copy of its own.
- The staging folder holds a pick until it is sealed or cancelled; nothing in
  it survives a restart. Plugin copies are moved into staging or deleted at
  once, and on iOS the system temporary folder is emptied at start, after
  each pick, after each save and on wipe.

## Failure states

- Sending: a failed photo or file keeps its bubble with "Not sent. Tap to
  retry." under it; a retry reuses the same sealed blob and attachment id and
  asks for a fresh ticket when needed. A sealed blob that is missing fails the
  send for good ("This file couldn't be sent. Attach it again."); random
  bytes are never sent in its place.
- Receiving: a download that fails (network, server error, or a digest or
  decryption failure the first time) shows the download glyph and "Couldn't
  download. Tap to retry." A blob the server no longer has (ticket 403 or
  404, or the blob refused again after one fresh ticket), or a second digest
  failure, shows "Photo not available" or "File not available". A blob
  already on the phone that fails its digest is deleted and fetched again. A
  voice message, an unknown algorithm, a non-UUID id, a size over 50 MiB or
  photo bytes that are not JPEG, PNG or WebP within the limits show "Can't
  open in this version".
- Opening: "No app found to open this file", "Couldn't open the file";
  saving: "Saved", "Couldn't save. Try again.", nothing on cancel.

## Order and cancel

- The outbox drains each chat on its own, oldest first. A text sent after a
  file in the same chat waits for that file's upload; a text to any other
  chat goes at once.
- The cross on an uploading or failed photo or file cancels it and removes
  the message: the upload stops, the API is told the upload failed if a
  ticket was issued, and the queued record, the stored content and the sealed
  blob are deleted. There is no dialog: nothing was sent. A cancel wins over a
  send or a retry already under way.

## App lock

A picker, the save screen and, on iOS, Quick Look run inside
`SystemSheetGrace` (`app/system_sheet_grace.dart`). On iOS they are presented
inside the app, so only the scene really going to the background locks it,
and the lock closes them. On Android they are other apps' screens: the app
stays unlocked while one is up, and the next return locks when the sheet
opened more than 3 minutes before. Opening a file in another app on Android
gets no grace, so Veil locks as soon as it is hidden, and the file opens in
that app's own task. [mobile-device-security.md](mobile-device-security.md)
has the details.

## Backend guarantees

- object storage receives encrypted blobs only
- API stores metadata only
- plaintext file contents never touch backend business logic
- plaintext file keys never reach the server; they travel only inside the E2E payload
- upload/download URLs are short-lived and policy-scoped
- failed or explicitly canceled uploads are marked failed and object cleanup is attempted

## Private beta relay policy

- allowed MIME types are restricted to:
  - `image/jpeg`
  - `image/png`
  - `image/webp`
  - `application/pdf`
  - `application/octet-stream`
- both clients ask for `application/octet-stream`, and the server stores every blob as that type
- max attachment size is controlled by relay configuration
- filenames are not sent to the backend or object storage metadata
- the phone only uploads to and downloads from the hosts in `VEIL_OBJECT_STORAGE_HOSTS`, and a release build only over TLS

## Limitations

The upload and download pipeline is hardened for the private beta, but the
cryptography has not been audited yet. Production still needs that audit, a
storage policy review and provider-specific hardening. Uploads run while the
app is open and resume when it comes back; there is no background upload.
