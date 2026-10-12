# Endpoint to forward user's prompt to the AI server.
# 10/12/2026
# https://fastapi.tiangolo.com/tutorial/body/#import-pydantics-basemodel
# https://github.com/ollama/ollama-python
# https://pydantic.dev/docs/validation/dev/errors/validation_errors/
# https://fastapi.tiangolo.com/reference/uploadfile/#fastapi.UploadFile


from fastapi import FastAPI, UploadFile
from pydantic import BaseModel, Field, field_validator
import ollama

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
    return get_response(response)

@app.post("/audio")
async def receive_audio_prompt(audio: UploadFile):
    # convert audio to format whisper-cli accepts
    # transcribe audio to text
    # send to ai server
    pass

# Create function to send the prompt to the AI server
def forward_request(request: str):
    response = client.chat(model="", messages=[{'role': 'user', 'content': request}])

    return response

# Create a function to return the AI server's response to the user
def get_response(response):
    # print(f"Response: {response.message.content}")

    return {"response": response.message.content}