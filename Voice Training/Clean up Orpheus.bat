@echo off
title Clean up Orpheus
cd /d "%~dp0orpheus"
set "BIN=%~dp0_to_delete\orpheus_extras"
if not exist "%BIN%\models" mkdir "%BIN%\models"
if not exist "%BIN%\outputs" mkdir "%BIN%\outputs"
if not exist "%BIN%\tools" mkdir "%BIN%\tools"
echo Moving Orpheus files that aren't needed for setup, training or speaking
echo into _to_delete\orpheus_extras ...
echo.
for %%F in (codec_check.py compare_voice.py compare_engines.py orpheus_3b_0_1_ft.ipynb) do if exist "%%F" move "%%F" "%BIN%\" >nul && echo   %%F
for %%F in (bella_voice_f16.gguf bella_voice_q4.gguf Modelfile.q4) do if exist "models\%%F" move "models\%%F" "%BIN%\models\" >nul && echo   models\%%F
if exist "models\saved_voices" move "models\saved_voices" "%BIN%\models\" >nul && echo   models\saved_voices
if exist "outputs\test_outputs" move "outputs\test_outputs" "%BIN%\outputs\" >nul && echo   outputs\test_outputs
if exist "tools\backups" move "tools\backups" "%BIN%\tools\" >nul && echo   tools\backups
if exist "__pycache__" move "__pycache__" "%BIN%\" >nul && echo   __pycache__
echo.
echo Done. Check that "python fast_speak.py" still works, then delete the _to_delete folder
echo to free about 9 GB.
pause
