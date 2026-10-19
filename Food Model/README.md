# BellAI Food Model

This is the food part of BellAi. You send it a photo of food or type something like "2 eggs and toast", and it gives back the foods, portion sizes and nutrition. Qwen2.5-VL figures out what the food is and roughly how much of it there is, and the nutrition numbers come from the USDA FoodData Central database. It needs Windows, Python 3.10 to 3.12, an NVIDIA GPU (24 GB for the 7B model or 12 GB for 3B) and a free USDA API key. Run `setup.ps1` to install everything and start the server, then open http://127.0.0.1:8000 to try it. The API is described in `API.md`.
