import os
import json
import httpx
from dotenv import load_dotenv
from websockets.asyncio.client import connect

load_dotenv()

HA_URL = os.getenv("HA_URL")
HA_TOKEN = os.getenv("HA_TOKEN")
HA_WEATHER_ENTITY = os.getenv("HA_WEATHER_ENTITY")
HA_HOME_LOCATION_ENTITY = os.getenv("HA_HOME_LOCATION_ENTITY")

# async def listen_to_home_assistant():
#     ws_url = HA_URL.replace("http://", "ws://") + "/api/websocket"

#     async with connect(ws_url) as websocket:
#         message = json.loads(await websocket.recv())

#     if message["type"] != "auth_required":
#         raise RuntimeError("Unexpected authentication response")

#     await websocket.send(json.dumps({
#         "type": "auth",
#         "access_token": HA_TOKEN
#     }))

#     auth_response = json.loads(await websocket.recv())

#     if auth_response["type"] != "auth_ok":
#             raise RuntimeError("Unable to authenticate to Home Assistant.")

#     await websocket.send(json.dumps({
#         "id": 1,
#         "type": "subscribe_events",
#         "event_type": "state_changed"
#     }))

#     subscription = json.loads(await websocket.recv())

#     if not subscription.get("success"):
#         raise RuntimeError("Unable to subscribe to state_changed")

#     async for message in websocket:
#         event = json.loads(message)

#         if event.get("type") == "event":
#             data = event["event"]["data"]

#             entity_id = data["entity_id"]
#             new_state = data["new_state"]

#             if new_state is None:
#                 continue

#             await broadcast_event({
#                 "entity_id": entity_id,
#                 "state": new_state["state"],
#             })


async def get_entity(entity_id: str):

    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.get(
            f"{HA_URL}/api/states/{entity_id}",
            headers={
                "Authorization": f"Bearer {HA_TOKEN}"
            }
        )

        response.raise_for_status()

        return response.json()

async def get_entities():

    template = """

        {% set domains = ['light', 'media_player', 'switch', 'fan'] %}
        {% set ns = namespace(devices=[]) %}

        {% for entity in states | selectattr('domain', 'in', domains) %}
            {% set ns.devices = ns.devices + [{
                'entity_id': entity.entity_id,
                'name': entity.attributes.get('friendly_name', entity.entity_id),
                'state': entity.state,
                'area': area_name(entity.entity_id),
                'attributes': entity.attributes
            }] %}
        {% endfor %}

        {{ ns.devices | to_json }}

    """

    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.post(
            f"{HA_URL}/api/template",
            headers={
                "Authorization": f"Bearer {HA_TOKEN}"
            },
            json={
                "template": template
            }
        )

        response.raise_for_status()

        return json.loads(response.text)

async def get_forecast(entity_id: str):

    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.post(
            f"{HA_URL}/api/services/weather/get_forecasts",
            params={"return_response": "true"},
            headers={
                "Authorization": f"Bearer {HA_TOKEN}"
            },
            json={
                "entity_id": entity_id,
                "type": "daily"
            }
        )

        response.raise_for_status()
        
        return response.json()

async def command_device(entity_id: str, domain: str, action: str, data: dict | None = None):

    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.post(
            f"{HA_URL}/api/services/{domain}/{action}",
            headers={
                "Authorization": f"Bearer {HA_TOKEN}"
                },
            json = {
                "entity_id": entity_id,
                **(data or {})
            }
        )

        response.raise_for_status()

        return response.json()