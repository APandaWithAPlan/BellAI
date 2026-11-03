#!/bin/bash
# Starts the BellAi voice server on macOS. Close this window to stop it.
cd "$(dirname "$0")" || exit 1
SAVED="gpt_sovits_folder_mac.txt"

DIR="${GPT_SOVITS_DIR:-}"
if [ -z "$DIR" ] && [ -f "$SAVED" ]; then DIR="$(head -n 1 "$SAVED")"; fi
if [ -z "$DIR" ]; then DIR="$HOME/GPT-SoVITS"; fi
while [ ! -d "$DIR/GPT_SoVITS" ]; do
  echo "Where is GPT-SoVITS? Drag its folder into this window, then press Return."
  read -r -p "Folder: " DIR
  DIR="${DIR%"${DIR##*[![:space:]]}"}"     # drop the space Terminal adds after a dragged folder
  DIR="${DIR//\\ / }"; DIR="${DIR#\'}"; DIR="${DIR%\'}"
done
echo "$DIR" > "$SAVED"

# Use GPT-SoVITS's conda environment (named GPTSoVits by its install guide), if there is one.
ENV_NAME="${GPT_SOVITS_ENV:-GPTSoVits}"
for CONDA_SH in "$HOME/miniconda3" "$HOME/anaconda3" "$HOME/miniforge3" "/opt/homebrew/Caskroom/miniconda/base" "/opt/miniconda3" "/opt/anaconda3"; do
  if [ -f "$CONDA_SH/etc/profile.d/conda.sh" ]; then
    source "$CONDA_SH/etc/profile.d/conda.sh"
    conda activate "$ENV_NAME" 2>/dev/null || echo "No conda environment called $ENV_NAME, using the default Python."
    break
  fi
done
PYTHON="$(command -v python || command -v python3)"

"$PYTHON" bellai_voice_server.py --gpt-sovits "$DIR" "$@"
read -r -p "Press Return to close."
