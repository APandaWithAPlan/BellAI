@echo off
title BellAi Studio
set "GSV=%~dp0GPT-SoVITS\GPT-SoVITS-v3lora-20250228"
if not exist "%GSV%\runtime\python.exe" (
  echo Can't find GPT-SoVITS at:
  echo   %GSV%
  echo Unzip GPT-SoVITS into the Voice Training\GPT-SoVITS folder, then try again.
  pause
  exit /b 1
)
echo Starting BellAi Studio. Your browser will open by itself.
echo Keep this window open while you use it. Close it to shut BellAi Studio down.
echo.
"%GSV%\runtime\python.exe" "%~dp0studio\bellai_studio.py"
pause
