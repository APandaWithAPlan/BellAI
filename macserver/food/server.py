"""Food API: POST a photo or text to /analyze and get nutrition JSON back.

Usage: python server.py   (then open http://127.0.0.1:8002)
"""

import io
import os
import re
import warnings
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
from pathlib import Path

from typing import Optional

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from PIL import Image, UnidentifiedImageError

from analyze_food import MAX_TEXT_CHARS, MODEL_ID, ModelNotLoaded, analyze, analyze_text, load_model

MODEL = os.environ.get("FOOD_MODEL", MODEL_ID)

MAX_UPLOAD_BYTES = 10 * 1024 * 1024  # 10 MB
ALLOWED_FORMATS = {"JPEG", "PNG", "WEBP"}
Image.MAX_IMAGE_PIXELS = 40_000_000  # refuse "decompression bomb" images
MAX_NOTE_CHARS = 300
TEST_PAGE = Path(__file__).resolve().parent / "static" / "index.html"

state = {"model": None, "processor": None}
# mlx wants the model used on the thread that loaded it, so one thread does all of it (and one photo at a time)
gpu = ThreadPoolExecutor(max_workers=1)


@asynccontextmanager
async def lifespan(app):
    print(f"Loading {MODEL} ... (first run downloads ~6 GB)")
    state["model"], state["processor"] = gpu.submit(load_model, MODEL).result()
    print("Model ready.")
    yield
    gpu.shutdown(wait=False)


app = FastAPI(title="BellAi Food API", version="1.0", lifespan=lifespan)


def read_image(upload: UploadFile):
    """Read the upload with a size cap and make sure it really is a JPEG/PNG/WEBP"""
    data = upload.file.read(MAX_UPLOAD_BYTES + 1)
    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="Image is larger than 10 MB.")
    if not data:
        raise HTTPException(status_code=400, detail="No image data received.")
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            probe = Image.open(io.BytesIO(data))
            fmt = probe.format
            probe.verify()  # catches truncated/corrupt files
            image = Image.open(io.BytesIO(data))
            image.load()
    except (UnidentifiedImageError, OSError, SyntaxError, ValueError,
            Image.DecompressionBombError, Image.DecompressionBombWarning):
        raise HTTPException(status_code=400, detail="That file isn't a readable image.")
    if fmt not in ALLOWED_FORMATS:
        raise HTTPException(status_code=400, detail="Please upload a JPEG, PNG or WEBP image.")
    return image


def safe_name(filename):
    name = re.sub(r"[^A-Za-z0-9._-]", "_", os.path.basename(filename or "upload"))
    return name[:100] or "upload"


@app.get("/", include_in_schema=False)
def test_page():
    return FileResponse(TEST_PAGE)


@app.get("/health")
def health():
    return {"status": "ok", "model": MODEL, "ready": state["model"] is not None}


@app.post("/analyze")
def analyze_food(image: Optional[UploadFile] = File(default=None, description="Food photo (JPEG, PNG or WEBP, max 10 MB)"),
                 text: str = Form(default="", description="Meal description, or a note for the photo"),
                 note: str = Form(default="", description="Older name for text when sending a photo")):
    # A plain "def" endpoint runs in a worker thread
    text = (text or note or "").strip()
    has_image = image is not None and bool(image.filename)

    if has_image:
        if state["model"] is None:
            raise HTTPException(status_code=503, detail="Model is still loading, try again shortly.")
        pil_image = read_image(image)
        return gpu.submit(analyze, state["model"], state["processor"], pil_image,
                          note=text[:MAX_NOTE_CHARS] or None,
                          model_id=MODEL, image_name=safe_name(image.filename)).result()

    if not text:
        raise HTTPException(status_code=400, detail="Send a photo (image) or a description (text).")
    if len(text) > MAX_TEXT_CHARS:
        raise HTTPException(status_code=400, detail=f"Description is longer than {MAX_TEXT_CHARS} characters.")
    try:
        # the fast path needs no model
        return gpu.submit(analyze_text, state["model"], state["processor"], text, model_id=MODEL).result()
    except ModelNotLoaded:
        raise HTTPException(status_code=503, detail="Model is still loading, try again shortly.")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=os.environ.get("HOST", "127.0.0.1"), port=int(os.environ.get("PORT", "8002")))
