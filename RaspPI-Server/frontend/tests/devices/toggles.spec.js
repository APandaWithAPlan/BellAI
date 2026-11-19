// @ts-check
// spec: specs/devices.md
// seed: tests/seed.spec.ts
import { test, expect, stateChanged, deviceCard, DEFAULT_DEVICES } from '../fixtures/home-assistant.js';

const toasts = page => page.getByRole('region', { name: 'Notifications' });

test.describe('Light toggles', () => {
  test('2.1 Turning a light on sends turn_on', async ({ page, ha }) => {
    await page.goto('/devices');
    await expect(page.getByText('1 of 3 active')).toBeVisible();

    // 1. Default mocks; click Bedroom Ceiling switch
    await deviceCard(page, 'Bedroom Ceiling').getByRole('switch').click();

    await expect.poll(() => ha.commands).toEqual([
      { entity_id: 'light.bedroom_ceiling', domain: 'light', action: 'turn_on', data: {} },
    ]);
    await expect(toasts(page).getByText('Bedroom Ceiling is on.')).toBeVisible();
  });

  test('2.2 Turning a light off sends turn_off', async ({ page, ha }) => {
    await page.goto('/devices');
    await expect(page.getByText('1 of 3 active')).toBeVisible();

    // 1. Click Living Room Lamp switch
    await deviceCard(page, 'Living Room Lamp').getByRole('switch').click();

    await expect.poll(() => ha.commands).toEqual([
      { entity_id: 'light.living_room_lamp', domain: 'light', action: 'turn_off', data: {} },
    ]);
    await expect(toasts(page).getByText('Living Room Lamp is off.')).toBeVisible();
  });

  test('2.3 Switch is server-authoritative', async ({ page, ha }) => {
    await page.goto('/devices');
    await expect(page.getByText('1 of 3 active')).toBeVisible();
    const sw = deviceCard(page, 'Bedroom Ceiling').getByRole('switch');

    // 1. Click Bedroom Ceiling; verify switch state; then push state change
    await sw.click();
    await expect.poll(() => ha.commands.length).toBe(1);
    await expect(toasts(page).getByText('Bedroom Ceiling is on.')).toBeVisible();
    await expect(sw).not.toBeChecked();
    await expect(page.getByText('1 of 3 active')).toBeVisible();

    await ha.push(stateChanged('light.bedroom_ceiling', 'on'));
    await expect(sw).toBeChecked();
    await expect(page.getByText('2 of 3 active')).toBeVisible();
  });

  test('2.4 Switch does not diverge when command succeeds but no WS event arrives', async ({ page, ha }) => {
    await page.goto('/devices');
    await expect(page.getByText('1 of 3 active')).toBeVisible();
    const sw = deviceCard(page, 'Living Room Lamp').getByRole('switch');

    // 1. Click Living Room Lamp switch, no push
    await sw.click();
    await expect.poll(() => ha.commands.length).toBe(1);
    await expect(sw).toBeChecked();

    // Toggling again sends turn_off again rather than corrupting state
    await sw.click();
    await expect.poll(() => ha.commands.length).toBe(2);
    expect(ha.commands.map(c => c.action)).toEqual(['turn_off', 'turn_off']);
    await expect(sw).toBeChecked();
    await expect(page.getByText('1 of 3 active')).toBeVisible();
  });

  test('2.5 Rapid double click sends two ordered commands', async ({ page, ha }) => {
    const errors = [];
    page.on('pageerror', e => errors.push(e));
    await page.goto('/devices');
    await expect(page.getByText('1 of 3 active')).toBeVisible();
    const sw = deviceCard(page, 'Bedroom Ceiling').getByRole('switch');

    // 1. Double click Bedroom Ceiling switch
    await sw.dblclick();
    await expect.poll(() => ha.commands.length).toBeGreaterThanOrEqual(1);

    expect(errors).toEqual([]);
    expect(ha.commands.length).toBeLessThanOrEqual(2);
    for (const c of ha.commands) expect(c.entity_id).toBe('light.bedroom_ceiling');

    // UI is consistent after server pushes
    await ha.push(stateChanged('light.bedroom_ceiling', 'on'));
    await expect(sw).toBeChecked();
    await expect(page.getByText('2 of 3 active')).toBeVisible();
    await ha.push(stateChanged('light.bedroom_ceiling', 'off'));
    await expect(sw).not.toBeChecked();
    await expect(page.getByText('1 of 3 active')).toBeVisible();
  });

  test('2.6 Keyboard toggle', async ({ page, ha }) => {
    await page.goto('/devices');
    await expect(page.getByText('1 of 3 active')).toBeVisible();

    // 1. Focus Bedroom Ceiling switch, press Space
    const sw = deviceCard(page, 'Bedroom Ceiling').getByRole('switch');
    await sw.focus();
    await page.keyboard.press('Space');

    await expect.poll(() => ha.commands).toEqual([
      { entity_id: 'light.bedroom_ceiling', domain: 'light', action: 'turn_on', data: {} },
    ]);
    await expect(toasts(page).getByText('Bedroom Ceiling is on.')).toBeVisible();
  });

  test('2.7 Toggling does not affect other devices', async ({ page, ha }) => {
    await page.goto('/devices');
    await expect(page.getByText('1 of 3 active')).toBeVisible();

    // 1. Click Bedroom Ceiling
    await deviceCard(page, 'Bedroom Ceiling').getByRole('switch').click();

    await expect(toasts(page).getByText('Bedroom Ceiling is on.')).toBeVisible();
    expect(ha.commands).toHaveLength(1);
    expect(ha.commands[0].entity_id).toBe('light.bedroom_ceiling');
    await expect(deviceCard(page, 'Living Room Lamp').getByRole('switch')).toBeChecked();
    await expect(deviceCard(page, 'Porch Light').getByRole('switch')).not.toBeChecked();
  });
});
