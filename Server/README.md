## Server
This server runs the AI models, this includes Vison/Voice/LLM. 

How this works:
```
ai-server 
├─ :11434  Ollama (chat, qwen3.5:4b-q4_K_M) 
└─ :8000   voice server + food model 
    /ws       streamed reply + sentence audio 
    /analyze  photo and/or text → summary, items, totals 
    /speak    text → wav 
```

Ollama Port is configured as the default
Voice port is configured on port 8000.
