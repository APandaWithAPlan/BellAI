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
#     "type": "auth",
#     "access_token": HA_TOKEN
#     }))

#     auth_response = json.loads(await websocket.recv())

#     if auth_response["type"] != "auth_ok":
#             raise RuntimeError("Unable to authenticate to Home Assistant.")

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

    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.get(
            f"{HA_URL}/api/states/",
            headers={
                "Authorization": f"Bearer {HA_TOKEN}"
            }
        )

        response.raise_for_status()

        return response.json()

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

