# BellAI Dashboard - Devices Page Test Plan

## Application Overview

The Devices page (/devices) lists Home Assistant light entities as cards with an on/off switch. On mount it opens a WebSocket to /ws/devices; when the socket opens it fetches a snapshot from GET /api/devices. WebSocket state_changed messages ({entity_id, new_state}) update, add or remove entities live. Toggling a switch sends POST /api/device/command ({entity_id, domain, action: turn_on|turn_off, data: {}}) and shows a toast. The switch is server-authoritative: it only flips when a WebSocket update arrives. The header shows "N of M active" and a progress bar, counting lights only.

Seed: tests/seed.spec.ts (navigates to /devices, expects heading "Smart Home"). Mocks: tests/fixtures/home-assistant.js (fixture `ha`).

SAFETY: The Vite dev server proxies /api and /ws to a REAL Home Assistant bridge controlling real lights. The `ha` fixture intercepts every /api/** request (catch-all returns 503 and records it in ha.unhandledRequests, which the fixture asserts is empty at teardown) and every /ws/** WebSocket (routeWebSocket without connectToServer, so nothing reaches the proxy). Every test MUST use the `ha` fixture and be installed before page.goto. Never navigate outside the seeded page, never un-route, never fetch the real backend.

Mock API (ha fixture): ha.devicesResponse = array | {status, body} | async function (delay/hold the snapshot); ha.commandResponse = {status, body} | 'network-error'; ha.commands = recorded POST bodies; ha.devicesRequestCount; ha.connectionCount; ha.sockets; await ha.push(message) sends to all open sockets (object is JSON-stringified, string sent raw); await ha.dropConnections() closes server side. stateChanged(entityId, state|null, attributes) builds a WS message; deviceCard(page, name) locates a card; DEFAULT_DEVICES is exported.

Default snapshot: light.living_room_lamp "Living Room Lamp"/Living Room (on), light.bedroom_ceiling "Bedroom Ceiling"/Bedroom (off), light.porch "Porch Light"/Outside (unavailable), switch.coffee_maker (on, non-light), sensor.temperature (non-light). Initial UI: "1 of 3 active", 3 switches.

Conventions: toasts are in region "Notifications". Each test starts from a fresh page; apply ha.* configuration before page.goto('/devices'). Expected outcomes describe CORRECT user-facing behavior; tests marked [DEFECT] are expected to fail against the current code and expose a real bug.

## Test Scenarios

### 1. Device rendering

**Seed:** `tests/seed.spec.ts`

#### 1.1. 1.1 Renders only light entities with name and area

**File:** `tests/devices/rendering.spec.js`

**Steps:**
  1. Default mocks; goto /devices
    - expect: Cards 'Living Room Lamp · Living Room', 'Bedroom Ceiling · Bedroom', 'Porch Light · Outside' visible
    - expect: 'Coffee Maker' and 'Temperature' not present
    - expect: Exactly 3 switches

#### 1.2. 1.2 Active count and progress count lights only

**File:** `tests/devices/rendering.spec.js`

**Steps:**
  1. Default mocks; goto /devices
    - expect: Text '1 of 3 active' (the on switch.coffee_maker is not counted)
    - expect: progressbar aria-valuenow approx 33.3

#### 1.3. 1.3 Switch state reflects device state

**File:** `tests/devices/rendering.spec.js`

**Steps:**
  1. Default mocks; inspect switches per card
    - expect: Living Room Lamp checked
    - expect: Bedroom Ceiling unchecked
    - expect: Porch Light (unavailable) unchecked

#### 1.4. 1.4 Fallbacks for missing name and area

**File:** `tests/devices/rendering.spec.js`

**Steps:**
  1. ha.devicesResponse = [{entity_id:'light.x', state:'off', area:null, attributes:{}}]; goto
    - expect: Card text 'Unknown Device · Unassigned' (or the entity id, but never the literal 'undefined' or 'null')

#### 1.5. 1.5 Empty device list

**File:** `tests/devices/rendering.spec.js`

**Steps:**
  1. ha.devicesResponse = []; goto
    - expect: '0 of 0 active', no switches, progress value 0, no NaN anywhere

#### 1.6. 1.6 Only non-light entities

**File:** `tests/devices/rendering.spec.js`

**Steps:**
  1. ha.devicesResponse = [switch.coffee_maker, sensor.temperature]
    - expect: '0 of 0 active', zero cards

#### 1.7. 1.7 Reachable from navigation bar

**File:** `tests/devices/rendering.spec.js`

**Steps:**
  1. goto /; click navigation link 'Devices'
    - expect: URL is /devices, heading 'Smart Home' visible, cards rendered from mocked snapshot

#### 1.8. 1.8 Many devices layout

**File:** `tests/devices/rendering.spec.js`

**Steps:**
  1. ha.devicesResponse with 12 lights of which 4 on; goto
    - expect: 12 cards, '4 of 12 active', progress approx 33.3, long names not overflowing card (visible text intact)

### 2. Light toggles

**Seed:** `tests/seed.spec.ts`

#### 2.1. 2.1 Turning a light on sends turn_on

**File:** `tests/devices/toggles.spec.js`

**Steps:**
  1. Default mocks; click Bedroom Ceiling switch
    - expect: ha.commands equals exactly [{entity_id:'light.bedroom_ceiling', domain:'light', action:'turn_on', data:{}}]
    - expect: Toast 'Bedroom Ceiling is on.' shown

#### 2.2. 2.2 Turning a light off sends turn_off

**File:** `tests/devices/toggles.spec.js`

**Steps:**
  1. Click Living Room Lamp switch
    - expect: One POST with action turn_off
    - expect: Toast 'Living Room Lamp is off.'

#### 2.3. 2.3 Switch is server-authoritative

**File:** `tests/devices/toggles.spec.js`

**Steps:**
  1. Click Bedroom Ceiling; verify switch state; then ha.push(stateChanged('light.bedroom_ceiling','on'))
    - expect: Before push switch stays unchecked and '1 of 3 active'
    - expect: After push switch checked and '2 of 3 active'

#### 2.4. 2.4 Switch does not diverge when command succeeds but no WS event arrives

**File:** `tests/devices/toggles.spec.js`

**Steps:**
  1. Click Living Room Lamp switch, no push
    - expect: Switch remains in the server state (checked); toggling again sends turn_off again (checked param derived from the switch's new value) rather than corrupting state

#### 2.5. 2.5 Rapid double click sends two ordered commands

**File:** `tests/devices/toggles.spec.js`

**Steps:**
  1. Double click Bedroom Ceiling switch
    - expect: No uncaught page error; ha.commands has at most 2 entries; UI consistent after pushes

#### 2.6. 2.6 Keyboard toggle

**File:** `tests/devices/toggles.spec.js`

**Steps:**
  1. Focus Bedroom Ceiling switch, press Space
    - expect: turn_on POST sent, toast shown

#### 2.7. 2.7 Toggling does not affect other devices

**File:** `tests/devices/toggles.spec.js`

**Steps:**
  1. Click Bedroom Ceiling
    - expect: Only one command recorded and only for light.bedroom_ceiling

### 3. Unavailable devices

**Seed:** `tests/seed.spec.ts`

#### 3.1. 3.1 Toggling an unavailable light is blocked

**File:** `tests/devices/unavailable.spec.js`

**Steps:**
  1. Click Porch Light switch
    - expect: Error toast 'Porch Light is unavailable.'
    - expect: ha.commands empty
    - expect: Switch stays unchecked

#### 3.2. 3.2 Toggling an unknown-state light is blocked

**File:** `tests/devices/unavailable.spec.js`

**Steps:**
  1. Snapshot light with state 'unknown'; click it
    - expect: Toast '<name> is unavailable.', no POST

#### 3.3. 3.3 Device becoming unavailable via WS blocks commands

**File:** `tests/devices/unavailable.spec.js`

**Steps:**
  1. ha.push(stateChanged('light.bedroom_ceiling','unavailable')); click its switch
    - expect: Unavailable toast, no POST, switch unchecked, active count unchanged

#### 3.4. 3.4 Device recovering via WS can be toggled

**File:** `tests/devices/unavailable.spec.js`

**Steps:**
  1. ha.push(stateChanged('light.porch','off')); click Porch switch
    - expect: POST turn_on for light.porch, toast 'Porch Light is on.'

#### 3.5. 3.5 Unavailable lights are not counted active

**File:** `tests/devices/unavailable.spec.js`

**Steps:**
  1. Push Living Room Lamp -> unavailable
    - expect: '0 of 3 active'; lamp switch unchecked

#### 3.6. 3.6 [DEFECT] Unavailable toast for snapshot device without name

**File:** `tests/devices/unavailable.spec.js`

**Steps:**
  1. Snapshot {entity_id:'light.nameless', state:'unavailable'} (no name); click it
    - expect: Toast does not contain the text 'undefined' (use fallback 'Unknown Device' or entity id, consistent with the card label)

### 4. API errors

**Seed:** `tests/seed.spec.ts`

#### 4.1. 4.1 Snapshot fetch failure shows error toast

**File:** `tests/devices/api-errors.spec.js`

**Steps:**
  1. ha.devicesResponse = {status:500}; goto
    - expect: Toast 'Failed to fetch /api/devices.'
    - expect: '0 of 0 active', no cards, page not crashed

#### 4.2. 4.2 [DEFECT] Command HTTP error shows meaningful error and no success toast

**File:** `tests/devices/api-errors.spec.js`

**Steps:**
  1. ha.commandResponse = {status:500, body:{error:'boom'}}; click Bedroom Ceiling switch
    - expect: Exactly one error toast that names the device (e.g. 'Failed to control Bedroom Ceiling'), NOT 'device is not defined'
    - expect: Success toast 'Bedroom Ceiling is on.' is NOT shown
    - expect: Switch remains unchecked

#### 4.3. 4.3 [DEFECT] Command network failure shows error and no success toast

**File:** `tests/devices/api-errors.spec.js`

**Steps:**
  1. ha.commandResponse = 'network-error'; click Bedroom Ceiling switch
    - expect: Error toast shown, no success toast 'Bedroom Ceiling is on.'
    - expect: Switch unchanged

#### 4.4. 4.4 [DEFECT] Command 4xx (e.g. 400/404) shows error

**File:** `tests/devices/api-errors.spec.js`

**Steps:**
  1. ha.commandResponse = {status:404, body:{}}; click Living Room Lamp
    - expect: Error toast naming Living Room Lamp, no 'is off.' success toast

#### 4.5. 4.5 Command error toast appears once, not duplicated

**File:** `tests/devices/api-errors.spec.js`

**Steps:**
  1. 500 on command; click a switch; count toasts in Notifications region
    - expect: No more than one error toast per failed action

#### 4.6. 4.6 App recovers after a failed command

**File:** `tests/devices/api-errors.spec.js`

**Steps:**
  1. Fail first command (500), then set ha.commandResponse to 200 and click again
    - expect: Second click sends POST and shows success toast

#### 4.7. 4.7 Snapshot failure does not break live updates

**File:** `tests/devices/api-errors.spec.js`

**Steps:**
  1. ha.devicesResponse = {status:500}; goto; ha.push(stateChanged('light.kitchen','on',{friendly_name:'Kitchen Pendant'}))
    - expect: Card 'Kitchen Pendant' appears, '1 of 1 active'

#### 4.8. 4.8 Snapshot with malformed (non-array) body

**File:** `tests/devices/api-errors.spec.js`

**Steps:**
  1. ha.devicesResponse = async () => ({oops:true}); goto
    - expect: Page does not crash (heading still visible); an error toast or empty state shown

### 5. WebSocket state updates

**Seed:** `tests/seed.spec.ts`

#### 5.1. 5.1 State change turns a light on

**File:** `tests/devices/websocket.spec.js`

**Steps:**
  1. ha.push(stateChanged('light.bedroom_ceiling','on'))
    - expect: Switch checked, '2 of 3 active', progress approx 66.7

#### 5.2. 5.2 State change turns a light off

**File:** `tests/devices/websocket.spec.js`

**Steps:**
  1. ha.push(stateChanged('light.living_room_lamp','off'))
    - expect: Switch unchecked, '0 of 3 active', progress 0

#### 5.3. 5.3 New light entity is added

**File:** `tests/devices/websocket.spec.js`

**Steps:**
  1. Push stateChanged('light.kitchen','on',{friendly_name:'Kitchen Pendant'})
    - expect: Card 'Kitchen Pendant · Unassigned' checked, '2 of 4 active'

#### 5.4. 5.4 friendly_name update renames and preserves area

**File:** `tests/devices/websocket.spec.js`

**Steps:**
  1. Push light.bedroom_ceiling off with friendly_name 'Master Light'
    - expect: Card 'Master Light · Bedroom'; old name gone; still 3 cards

#### 5.5. 5.5 Entity removal

**File:** `tests/devices/websocket.spec.js`

**Steps:**
  1. Push stateChanged('light.living_room_lamp', null)
    - expect: Card removed, '0 of 2 active'

#### 5.6. 5.6 Non-light and malformed messages are ignored

**File:** `tests/devices/websocket.spec.js`

**Steps:**
  1. Push switch.coffee_maker state change, push {} (no entity_id), push {entity_id:null}
    - expect: UI unchanged: 3 cards, '1 of 3 active', no toast

#### 5.7. 5.7 [DEFECT] Invalid JSON message does not break the page

**File:** `tests/devices/websocket.spec.js`

**Steps:**
  1. ha.push('not json'); then push a valid change for Bedroom Ceiling
    - expect: No uncaught page error (listen for pageerror); the following valid message still updates the UI

#### 5.8. 5.8 WS update racing the snapshot wins

**File:** `tests/devices/websocket.spec.js`

**Steps:**
  1. ha.devicesResponse = async function awaiting a gate promise; goto; wait for socket; push bedroom -> on; release gate (snapshot says off)
    - expect: Bedroom Ceiling remains checked, '2 of 3 active'

#### 5.9. 5.9 Entity removed by WS during snapshot is not resurrected

**File:** `tests/devices/websocket.spec.js`

**Steps:**
  1. Gate snapshot; push null state for Living Room Lamp; release snapshot containing it
    - expect: Living Room Lamp card absent

#### 5.10. 5.10 Reconnects and refetches after socket drops

**File:** `tests/devices/websocket.spec.js`

**Steps:**
  1. Load page; record ha.connectionCount (1) and devicesRequestCount (1); change ha.devicesResponse (e.g. Bedroom on); await ha.dropConnections()
    - expect: Within ~5s connectionCount is 2 and devicesRequestCount is 2
    - expect: New snapshot rendered (Bedroom checked), pushes work on the new socket

#### 5.11. 5.11 Dropped connection informs the user

**File:** `tests/devices/websocket.spec.js`

**Steps:**
  1. await ha.dropConnections()
    - expect: User sees some indication (toast) that live connection was lost/reconnecting, and no repeated toast flood during reconnects

#### 5.12. 5.12 No reconnect after leaving the page

**File:** `tests/devices/websocket.spec.js`

**Steps:**
  1. Click nav 'Home' (unmount Devices); wait > 3.5s
    - expect: connectionCount does not increase; no stale-state errors

#### 5.13. 5.13 Attributes merge on update

**File:** `tests/devices/websocket.spec.js`

**Steps:**
  1. Push living_room_lamp on with attributes {color_temp:300}
    - expect: Card still rendered with original name and area; still checked
