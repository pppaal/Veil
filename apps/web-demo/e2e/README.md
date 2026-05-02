# Web demo Playwright e2e

Real-browser end-to-end tests for the VEIL web demo. Two-context tests
(Alice ↔ Bob) exercise the full encrypt → server → decrypt round-trip
that REST-only smoke tests cannot reach.

## Specs

- `auth.spec.ts` — fresh handle registration, invalid handle rejection
- `messaging.spec.ts` — Alice → Bob round-trip with markdown rendering
- `actions.spec.ts` — edit + delete with realtime fanout to peer
- `settings.spec.ts` — settings dialog theme toggle, Ctrl/Cmd+/ help

## Run locally

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
mode, then `pnpm e2e:web` executes.

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
const a = await registerAndOpen(browser, 'Alice', `a${stamp}`);
const b = await registerAndOpen(browser, 'Bob', `b${stamp}`);
// …
await a.context.close();
await b.context.close();
```

Always close both contexts at the end so the next test gets clean
storage.
