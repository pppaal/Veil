# Web demo Playwright e2e

Real-browser end-to-end tests for the VEIL web demo, in three Playwright
projects (see `playwright.config.ts` at the repo root).

## The in-memory relay

`mock-server.mjs` is a stand-in for the API that serves `/demo/` and an
in-memory `/v1` relay (auth, key directory, prekeys, conversations,
messages, receipts, attachments, reports, device transfer, one-time secret
links). It relays ciphertext and never decrypts. Its realtime gateway
(`mock-realtime.mjs`, Socket.IO over a WebSocket) is off until a test turns
it on with `POST /__test/realtime`, so by default `/v1/realtime` refuses
the upgrade and the demo runs in polling mode. Playwright starts it;
nothing else is needed. It refuses what the real API refuses on the routes
the demo uses, with the same status and error code (request bodies as the
API's DTOs, a signed prekey as `KeysService` checks it, a device transfer
as `DeviceTransferService` runs it, its signed approval and the identical
completion retry it answers included); `__tests__/mock-relay.test.js` pins
those refusals.

## characterization: the whole app through its UI

`characterization/*.spec.ts` drive the real app (`index.html` + `app.js`)
in two or more browser contexts against the relay, and assert that no app
error reaches the console: signing up and back in, a rejected session,
wipe, settings and the ko/en switch (`session`), a direct chat with text,
replies, reactions, edits, deletes with undo, search, forwarding, tabs,
read receipts, history paging and local history deletion (`messaging`),
pushes, read receipts and typing with the realtime gateway on
(`realtime`), image and file round trips (`attachments`), safety numbers
and identity changes accepted and declined (`trust`), device transfer onto
a browser that holds another identity, through a lost completion answer
and a refused completion (`transfer`), one-time secret links
(`secret-link`) and the KakaoTalk import (`kakao-import`). They were
written against the monolithic `app.js` and passed there before it was
split (docs/web-architecture.md), so they pin what the split had to keep.

```bash
CHROME_PATH=/usr/bin/google-chrome npx playwright test --project=characterization
```

## browser-unit: protocol v2 against the relay

`browser/protocol-v2.spec.ts` runs the demo in Chrome against the relay in
polling mode:

- Alice and Bob exchange 10 messages while the relay hands each recipient
  the held messages one at a time in random order.
- A reload restores both histories from the encrypted local store with no
  ratchet work at all, while the relay serves corrupted ciphertext.
- Both devices' safety-number dialogs, each computed from the identity its
  session runs on, show the same number.
- A relay that swaps Bob's identity and opens a session to Alice as Bob's
  device is refused: Alice sees the key-change banner and cannot send.
  Once she declines that key, she sends to Bob again, and the refused frame,
  which the relay still serves, raises nothing after a reload.
- Reporting one of Bob's messages sends only the reason picked and the
  message, conversation and reported user ids, in the shape the API takes.
- A device that was away while 260 messages and reactions arrived (more
  than five pages of history) gets all of them, opened in order and none
  locked, and keeps them through later refreshes and a reload.
- A device whose own send was cached above such a backlog, while its
  history fetches failed, still pages back through the backlog after a
  reload.
- A message deleted by its sender, and one past the relay's conversation
  timer, leave both pages and the sidebar, and their rows in the
  decrypt-once store are retired on both devices, with history polling as
  the only channel and the relay still serving the expired one. A message
  sent under the timer expires on both devices even when the relay stores
  it with no expiry, by the one sealed inside it. The store also retires
  expired records nothing is showing.
- Two tabs write the shared session record in IndexedDB at once, one
  rotating prekeys and one renewing tokens, and neither reverts the other.

```bash
CHROME_PATH=/usr/bin/google-chrome npx playwright test --project=browser-unit
```

Without `CHROME_PATH` the project uses `/usr/bin/google-chrome` when it
exists and Playwright's own Chromium otherwise.

## docker: the full stack

- `auth.spec.ts` — fresh handle registration, invalid handle rejection
- `messaging.spec.ts` — Alice → Bob round-trip with markdown rendering
- `actions.spec.ts` — edit + delete with realtime fanout to peer
- `settings.spec.ts` — settings dialog theme toggle, Ctrl/Cmd+/ help

Boot the stack first, then run Playwright:

```bash
# Terminal 1 — API + Postgres + Redis + MinIO + /demo/
pnpm demo:up

# Wait for the API to come up:
curl http://127.0.0.1:3000/v1/health

# Terminal 2 — install browsers (one-time) then run tests
pnpm e2e:web:install   # downloads chromium + system deps
pnpm e2e:web           # headless, saves report to playwright-report/
pnpm e2e:web:ui        # interactive UI mode for debugging
```

## CI

The CI workflow runs the e2e suite after the API + Mobile build steps.
See `.github/workflows/ci.yml`. The runner installs chromium once via
`pnpm e2e:web:install`, then `pnpm demo:up` boots the stack in detached
mode, then `pnpm e2e:web` executes all three projects.

## Caveats

- Voice messages are NOT exercised. MediaRecorder requires user-gesture
  + microphone permission which Playwright can fake but the audio
  decode path is platform-dependent. Skip until a real-device QA pass.
- Image and file uploads run only in the characterization project,
  against the relay's blob store; the docker specs do not upload.
- Two-context tests assume the API is empty enough to let two
  registrations coexist. The CI fixture cleans state between runs by
  calling `demo:reset` before each run if you set `E2E_CLEAN=1`.

## Adding a new spec

Each spec file lives in this directory. The `playwright.config.ts` at
the repo root picks them up automatically. Pattern for a peer-required
test:

```ts
const a = await registerAndOpen(browser, `a${stamp}`);
const b = await registerAndOpen(browser, `b${stamp}`);
// …
await a.context.close();
await b.context.close();
```

Always close both contexts at the end so the next test gets clean
storage.
