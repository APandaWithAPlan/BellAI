@echo off
rem starts gpt-sovits in its own window, then the bell voice server here
rem usage: start_voice.bat [path to GPT-SoVITS]  (default ..\..\GPT-SoVITS)
setlocal
set "GSV=%~1"
if "%GSV%"=="" set "GSV=%~dp0..\..\GPT-SoVITS"
rem api_v2 prints chinese text, needs utf-8 or every request dies
set PYTHONUTF8=1
start "GPT-SoVITS api_v2" /D "%GSV%" "%GSV%\.venv\Scripts\python.exe" api_v2.py -a 127.0.0.1 -p 9880
:wait
rem check server
curl -s -o nul -m 2 http://127.0.0.1:9880/docs || (timeout /t 3 >nul & goto wait)
python "%~dp0bell_voice_server.py"
