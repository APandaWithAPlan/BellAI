// @ts-check
// spec: specs/devices.md
// seed: tests/seed.spec.ts
import { test, expect, stateChanged, deviceCard, DEFAULT_DEVICES } from '../fixtures/home-assistant.js';

const toasts = page => page.getByRole('region', { name: 'Notifications' });
const errorToasts = page => toasts(page).locator('[data-slot="toast"][data-type="error"]');

test.describe('API errors', () => {
  test('4.1 Snapshot fetch failure shows error toast', async ({ page, ha }) => {
    // 1. ha.devicesResponse = {status:500}; goto
    ha.devicesResponse = { status: 500, body: { error: 'boom' } };
    await page.goto('/devices');

    await expect(toasts(page).getByText('Failed to fetch /api/devices.')).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Smart Home' })).toBeVisible();
    await expect(page.getByText('0 of 0 active')).toBeVisible();
    await expect(page.locator('[data-slot="card"]')).toHaveCount(0);
  });

  // Expected to fail: useDeviceCommand throws `Failed to control ${device}` with an undefined `device`
  // (ReferenceError "device is not defined"), and the success toast is still shown afterwards.
  test('4.2 [DEFECT] Command HTTP error shows meaningful error and no success toast', async ({ page, ha }) => {
    ha.commandResponse = { status: 500, body: { error: 'boom' } };
    await page.goto('/devices');
    await expect(page.getByText('1 of 3 active')).toBeVisible();
    const sw = deviceCard(page, 'Bedroom Ceiling').getByRole('switch');

    // 1. ha.commandResponse = {status:500}; click Bedroom Ceiling switch
    await sw.click();

    await expect(errorToasts(page)).toHaveCount(1);
    await expect(errorToasts(page)).toContainText('Bedroom Ceiling');
    await expect(toasts(page)).not.toContainText('device is not defined');
    await expect(toasts(page).getByText('Bedroom Ceiling is on.')).toHaveCount(0);
    await expect(sw).not.toBeChecked();
  });

  // Expected to fail: a failed command is swallowed in useDeviceCommand, so the success toast is shown anyway.
  test('4.3 [DEFECT] Command network failure shows error and no success toast', async ({ page, ha }) => {
    ha.commandResponse = 'network-error';
    await page.goto('/devices');
    await expect(page.getByText('1 of 3 active')).toBeVisible();
    const sw = deviceCard(page, 'Bedroom Ceiling').getByRole('switch');

    // 1. ha.commandResponse = 'network-error'; click Bedroom Ceiling switch
    await sw.click();

    await expect(errorToasts(page).first()).toBeVisible();
    await expect(toasts(page).getByText('Bedroom Ceiling is on.')).toHaveCount(0);
    await expect(sw).not.toBeChecked();
  });

  // Expected to fail: the error toast says "device is not defined" and a success toast "is off." is also shown.
  test('4.4 [DEFECT] Command 4xx (e.g. 400/404) shows error', async ({ page, ha }) => {
    ha.commandResponse = { status: 404, body: {} };
    await page.goto('/devices');
    await expect(page.getByText('1 of 3 active')).toBeVisible();

    // 1. ha.commandResponse = {status:404, body:{}}; click Living Room Lamp
    await deviceCard(page, 'Living Room Lamp').getByRole('switch').click();

    await expect(errorToasts(page).first()).toBeVisible();
    await expect(errorToasts(page).first()).toContainText('Living Room Lamp');
    await expect(toasts(page).getByText('Living Room Lamp is off.')).toHaveCount(0);
  });

  test('4.5 Command error toast appears once, not duplicated', async ({ page, ha }) => {
    ha.commandResponse = { status: 500, body: { error: 'boom' } };
    await page.goto('/devices');
    await expect(page.getByText('1 of 3 active')).toBeVisible();

    // 1. 500 on command; click a switch; count toasts in Notifications region
    await deviceCard(page, 'Bedroom Ceiling').getByRole('switch').click();

    await expect(errorToasts(page).first()).toBeVisible();
    expect(await errorToasts(page).count()).toBeLessThanOrEqual(1);
  });

  test('4.6 App recovers after a failed command', async ({ page, ha }) => {
    ha.commandResponse = { status: 500, body: { error: 'boom' } };
    await page.goto('/devices');
    await expect(page.getByText('1 of 3 active')).toBeVisible();
    const sw = deviceCard(page, 'Bedroom Ceiling').getByRole('switch');

    // 1. Fail first command (500), then set ha.commandResponse to 200 and click again
    await sw.click();
    await expect.poll(() => ha.commands.length).toBe(1);
    await expect(errorToasts(page).first()).toBeVisible();

    ha.commandResponse = { status: 200, body: { success: true } };
    await sw.click();

    await expect.poll(() => ha.commands.length).toBe(2);
    expect(ha.commands[1]).toEqual({ entity_id: 'light.bedroom_ceiling', domain: 'light', action: 'turn_on', data: {} });
    await expect(toasts(page).getByText('Bedroom Ceiling is on.').last()).toBeVisible();
  });

  test('4.7 Snapshot failure does not break live updates', async ({ page, ha }) => {
    // 1. ha.devicesResponse = {status:500}; goto; push a new light
    ha.devicesResponse = { status: 500, body: { error: 'boom' } };
    await page.goto('/devices');
    await expect(toasts(page).getByText('Failed to fetch /api/devices.')).toBeVisible();

    await ha.push(stateChanged('light.kitchen', 'on', { friendly_name: 'Kitchen Pendant' }));

    await expect(page.getByText('Kitchen Pendant · Unassigned')).toBeVisible();
    await expect(page.getByText('1 of 1 active')).toBeVisible();
  });

  test('4.8 Snapshot with malformed (non-array) body', async ({ page, ha }) => {
    // 1. ha.devicesResponse = async () => ({oops:true}); goto
    ha.devicesResponse = async () => ({ oops: true });
    await page.goto('/devices');

    // Page does not crash
    await expect(page.getByRole('heading', { name: 'Smart Home' })).toBeVisible();
    // An error toast or an empty state is shown
    await expect(errorToasts(page).first().or(page.getByText('0 of 0 active'))).toBeVisible();
  });
});
