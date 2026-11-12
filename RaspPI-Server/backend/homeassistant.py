import os
import json
import httpx
from dotenv import load_dotenv
import asyncio
from py_ha_ws_client import HomeAssistantWsClient

load_dotenv()

HA_URL = os.getenv("HA_URL")
HA_TOKEN = os.getenv("HA_TOKEN")
HA_WEATHER_ENTITY = os.getenv("HA_WEATHER_ENTITY")
HA_HOME_LOCATION_ENTITY = os.getenv("HA_HOME_LOCATION_ENTITY")

async def listen_to_home_assistant(on_state_change):
    ws_url = HA_URL.replace("http://", "ws://") + "/api/websocket"

    async with HomeAssistantWsClient.with_url(HA_TOKEN, ws_url, auto_reconnect=True) as client:
        async def handle_state_change(event):
            data = event["data"]
            entity_id = data["entity_id"]

            if entity_id.startswith(("light.", "switch.", "media_player.")):
                await on_state_change({
                    "entity_id": entity_id,
                    "new_state": data.get("new_state")
                })

        await client.subscribe_events("state_changed", handle_state_change)

        await asyncio.Event().wait()


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