# Web demo Playwright e2e

Real-browser end-to-end tests for the VEIL web demo, in two Playwright
projects (see `playwright.config.ts` at the repo root).

## browser-unit: protocol v2 against an in-memory relay

`browser/protocol-v2.spec.ts` runs the demo in Chrome against
`mock-server.mjs`, a stand-in for the API that serves `/demo/` and an
in-memory `/v1` relay (auth, key directory, prekeys, conversations,
messages, attachments). It relays ciphertext and never decrypts; it has no
realtime gateway (`/socket.io` and `/v1/realtime` answer 404), so the demo
runs in polling mode. Playwright starts it; nothing else is needed.

- Alice and Bob exchange 10 messages while the relay hands each recipient
  the held messages one at a time in random order.
- A reload restores both histories from the encrypted local store with no
  ratchet work at all, while the relay serves corrupted ciphertext.
- A relay that swaps Bob's identity and opens a session to Alice as Bob's
  device is refused: Alice sees the key-change banner and cannot send.

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
mode, then `pnpm e2e:web` executes both projects.

## Caveats

- Voice messages are NOT exercised. MediaRecorder requires user-gesture
  + microphone permission which Playwright can fake but the audio
  decode path is platform-dependent. Skip until a real-device QA pass.
- Image upload is also NOT exercised. The drag-and-drop preview gate
  needs a real File object handle from the OS; we cover the encrypt /
  upload path in unit tests instead (Phase AO).
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
