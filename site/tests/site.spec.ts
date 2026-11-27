import { expect, test } from '@playwright/test';

test('home renders without errors and links to the release', async ({ page }) => {
  const errors: string[] = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto('/');
  await expect(page).toHaveTitle(/Pulse/);
  const dmg = page.locator('#download a[href$=".dmg"]');
  await expect(dmg).toHaveAttribute('href', /releases\/download\/v\d+\.\d+\.\d+\/Pulse-\d+\.\d+\.\d+\.dmg$/);
  await expect(page.locator('#download a[href$=".deb"]')).toHaveAttribute('href', /pulse-monitor_\d+\.\d+\.\d+_all\.deb$/);
  expect(errors).toEqual([]);
});

test('the story folds the hero and switches tabs on scroll', async ({ page, isMobile }) => {
  test.skip(isMobile, 'phones get the still hero');
  await page.goto('/');
  const h2 = page.locator('[data-k="h2"]');
  await expect(h2).toHaveCSS('opacity', '0');
  await page.locator('[data-k="tab1"]').evaluate(() => {
    const s = document.querySelector<HTMLElement>('[data-story]')!;
    window.scrollTo(0, s.offsetTop + parseFloat(getComputedStyle(s).getPropertyValue('--story-px')) * 0.95);
  });
  await expect(h2).toHaveCSS('opacity', '1');
  await expect(page.locator('[data-k="tab1"]')).not.toHaveClass(/off/);
  await expect(page.locator('[data-k="tab0"]')).toHaveClass(/off/);
});

test('phones see the still hero', async ({ page, isMobile }) => {
  test.skip(!isMobile, 'desktop has the story');
  await page.goto('/');
  await expect(page.locator('.phone-hero h1')).toBeVisible();
  await expect(page.locator('[data-stage]')).toBeHidden();
});

test('live tour: panel, logs and the Linux window respond to clicks', async ({ page }) => {
  await page.goto('/tour/?os=mac');
  await expect(page.locator('.panel')).toBeVisible();
  await page.locator('[data-c="4"]').click();
  await expect(page.locator('.logs pre')).toContainText('Jellyfin');
  await page.locator('.logs [data-close]').first().click();
  await page.locator('[data-item]').click({ button: 'right' });
  await page.getByRole('menuitem', { name: /Settings/ }).click();
  await expect(page.locator('.settings')).toBeVisible();
  await page.goto('/tour/?os=linux');
  await expect(page.locator('.adw')).toBeVisible();
  await page.locator('[data-page="sites"]').click();
  await expect(page.locator('[data-p="sites"]')).toContainText('perde-keys');
});
