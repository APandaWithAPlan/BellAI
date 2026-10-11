# Endpoint to forward user's prompt to the AI server.
# 10/11/2026
# https://fastapi.tiangolo.com/tutorial/body/#import-pydantics-basemodel
# https://github.com/ollama/ollama-python


from fastapi import FastAPI
from pydantic import BaseModel
import ollama

# Format user request
class Prompt(BaseModel):
    request: str

client = ollama.Client(host="http://ip:port")
app = FastAPI()

# Create an endpoint to listen for and receive user prompts
@app.post("/text-prompt")
def receive_prompt(prompt: Prompt):
    # print(f"Prompt: {prompt.request}")

    formatted_request = format_request(prompt.request)
    response = forward_request(formatted_request)
    return get_response(response)

def format_request(request: str):
    pass

# Create function to send the prompt to the AI server
def forward_request(request: str):
    response = client.chat(model="", messages=[{'role': 'user', 'content': request}])

    return response

# Create a function to return the AI server's response to the user
def get_response(response):
    # print(f"Response: {response.message.content}")
    return {"response": response.message.content}