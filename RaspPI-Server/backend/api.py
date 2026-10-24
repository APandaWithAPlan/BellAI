# Endpoint to forward user's prompt to the AI server.
# 10/12/2026
# https://fastapi.tiangolo.com/tutorial/body/#import-pydantics-basemodel
# https://github.com/ollama/ollama-python
# https://pydantic.dev/docs/validation/dev/errors/validation_errors/
# https://fastapi.tiangolo.com/reference/uploadfile/#fastapi.UploadFile


from fastapi import FastAPI, UploadFile, File, HTTPException
from pydantic import BaseModel, Field, field_validator, ValidationError
import ollama
from pathlib import Path
import tempfile
import shutil
import subprocess

client = ollama.Client(host="http://ip:port")
whisper_cli = Path.home() / "whisper.cpp/build/bin/whisper-cli"
whisper_model = Path.home() / "whisper.cpp/models/ggml-tiny.en.bin"

# Format user request
class Prompt(BaseModel):
    request: str = Field(min_length=1, max_length=10000)

    @field_validator('request')
    @classmethod
    # Create a function to handle malformed or invalid requests
    def validate_request(cls, v: str):
        if not v.strip():
            raise ValueError("The prompt cannot be empty.")
        
        return v

app = FastAPI()

# Create an endpoint to listen for and receive user prompts
@app.post("/chat")
def receive_chat_prompt(prompt: Prompt):
    # print(f"Prompt: {prompt.request}")
    response = forward_request(prompt.request)

    # Return the AI server's response to the user
    return {"response": response.message.content}

@app.post("/audio")
def receive_audio_prompt(audio_file: UploadFile = File(...)):
    if audio_file.content_type not in ["audio/webm", "video/webm"]:
        raise HTTPException(status_code=415, detail="Unsupported audio format. A /webm file is expected.")
    
    with tempfile.TemporaryDirectory() as temp_dir:
        input_path = Path(temp_dir) / "input_audio.webm" 
        output_path = Path(temp_dir) / "output_audio.wav"

        # Convert audio to format whisper-cli accepts
        convert_audio(audio_file.file, input_path, output_path)

        # Transcribe audio to text
        transcript = transcribe_audio(output_path)

        try:
            validated_prompt = Prompt(request=transcript)

        except ValidationError as e:
            raise HTTPException(status_code=422, detail="The audio prompt is invalid or empty.")

    # Send transcript to AI server
    response = forward_request(validated_prompt.request)

    # Return the AI server's response to the user
    return {"response": response.message.content}

# Create function to send the prompt to the AI server
def forward_request(request):
    try:
        response = client.chat(model="qwen3:8b", messages=[{'role': 'user', 'content': request}])

    except ollama.ResponseError as e:
        raise HTTPException(status_code=502, detail="Ollama encountered an error while processing the request.")
    
    except ollama.RequestError as e:
        raise HTTPException(status_code=503, detail="The Ollama server is unavailable/unreachable.")

    return response

def convert_audio(audio_file, input_path, output_path):
        with open(input_path, "wb") as f:
            shutil.copyfileobj(audio_file, f)
        try:
            subprocess.run(["ffmpeg", "-y", "-i", str(input_path), "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", str(output_path)], check=True, capture_output=True, text=True, timeout=120)

        except subprocess.CalledProcessError as e:
            raise HTTPException(status_code=500, detail="There was an error formatting the audio.")

def transcribe_audio(output_path):
    transcript_path = output_path.with_suffix(".txt")

    try:
        subprocess.run([str(whisper_cli), "-m", str(whisper_model), "-f", str(output_path), "-l", "en", "-t", "4", "-otxt", "-of", str(transcript_path.with_suffix(""))], check=True, capture_output=True, text=True, timeout=120)

    except subprocess.CalledProcessError as e:
        raise HTTPException(status_code=500, detail="There was an error transcribing the audio.")

    return transcript_path.read_text(encoding="utf-8").strip()