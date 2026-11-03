# BellAi Insights API: POST /insights returns food and workout recommendations.

import hmac
import os
from typing import List, Optional

import httpx
from fastapi import APIRouter, Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from insights import MODEL, OLLAMA_URL, generate_insights

API_KEY = os.environ.get("INSIGHTS_API_KEY", "")
MAX_MEALS = 50   # most meals accepted in one request


# User goals and limits
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


# One logged meal
class Meal(BaseModel):
    model_config = ConfigDict(extra="allow")   # extra /analyze fields (items, summary) are passed through

    name: Optional[str] = Field(None, max_length=200)
    kcal: Optional[float] = Field(None, ge=0, le=10000)
    protein_g: Optional[float] = Field(None, ge=0, le=1000)
    carbs_g: Optional[float] = Field(None, ge=0, le=2000)
    fat_g: Optional[float] = Field(None, ge=0, le=1000)
    fiber_g: Optional[float] = Field(None, ge=0, le=500)
    sugar_g: Optional[float] = Field(None, ge=0, le=1000)
    sodium_mg: Optional[float] = Field(None, ge=0, le=50000)
    totals: Optional[dict] = None


# Request body
class InsightsRequest(BaseModel):
    user: UserPrefs = Field(default_factory=UserPrefs)
    meals: List[Meal] = Field(default_factory=list, max_length=MAX_MEALS)


# Checks the X-API-Key header
def check_api_key(x_api_key: str = Header(default="")):
    if API_KEY and not hmac.compare_digest(x_api_key.encode(), API_KEY.encode()):
        raise HTTPException(status_code=401, detail="Missing or wrong X-API-Key header.")


router = APIRouter()


# Returns recommendations
@router.post("/insights", dependencies=[Depends(check_api_key)])
def insights(req: InsightsRequest):
    return generate_insights(req.user.model_dump(), [m.model_dump(exclude_none=True) for m in req.meals])


# Checks the model is reachable
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
