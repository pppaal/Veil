import { existsSync } from 'node:fs';

import { defineConfig, devices } from '@playwright/test';

// VEIL Playwright config. Two projects:
//
// docker        the e2e specs in apps/web-demo/e2e against the full stack at
//               VEIL_E2E_BASE_URL (default http://127.0.0.1:3000). Boot order:
//                 pnpm demo:up          # postgres + redis + minio + api + /demo/
//                 pnpm e2e:web          # this config picks up the demo
//               CI runs both in sequence via .github/workflows/ci.yml.
// browser-unit  the protocol-v2 browser tests in apps/web-demo/e2e/browser
//               against the in-memory relay (apps/web-demo/e2e/mock-server.mjs),
//               which this config starts. Needs no services:
//                 CHROME_PATH=/usr/bin/google-chrome npx playwright test --project=browser-unit

const BASE_URL = process.env.VEIL_E2E_BASE_URL ?? 'http://127.0.0.1:3000';
const MOCK_PORT = Number(process.env.VEIL_MOCK_PORT ?? 4317);
const MOCK_URL = `http://127.0.0.1:${MOCK_PORT}`;
// The browser-unit tests drive a system Chrome when there is one; where
// there is none (a CI runner with only Playwright's own browsers), they fall
// back to Playwright's Chromium.
const CHROME_PATH = process.env.CHROME_PATH ?? '/usr/bin/google-chrome';

export default defineConfig({
  testDir: './apps/web-demo/e2e',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: 1,
  reporter: [['list'], ['html', { open: 'never', outputFolder: 'playwright-report' }]],
  timeout: 30_000,
  expect: { timeout: 5_000 },
  use: {
    trace: 'retain-on-failure',
    video: 'retain-on-failure',
    screenshot: 'only-on-failure',
    // The demo loads its own JS + WebCrypto. Real Chromium is the only
    // engine that will exercise the production-grade path.
    actionTimeout: 10_000,
    navigationTimeout: 15_000,
  },
  projects: [
    {
      name: 'docker',
      testIgnore: /browser\//,
      use: { ...devices['Desktop Chrome'], baseURL: `${BASE_URL}/demo/` },
    },
    {
      name: 'browser-unit',
      testMatch: /browser\/.*\.spec\.ts$/,
      timeout: 120_000,
      use: {
        ...devices['Desktop Chrome'],
        baseURL: `${MOCK_URL}/demo/`,
        launchOptions: existsSync(CHROME_PATH) ? { executablePath: CHROME_PATH } : {},
      },
    },
  ],
  webServer: {
    command: 'node apps/web-demo/e2e/mock-server.mjs',
    url: `${MOCK_URL}/__test/health`,
    env: { VEIL_MOCK_PORT: String(MOCK_PORT) },
    reuseExistingServer: !process.env.CI,
  },
});
