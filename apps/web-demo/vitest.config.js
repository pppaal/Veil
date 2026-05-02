import { defineConfig } from 'vitest/config';

// Vitest scope is intentionally narrow: only the __tests__ directory.
// The Playwright e2e specs in e2e/ live in the same package but use
// @playwright/test, which is incompatible with the Vitest runner.
export default defineConfig({
  test: {
    include: ['__tests__/**/*.test.js'],
    environment: 'node',
  },
});
