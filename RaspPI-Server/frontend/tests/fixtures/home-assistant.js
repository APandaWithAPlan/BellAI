// @ts-check
/**
 * Mocked Home Assistant backend for Playwright tests.
 *
 * SAFETY: The Vite dev server proxies /api and /ws to a real Home Assistant
 * bridge. This fixture intercepts ALL /api/** requests and ALL /ws/** sockets
 * in the browser before the page loads, so no request ever reaches the proxy.
 * Unhandled API calls get a 503 and are recorded in `unhandledRequests`; the
 * WebSocket is fully mocked (connectToServer() is never called).
 */
import { test as base, expect } from '@playwright/test';

export const DEFAULT_DEVICES = [
  { entity_id: 'light.living_room_lamp', name: 'Living Room Lamp', area: 'Living Room', state: 'on', attributes: { brightness: 255 } },
  { entity_id: 'light.bedroom_ceiling', name: 'Bedroom Ceiling', area: 'Bedroom', state: 'off', attributes: {} },
  { entity_id: 'light.porch', name: 'Porch Light', area: 'Outside', state: 'unavailable', attributes: {} },
  { entity_id: 'switch.coffee_maker', name: 'Coffee Maker', area: 'Kitchen', state: 'on', attributes: {} },
  { entity_id: 'sensor.temperature', name: 'Temperature', area: 'Living Room', state: '21.5', attributes: {} },
];

/**
 * Builds a Home Assistant style state_changed event as forwarded by /ws/devices.
 * @param {string} entityId
 * @param {string | null} state  null => entity removed
 * @param {Record<string, unknown>} [attributes]
 */
export function stateChanged(entityId, state, attributes = {}) {
  return {
    entity_id: entityId,
    new_state: state === null ? null : { entity_id: entityId, state, attributes },
  };
}

class HomeAssistantMock {
  constructor() {
    /** @type {any[] | { status: number, body?: any } | (() => Promise<any>)} */
    this.devicesResponse = structuredClone(DEFAULT_DEVICES);
    /** @type {{ status: number, body: any } | 'network-error'} */
    this.commandResponse = { status: 200, body: { success: true } };
    /** @type {any[]} */
    this.commands = [];
    /** @type {string[]} */
    this.unhandledRequests = [];
    this.devicesRequestCount = 0;
    /** @type {import('@playwright/test').WebSocketRoute[]} */
    this.sockets = [];
    this.connectionCount = 0;
  }

  /** @param {import('@playwright/test').Page} page */
  async install(page) {
    // Catch-all first: Playwright matches the most recently registered route first.
    await page.route('**/api/**', async route => {
      this.unhandledRequests.push(`${route.request().method()} ${route.request().url()}`);
      await route.fulfill({ status: 503, json: { error: 'unmocked endpoint' } });
    });

    await page.route('**/api/devices', async route => {
      this.devicesRequestCount += 1;
      const resp = this.devicesResponse;
      if (typeof resp === 'function') {
        await route.fulfill({ status: 200, json: await resp() });
      } else if (Array.isArray(resp)) {
        await route.fulfill({ status: 200, json: resp });
      } else {
        await route.fulfill({ status: resp.status, json: resp.body ?? { error: 'error' } });
      }
    });

    await page.route('**/api/device/command', async route => {
      this.commands.push(route.request().postDataJSON());
      const resp = this.commandResponse;
      if (resp === 'network-error') {
        await route.abort('failed');
      } else {
        await route.fulfill({ status: resp.status, json: resp.body });
      }
    });

    await page.routeWebSocket('**/ws/**', ws => {
      // Other pages (e.g. the /ws/chat socket on Home) are mocked too but must not
      // be counted as, or receive pushes meant for, the /ws/devices socket.
      if (!new URL(ws.url()).pathname.startsWith('/ws/devices')) return;
      this.connectionCount += 1;
      this.sockets.push(ws);
      ws.onClose(() => {
        this.sockets = this.sockets.filter(s => s !== ws);
      });
      // Never call ws.connectToServer(): the socket is fully mocked.
    });
  }

  /** Sends a message to every currently open device socket. */
  async push(message) {
    await expect.poll(() => this.sockets.length, { message: 'no open /ws/devices socket' }).toBeGreaterThan(0);
    for (const ws of this.sockets) {
      ws.send(typeof message === 'string' ? message : JSON.stringify(message));
    }
  }

  /** Server-side close of all open sockets (simulates Home Assistant bridge dropping). */
  async dropConnections() {
    for (const ws of [...this.sockets]) {
      await ws.close();
    }
  }
}

/**
 * @type {import('@playwright/test').TestType<
 *   import('@playwright/test').PlaywrightTestArgs & import('@playwright/test').PlaywrightTestOptions & { ha: HomeAssistantMock },
 *   import('@playwright/test').PlaywrightWorkerArgs & import('@playwright/test').PlaywrightWorkerOptions>}
 */
export const test = base.extend({
  ha: async ({ page }, use) => {
    const mock = new HomeAssistantMock();
    await mock.install(page);
    await use(mock);
    // Every test must stay within the mocked surface.
    expect(mock.unhandledRequests, 'unmocked /api requests were made').toEqual([]);
  },
});

export { expect };

/** Locator for the SmartHomeCard of a given device name. */
export function deviceCard(page, name) {
  return page.locator('[data-slot="card"]').filter({ hasText: `${name} ·` });
}
