import { test, expect } from './fixtures/home-assistant.js';

// Seed for Playwright Test Agents: all /api/** and /ws/** traffic is mocked by
// the `ha` fixture, so exploring from here never touches real smart home devices.
test.describe('Test group', () => {
  test('seed', async ({ page, ha }) => {
    await page.goto('/devices');
    await expect(page.getByRole('heading', { name: 'Smart Home' })).toBeVisible();
  });
});
