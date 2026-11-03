from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pathlib import Path

DIST_DIR = Path(__file__).resolve().parent.parent / "dashboard" / "dist"

def setup_dashboard(app: FastAPI):
    app.mount(
        "/assets",
        StaticFiles(directory=DIST_DIR / "assets"),
        name="assets"
    )

    @app.get("/{path:path}", include_in_schema=False)
    async def serve_react(path: str):
        return FileResponse(DIST_DIR / "index.html")