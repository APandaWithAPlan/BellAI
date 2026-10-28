"""BellAi Insights API: POST /insights returns food and workout recommendations.

Add it to the AI server (Server/bell_voice_server.py) with two lines after `app = FastAPI(...)`:
    sys.path.insert(0, str(HERE.parent / "Insights")); from insights_server import router as insights_router
    app.include_router(insights_router)

Or run it on its own for testing (port 8001):
    python insights_server.py

Settings (environment variables, all optional)
    OLLAMA_HOST         where Ollama runs (default 127.0.0.1:11434), same as the voice server
    INSIGHTS_MODEL      chat model (default qwen3.5:4b-q4_K_M)
    INSIGHTS_API_KEY    if set, every /insights request must send header X-API-Key: <value>
"""

import hmac
import os
from typing import List, Optional

import httpx
from fastapi import APIRouter, Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

from insights import MODEL, OLLAMA_URL, generate_insights

API_KEY = os.environ.get("INSIGHTS_API_KEY", "")
MAX_MEALS = 50


class UserPrefs(BaseModel):
    calorie_goal: Optional[float] = Field(None, ge=800, le=6000)
    protein_goal_g: Optional[float] = Field(None, ge=10, le=400)
    weight_kg: Optional[float] = Field(None, ge=25, le=400)
    sodium_limit_mg: Optional[float] = Field(None, ge=500, le=10000)
    allergies: List[str] = Field(default_factory=list, max_length=20)
    diet: Optional[str] = Field(None, max_length=30)           # vegetarian, vegan, halal, ...
    goal: Optional[str] = Field(None, max_length=30)           # lose, maintain, gain
    injuries: List[str] = Field(default_factory=list, max_length=10)
    fitness_level: Optional[str] = Field(None, max_length=20)  # beginner, intermediate, advanced
    dislikes: List[str] = Field(default_factory=list, max_length=30)


class InsightsRequest(BaseModel):
    user: UserPrefs = Field(default_factory=UserPrefs)
    meals: List[dict] = Field(default_factory=list, max_length=MAX_MEALS)  # food model results or nutrient dicts


def check_api_key(x_api_key: str = Header(default="")):
    if API_KEY and not hmac.compare_digest(x_api_key.encode(), API_KEY.encode()):
        raise HTTPException(status_code=401, detail="Missing or wrong X-API-Key header.")


router = APIRouter()


@router.post("/insights", dependencies=[Depends(check_api_key)])
def insights(req: InsightsRequest):
    # plain "def" runs in a worker thread, so a slow model call doesn't block the server
    return generate_insights(req.user.model_dump(), req.meals)


@router.get("/insights/health")
def insights_health():
    try:
        reachable = httpx.get(f"{OLLAMA_URL}/api/tags", timeout=3).is_success
    except httpx.HTTPError:
        reachable = False
    return {"status": "ok", "model": MODEL, "model_reachable": reachable}


app = FastAPI(title="BellAi Insights API", version="1.0")   # standalone app for testing
app.include_router(router)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=os.environ.get("HOST", "127.0.0.1"), port=int(os.environ.get("PORT", "8001")))
