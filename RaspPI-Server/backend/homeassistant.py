import os
import httpx
from dotenv import load_dotenv

load_dotenv()

HA_URL = os.getenv("HA_URL")
HA_TOKEN = os.getenv("HA_TOKEN")
HA_WEATHER_ENTITY = os.getenv("HA_WEATHER_ENTITY")
HA_HOME_LOCATION_ENTITY = os.getenv("HA_HOME_LOCATION_ENTITY")

async def get_entity(entity_id: str):
    headers = {
        "Authorization": f"Bearer {HA_TOKEN}"
    }

    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.get(
            f"{HA_URL}/api/states/{entity_id}",
            headers=headers
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

