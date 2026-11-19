// @ts-check
// spec: specs/devices.md
// seed: tests/seed.spec.ts
import { test, expect, stateChanged, deviceCard, DEFAULT_DEVICES } from '../fixtures/home-assistant.js';

const toasts = page => page.getByRole('region', { name: 'Notifications' });

test.describe('Unavailable devices', () => {
  test('3.1 Toggling an unavailable light is blocked', async ({ page, ha }) => {
    await page.goto('/devices');
    await expect(page.getByText('1 of 3 active')).toBeVisible();
    const sw = deviceCard(page, 'Porch Light').getByRole('switch');

    // 1. Click Porch Light switch
    await sw.click();

    await expect(toasts(page).getByText('Porch Light is unavailable.')).toBeVisible();
    expect(ha.commands).toEqual([]);
    await expect(sw).not.toBeChecked();
  });

  test('3.2 Toggling an unknown-state light is blocked', async ({ page, ha }) => {
    // 1. Snapshot light with state 'unknown'; click it
    ha.devicesResponse = [
      { entity_id: 'light.hall', name: 'Hall Light', area: 'Hall', state: 'unknown', attributes: {} },
    ];
    await page.goto('/devices');
    const sw = deviceCard(page, 'Hall Light').getByRole('switch');
    await sw.click();

    await expect(toasts(page).getByText('Hall Light is unavailable.')).toBeVisible();
    expect(ha.commands).toEqual([]);
  });

  test('3.3 Device becoming unavailable via WS blocks commands', async ({ page, ha }) => {
    await page.goto('/devices');
    await expect(page.getByText('1 of 3 active')).toBeVisible();
    const sw = deviceCard(page, 'Bedroom Ceiling').getByRole('switch');

    // 1. ha.push(stateChanged('light.bedroom_ceiling','unavailable')); click its switch
    await ha.push(stateChanged('light.bedroom_ceiling', 'unavailable'));
    await sw.click();

    await expect(toasts(page).getByText('Bedroom Ceiling is unavailable.')).toBeVisible();
    expect(ha.commands).toEqual([]);
    await expect(sw).not.toBeChecked();
    await expect(page.getByText('1 of 3 active')).toBeVisible();
  });

  test('3.4 Device recovering via WS can be toggled', async ({ page, ha }) => {
    await page.goto('/devices');
    await expect(page.getByText('1 of 3 active')).toBeVisible();

    // 1. ha.push(stateChanged('light.porch','off')); click Porch switch
    await ha.push(stateChanged('light.porch', 'off'));
    await deviceCard(page, 'Porch Light').getByRole('switch').click();

    await expect.poll(() => ha.commands).toEqual([
      { entity_id: 'light.porch', domain: 'light', action: 'turn_on', data: {} },
    ]);
    await expect(toasts(page).getByText('Porch Light is on.')).toBeVisible();
  });

  test('3.5 Unavailable lights are not counted active', async ({ page, ha }) => {
    await page.goto('/devices');
    await expect(page.getByText('1 of 3 active')).toBeVisible();

    // 1. Push Living Room Lamp -> unavailable
    await ha.push(stateChanged('light.living_room_lamp', 'unavailable'));

    await expect(page.getByText('0 of 3 active')).toBeVisible();
    await expect(deviceCard(page, 'Living Room Lamp').getByRole('switch')).not.toBeChecked();
  });

  // Expected to fail: useToggleDevice uses device.name, which is undefined for snapshot devices without a name,
  // so the toast reads "undefined is unavailable." instead of using the card's fallback label.
  test('3.6 [DEFECT] Unavailable toast for snapshot device without name', async ({ page, ha }) => {
    // 1. Snapshot {entity_id:'light.nameless', state:'unavailable'} (no name); click it
    ha.devicesResponse = [{ entity_id: 'light.nameless', state: 'unavailable' }];
    await page.goto('/devices');
    await page.getByRole('switch').click();

    const region = toasts(page);
    await expect(region.getByText(/unavailable/)).toBeVisible();
    await expect(region).not.toContainText('undefined');
    expect(ha.commands).toEqual([]);
  });
});
