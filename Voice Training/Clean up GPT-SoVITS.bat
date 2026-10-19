@echo off
title Clean up GPT-SoVITS
setlocal
set "GSV=%~dp0GPT-SoVITS\GPT-SoVITS-v3lora-20250228"
set "BIN=%~dp0_to_delete\gpt_sovits_extras"
if not exist "%GSV%\runtime" (
  echo Can't find GPT-SoVITS at %GSV%
  pause
  exit /b 1
)
echo Close BellAi Studio before continuing (it can't be running while files move).
pause
cd /d "%GSV%"
for %%D in (tools GPT_SoVITS\pretrained_models logs GPT_weights_v2 SoVITS_weights_v2) do if not exist "%BIN%\%%D" mkdir "%BIN%\%%D"
echo.
echo Moving things BellAi doesn't use into _to_delete\gpt_sovits_extras ...
echo.

rem --- old web UI, docs, Docker, notebooks, other APIs ---
for %%F in (go-webui.bat go-webui.ps1 webui.py api.py api_v2.py batch_inference.py colab_webui.ipynb GPT_SoVITS_Inference.ipynb gpt-sovits_kaggle.ipynb install.sh Dockerfile docker-compose.yaml dockerbuild.sh .dockerignore README.md) do call :mv "%%F" "%BIN%\%%F"
for %%F in (docs Docker output __pycache__ GPT_weights GPT_weights_v3 SoVITS_weights SoVITS_weights_v3) do call :mv "%%F" "%BIN%\%%F"

rem --- audio tools for other workflows (vocal separation, Chinese speech recognition, denoise, slicer) ---
for %%F in (uvr5 asr denoise-model AP_BWE_main audio_sr.py cmd-denoise.py slice_audio.py slicer2.py subfix_webui.py) do call :mv "tools\%%F" "%BIN%\tools\%%F"

rem --- base models for versions 1 and 3 (BellAi uses version 2) ---
for %%F in ("s1bert25hz-2kh-longer-epoch=68e-step=50232.ckpt" s1v3.ckpt s2D488k.pth s2G488k.pth s2Gv3.pth models--nvidia--bigvgan_v2_24khz_100band_256x) do call :mv "GPT_SoVITS\pretrained_models\%%~F" "%BIN%\GPT_SoVITS\pretrained_models\%%~F"

rem --- your first two practice runs (the current voice is bellai_1012_2137) ---
call :mv "logs\BellAi SOVITS 1" "%BIN%\logs\BellAi SOVITS 1"
call :mv "logs\bellai_sovits1" "%BIN%\logs\bellai_sovits1"
for %%F in (bellai_sovits1-e5.ckpt bellai_sovits1-e10.ckpt bellai_sovits1-e15.ckpt) do call :mv "GPT_weights_v2\%%F" "%BIN%\GPT_weights_v2\%%F"
for %%F in (bellai_sovits1_e4_s260.pth bellai_sovits1_e8_s520.pth) do call :mv "SoVITS_weights_v2\%%F" "%BIN%\SoVITS_weights_v2\%%F"

echo.
echo Done. Open BellAi Studio, say a line, and if it works, delete the _to_delete folder.
pause
exit /b 0

:mv
if exist "%~1" (
  move "%~1" "%~2" >nul 2>&1 && (echo   %~1) || (echo   COULDN'T MOVE %~1 - is something using it?)
)
exit /b 0
