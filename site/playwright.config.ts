import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: 'tests',
  testIgnore: 'unit/**',
  fullyParallel: true,
  reporter: 'list',
  use: { baseURL: 'http://localhost:4330', reducedMotion: 'no-preference' },
  webServer: { command: 'npx astro preview --port 4330', port: 4330, reuseExistingServer: true },
  projects: [
    { name: 'desktop', use: { ...devices['Desktop Chrome'], channel: 'chrome', viewport: { width: 1440, height: 900 } } },
    { name: 'mobile', use: { ...devices['Pixel 7'], channel: 'chrome' } },
  ],
});
