# Endpoint to forward user's prompt to the AI server.
# 10/12/2026
# https://fastapi.tiangolo.com/tutorial/body/#import-pydantics-basemodel
# https://github.com/ollama/ollama-python
# https://pydantic.dev/docs/validation/dev/errors/validation_errors/
# https://fastapi.tiangolo.com/reference/uploadfile/#fastapi.UploadFile


from fastapi import FastAPI, UploadFile, File
from pydantic import BaseModel, Field, field_validator
import ollama
from pathlib import Path
import tempfile
import shutil
import subprocess

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

client = ollama.Client(host="http://ip:port")
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
    with tempfile.TemporaryFile() as temp_dir:
        input_path = Path(temp_dir) / "input_audio.webm" 
        output_path = Path(temp_dir) / "output_audio.wav"

        # Convert audio to format whisper-cli accepts
        convert_audio(audio_file.file, input_path, output_path)

        # Transcribe audio to text
        transcript = transcribe_audio(output_path)

    # Send transcript to AI server
    response = forward_request(transcript)

    # Return the AI server's response to the user
    return {"response": response.message.content}

# Create function to send the prompt to the AI server
def forward_request(request):
    response = client.chat(model="", messages=[{'role': 'user', 'content': request}])

    return response

def convert_audio(audio_file, input_path, output_path):
        with open(input_path, "wb") as f:
            shutil.copyfileobj(audio_file, f)

        subprocess.run(["ffmpeg", "-y", str(input_path), "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", str(output_path)], check=True, capture_output=True, text=True, timeout=120)

def transcribe_audio(output_path):
    whisper_output = subprocess.run(["/home/whisper.cpp/build/bin/whisper-cli", "-m", "/home/whisper.cpp/models/ggml-tiny.en.bin", "-f", str(output_path), "-l", "en", "-t", "4"], check=True, capture_output=True, text=True, timeout=120)

    return whisper_output.stdout.strip()