// @ts-check
// spec: specs/devices.md
// seed: tests/seed.spec.ts
import { test, expect, stateChanged, deviceCard, DEFAULT_DEVICES } from '../fixtures/home-assistant.js';

test.describe('Device rendering', () => {
  test('1.1 Renders only light entities with name and area', async ({ page, ha }) => {
    // 1. Default mocks; goto /devices
    await page.goto('/devices');

    await expect(page.getByText('Living Room Lamp · Living Room')).toBeVisible();
    await expect(page.getByText('Bedroom Ceiling · Bedroom')).toBeVisible();
    await expect(page.getByText('Porch Light · Outside')).toBeVisible();
    await expect(page.getByText('Coffee Maker')).toHaveCount(0);
    await expect(page.getByText('Temperature')).toHaveCount(0);
    await expect(page.getByRole('switch')).toHaveCount(3);
  });

  test('1.2 Active count and progress count lights only', async ({ page, ha }) => {
    // 1. Default mocks; goto /devices
    await page.goto('/devices');

    // switch.coffee_maker is on but is not a light, so it is not counted
    await expect(page.getByText('1 of 3 active')).toBeVisible();
    await expect(page.getByRole('progressbar')).toHaveAttribute('aria-valuenow', /^33\.3/);
  });

  test('1.3 Switch state reflects device state', async ({ page, ha }) => {
    // 1. Default mocks; inspect switches per card
    await page.goto('/devices');

    await expect(deviceCard(page, 'Living Room Lamp').getByRole('switch')).toBeChecked();
    await expect(deviceCard(page, 'Bedroom Ceiling').getByRole('switch')).not.toBeChecked();
    await expect(deviceCard(page, 'Porch Light').getByRole('switch')).not.toBeChecked();
  });

  test('1.4 Fallbacks for missing name and area', async ({ page, ha }) => {
    // 1. ha.devicesResponse = [{entity_id:'light.x', state:'off', area:null, attributes:{}}]; goto
    ha.devicesResponse = [{ entity_id: 'light.x', state: 'off', area: null, attributes: {} }];
    await page.goto('/devices');

    const card = page.locator('[data-slot="card"]');
    await expect(card).toHaveCount(1);
    await expect(card).toHaveText(/Unknown Device · Unassigned|light\.x/);
    await expect(card).not.toContainText('undefined');
    await expect(card).not.toContainText('null');
  });

  test('1.5 Empty device list', async ({ page, ha }) => {
    // 1. ha.devicesResponse = []; goto
    ha.devicesResponse = [];
    await page.goto('/devices');

    await expect(page.getByText('0 of 0 active')).toBeVisible();
    await expect(page.getByRole('switch')).toHaveCount(0);
    await expect(page.getByRole('progressbar')).toHaveAttribute('aria-valuenow', '0');
    await expect(page.locator('body')).not.toContainText('NaN');
  });

  test('1.6 Only non-light entities', async ({ page, ha }) => {
    // 1. ha.devicesResponse = [switch.coffee_maker, sensor.temperature]
    ha.devicesResponse = DEFAULT_DEVICES.filter(d => !d.entity_id.startsWith('light.'));
    await page.goto('/devices');

    await expect(page.getByText('0 of 0 active')).toBeVisible();
    await expect(page.locator('[data-slot="card"]')).toHaveCount(0);
  });

  test('1.7 Reachable from navigation bar', async ({ page, ha }) => {
    // The home page calls other endpoints; give them harmless mocked responses.
    await page.route('**/api/weather', route => route.fulfill({ json: { temperature: 20, temperature_unit: 'C', description: 'Clear', high: 22, low: 12, humidity: 40 } }));
    await page.route('**/api/location', route => route.fulfill({ json: { city: 'Testville', state: 'TS' } }));
    await page.route('**/api/mail*', route => route.fulfill({ json: { mail: [] } }));
    await page.route('**/api/tasks', route => route.fulfill({ json: { data: { tasks: [] } } }));

    // 1. goto /; click navigation link 'Devices'
    await page.goto('/');
    await page.getByRole('link', { name: 'Devices' }).click();

    await expect(page).toHaveURL(/\/devices$/);
    await expect(page.getByRole('heading', { name: 'Smart Home' })).toBeVisible();
    await expect(page.getByText('Living Room Lamp · Living Room')).toBeVisible();
  });

  test('1.8 Many devices layout', async ({ page, ha }) => {
    // 1. ha.devicesResponse with 12 lights of which 4 on; goto
    ha.devicesResponse = Array.from({ length: 12 }, (_, i) => ({
      entity_id: `light.light_${i + 1}`,
      name: i === 0 ? 'An Extremely Long Light Name For Layout Testing Purposes' : `Light ${i + 1}`,
      area: i === 0 ? 'A Very Long Area Name Used For Layout Testing' : `Room ${i + 1}`,
      state: i < 4 ? 'on' : 'off',
      attributes: {},
    }));
    await page.goto('/devices');

    await expect(page.locator('[data-slot="card"]')).toHaveCount(12);
    await expect(page.getByText('4 of 12 active')).toBeVisible();
    await expect(page.getByRole('progressbar')).toHaveAttribute('aria-valuenow', /^33\.3/);
    await expect(
      page.getByText('An Extremely Long Light Name For Layout Testing Purposes · A Very Long Area Name Used For Layout Testing'),
    ).toBeVisible();

    // The long text must stay inside its card horizontally
    const card = deviceCard(page, 'An Extremely Long Light Name For Layout Testing Purposes');
    const cardBox = await card.boundingBox();
    const textBox = await card.locator('p').boundingBox();
    expect(cardBox).not.toBeNull();
    expect(textBox).not.toBeNull();
    expect(textBox.x + textBox.width).toBeLessThanOrEqual(cardBox.x + cardBox.width + 1);
  });
});
