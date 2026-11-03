@echo off
title BellAi Voice
rem Starts the BellAi voice server on Windows. Close this window to stop it.
cd /d "%~dp0"
set "SAVED=%~dp0gpt_sovits_folder_windows.txt"
if not defined GPT_SOVITS_DIR if exist "%SAVED%" set /p GPT_SOVITS_DIR=<"%SAVED%"
if defined GPT_SOVITS_DIR if exist "%GPT_SOVITS_DIR%\runtime\python.exe" goto run

:ask
echo Where is GPT-SoVITS? Paste the folder that has "runtime" and "GPT_SoVITS" in it, then press Enter.
set "GPT_SOVITS_DIR="
set /p "GPT_SOVITS_DIR=Folder: "
if not defined GPT_SOVITS_DIR goto ask
set "GPT_SOVITS_DIR=%GPT_SOVITS_DIR:"=%"
if not exist "%GPT_SOVITS_DIR%\runtime\python.exe" (
  echo Can't find runtime\python.exe in that folder.
  goto ask
)
>"%SAVED%" echo %GPT_SOVITS_DIR%

:run
"%GPT_SOVITS_DIR%\runtime\python.exe" "%~dp0bellai_voice_server.py" --gpt-sovits "%GPT_SOVITS_DIR%" %*
pause
