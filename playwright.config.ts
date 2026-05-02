import { defineConfig, devices } from '@playwright/test';

// VEIL Playwright config. Tests assume the API + web demo are reachable
// at VEIL_E2E_BASE_URL (default http://127.0.0.1:3000). Boot order:
//   pnpm demo:up          # postgres + redis + minio + api + /demo/
//   pnpm e2e:web          # this config picks up the demo
// CI runs both in sequence via .github/workflows/ci.yml.

const BASE_URL = process.env.VEIL_E2E_BASE_URL ?? 'http://127.0.0.1:3000';

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
    baseURL: `${BASE_URL}/demo/`,
    trace: 'retain-on-failure',
    video: 'retain-on-failure',
    screenshot: 'only-on-failure',
    // The demo loads its own JS + WebCrypto. Real Chromium is the only
    // engine that will exercise the production-grade path.
    actionTimeout: 10_000,
    navigationTimeout: 15_000,
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],
});
