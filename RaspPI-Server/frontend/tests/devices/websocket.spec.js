// @ts-check
// spec: specs/devices.md
// seed: tests/seed.spec.ts
import { test, expect, stateChanged, deviceCard, DEFAULT_DEVICES } from '../fixtures/home-assistant.js';

const toasts = page => page.getByRole('region', { name: 'Notifications' });
const anyToast = page => toasts(page).locator('[data-slot="toast"]');

test.describe('WebSocket state updates', () => {
  test.beforeEach(async ({ page, ha }) => {
    // Gated tests configure their own snapshot and navigate themselves.
    if (test.info().title.startsWith('5.8') || test.info().title.startsWith('5.9')) return;
    await page.goto('/devices');
    await expect(page.getByText('1 of 3 active')).toBeVisible();
  });

  test('5.1 State change turns a light on', async ({ page, ha }) => {
    // 1. ha.push(stateChanged('light.bedroom_ceiling','on'))
    await ha.push(stateChanged('light.bedroom_ceiling', 'on'));

    await expect(deviceCard(page, 'Bedroom Ceiling').getByRole('switch')).toBeChecked();
    await expect(page.getByText('2 of 3 active')).toBeVisible();
    await expect(page.getByRole('progressbar')).toHaveAttribute('aria-valuenow', /^66\.6|^66\.7/);
  });

  test('5.2 State change turns a light off', async ({ page, ha }) => {
    // 1. ha.push(stateChanged('light.living_room_lamp','off'))
    await ha.push(stateChanged('light.living_room_lamp', 'off'));

    await expect(deviceCard(page, 'Living Room Lamp').getByRole('switch')).not.toBeChecked();
    await expect(page.getByText('0 of 3 active')).toBeVisible();
    await expect(page.getByRole('progressbar')).toHaveAttribute('aria-valuenow', '0');
  });

  test('5.3 New light entity is added', async ({ page, ha }) => {
    // 1. Push stateChanged('light.kitchen','on',{friendly_name:'Kitchen Pendant'})
    await ha.push(stateChanged('light.kitchen', 'on', { friendly_name: 'Kitchen Pendant' }));

    await expect(page.getByText('Kitchen Pendant · Unassigned')).toBeVisible();
    await expect(deviceCard(page, 'Kitchen Pendant').getByRole('switch')).toBeChecked();
    await expect(page.getByText('2 of 4 active')).toBeVisible();
  });

  test('5.4 friendly_name update renames and preserves area', async ({ page, ha }) => {
    // 1. Push light.bedroom_ceiling off with friendly_name 'Master Light'
    await ha.push(stateChanged('light.bedroom_ceiling', 'off', { friendly_name: 'Master Light' }));

    await expect(page.getByText('Master Light · Bedroom')).toBeVisible();
    await expect(page.getByText('Bedroom Ceiling')).toHaveCount(0);
    await expect(page.locator('[data-slot="card"]')).toHaveCount(3);
  });

  test('5.5 Entity removal', async ({ page, ha }) => {
    // 1. Push stateChanged('light.living_room_lamp', null)
    await ha.push(stateChanged('light.living_room_lamp', null));

    await expect(deviceCard(page, 'Living Room Lamp')).toHaveCount(0);
    await expect(page.getByText('0 of 2 active')).toBeVisible();
  });

  test('5.6 Non-light and malformed messages are ignored', async ({ page, ha }) => {
    // 1. Push switch.coffee_maker state change, push {} (no entity_id), push {entity_id:null}
    await ha.push(stateChanged('switch.coffee_maker', 'off'));
    await ha.push({});
    await ha.push({ entity_id: null });
    // Sentinel: once this later message is rendered, earlier ones have been processed
    await ha.push(stateChanged('light.bedroom_ceiling', 'on'));
    await expect(page.getByText('2 of 3 active')).toBeVisible();
    await ha.push(stateChanged('light.bedroom_ceiling', 'off'));

    await expect(page.getByText('1 of 3 active')).toBeVisible();
    await expect(page.locator('[data-slot="card"]')).toHaveCount(3);
    await expect(anyToast(page)).toHaveCount(0);
  });

  // Expected to fail: socket.onmessage calls JSON.parse without try/catch, so 'not json' throws an uncaught error.
  test('5.7 [DEFECT] Invalid JSON message does not break the page', async ({ page, ha }) => {
    const errors = [];
    page.on('pageerror', e => errors.push(e));

    // 1. ha.push('not json'); then push a valid change for Bedroom Ceiling
    await ha.push('not json');
    await ha.push(stateChanged('light.bedroom_ceiling', 'on'));

    await expect(deviceCard(page, 'Bedroom Ceiling').getByRole('switch')).toBeChecked();
    await expect(page.getByText('2 of 3 active')).toBeVisible();
    expect(errors).toEqual([]);
  });

  test('5.8 WS update racing the snapshot wins', async ({ page, ha }) => {
    let release;
    const gate = new Promise(resolve => { release = resolve; });
    ha.devicesResponse = async () => {
      await gate;
      return structuredClone(DEFAULT_DEVICES); // snapshot says bedroom is off
    };

    // 1. Gate snapshot; goto; wait for socket; push bedroom -> on; release gate
    await page.goto('/devices');
    await expect.poll(() => ha.devicesRequestCount).toBe(1);
    await ha.push(stateChanged('light.bedroom_ceiling', 'on'));
    await expect(page.getByRole('switch')).toHaveCount(1);
    release();

    await expect(page.getByText('2 of 3 active')).toBeVisible();
    const bedroom = page.locator('[data-slot="card"]').filter({ hasText: /Bedroom Ceiling|light\.bedroom_ceiling/ });
    await expect(bedroom.getByRole('switch')).toBeChecked();
  });

  test('5.9 Entity removed by WS during snapshot is not resurrected', async ({ page, ha }) => {
    let release;
    const gate = new Promise(resolve => { release = resolve; });
    ha.devicesResponse = async () => {
      await gate;
      return structuredClone(DEFAULT_DEVICES); // snapshot still contains the lamp
    };

    // 1. Gate snapshot; push null state for Living Room Lamp; release snapshot
    await page.goto('/devices');
    await expect.poll(() => ha.devicesRequestCount).toBe(1);
    await ha.push(stateChanged('light.living_room_lamp', null));
    release();

    await expect(deviceCard(page, 'Bedroom Ceiling')).toBeVisible();
    await expect(deviceCard(page, 'Living Room Lamp')).toHaveCount(0);
    await expect(page.getByText('0 of 2 active')).toBeVisible();
  });

  test('5.10 Reconnects and refetches after socket drops', async ({ page, ha }) => {
    // 1. Load page; record counts; change snapshot; drop connections
    // Counts are cumulative and React StrictMode (dev) mounts the effect twice, so use baselines.
    const baseConnections = ha.connectionCount;
    const baseRequests = ha.devicesRequestCount;
    expect(baseRequests).toBeGreaterThanOrEqual(1);

    ha.devicesResponse = DEFAULT_DEVICES.map(d =>
      d.entity_id === 'light.bedroom_ceiling' ? { ...d, state: 'on' } : d,
    );
    await ha.dropConnections();

    await expect.poll(() => ha.connectionCount, { timeout: 8000 }).toBe(baseConnections + 1);
    await expect.poll(() => ha.devicesRequestCount, { timeout: 8000 }).toBe(baseRequests + 1);

    await expect(deviceCard(page, 'Bedroom Ceiling').getByRole('switch')).toBeChecked();
    await expect(page.getByText('2 of 3 active')).toBeVisible();

    // Pushes work on the new socket
    await ha.push(stateChanged('light.porch', 'on'));
    await expect(page.getByText('3 of 3 active')).toBeVisible();
  });

  // Expected to fail: useDeviceWebsockets only reconnects silently on close; no toast informs the user.
  test('5.11 Dropped connection informs the user', async ({ page, ha }) => {
    // 1. await ha.dropConnections()
    const baseConnections = ha.connectionCount;
    await ha.dropConnections();

    await expect(anyToast(page).first()).toBeVisible({ timeout: 5000 });

    // No repeated toast flood across a reconnect
    await expect.poll(() => ha.connectionCount, { timeout: 8000 }).toBe(baseConnections + 1);
    expect(await anyToast(page).count()).toBeLessThanOrEqual(2);
  });

  test('5.12 No reconnect after leaving the page', async ({ page, ha }) => {
    // The home page calls other endpoints; give them harmless mocked responses.
    await page.route('**/api/weather', route => route.fulfill({ json: { temperature: 20, temperature_unit: 'C', description: 'Clear', high: 22, low: 12, humidity: 40 } }));
    await page.route('**/api/location', route => route.fulfill({ json: { city: 'Testville', state: 'TS' } }));
    await page.route('**/api/mail*', route => route.fulfill({ json: { mail: [] } }));
    await page.route('**/api/tasks', route => route.fulfill({ json: { data: { tasks: [] } } }));
    const errors = [];
    page.on('pageerror', e => errors.push(e));

    // 1. Click nav 'Home' (unmount Devices); wait > 3.5s
    // StrictMode (dev) double-mounts the effect, so compare against the post-load baseline.
    const baseConnections = ha.connectionCount;
    // Leave for a page that does not itself use useDeviceWebsockets (Home does, and would open its own /ws/devices socket).
    await page.getByRole('link', { name: 'Life' }).click();
    await expect(page).toHaveURL(/\/life$/);
    await expect(page.getByRole('heading', { name: 'Smart Home' })).toHaveCount(0);
    // Deliberate wait: the reconnect delay is 3s, so confirm nothing reconnects after it.
    await page.waitForTimeout(3500);

    expect(ha.connectionCount).toBe(baseConnections);
    expect(errors).toEqual([]);
  });

  test('5.13 Attributes merge on update', async ({ page, ha }) => {
    // 1. Push living_room_lamp on with attributes {color_temp:300}
    await ha.push(stateChanged('light.living_room_lamp', 'on', { color_temp: 300 }));

    await expect(page.getByText('Living Room Lamp · Living Room')).toBeVisible();
    await expect(deviceCard(page, 'Living Room Lamp').getByRole('switch')).toBeChecked();
    await expect(page.getByText('1 of 3 active')).toBeVisible();
  });
});
