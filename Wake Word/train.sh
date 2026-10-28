#!/usr/bin/env bash
# Trains the BellAi wake word in WSL. Run setup.sh and download_data.sh first.
#
#   bash train.sh            # every step, in order
#   bash train.sh generate   # 1. synthetic Piper clips (target word + near misses)
#   bash train.sh import     # 2. copy your clips from custom_clips/ into the training folders
#   bash train.sh augment    # 3. add room echo + background noise, compute features
#   bash train.sh train      # 4. train, then save BellAi.onnx / BellAi.tflite
#   bash train.sh export     # 5. copy the finished model into Wake Word/models
#
# Every step can be re-run. Generation continues until the clip counts in bellai_model.yml are met,
# and augment always rebuilds the features so newly imported clips are included.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BELLAI_WW_DIR:-$HOME/bellai-wakeword}"
STEP="${1:-all}"

cd "$WORK_DIR"
source .venv/bin/activate

# Always train with the config from the repo so edits there are picked up
cp "$REPO_DIR/bellai_model.yml" "$WORK_DIR/bellai_model.yml"
CONFIG="$WORK_DIR/bellai_model.yml"
TRAIN="$WORK_DIR/openwakeword/openwakeword/train.py"
MODEL_NAME="$(python -c "import yaml; print(yaml.safe_load(open('$CONFIG'))['model_name'])")"
OUT_DIR="$(python -c "import os, yaml; print(os.path.abspath(yaml.safe_load(open('$CONFIG'))['output_dir']))")"

run_generate() { python "$TRAIN" --training_config "$CONFIG" --generate_clips; }
run_import()   { python "$REPO_DIR/import_clips.py" --clips "$REPO_DIR/custom_clips" --dest "$OUT_DIR/$MODEL_NAME"; }
run_augment()  { python "$TRAIN" --training_config "$CONFIG" --augment_clips --overwrite; }
run_train()    { python "$TRAIN" --training_config "$CONFIG" --train_model || echo "Training script exited with an error (often only the .tflite conversion). Checking for the .onnx..."; }
run_export() {
    if [ ! -f "$OUT_DIR/$MODEL_NAME.onnx" ]; then
        echo "No $MODEL_NAME.onnx in $OUT_DIR yet. Run: bash train.sh train"
        exit 1
    fi
    if [ ! -f "$OUT_DIR/$MODEL_NAME.tflite" ]; then
        python "$REPO_DIR/export_tflite.py" "$OUT_DIR/$MODEL_NAME.onnx" "$OUT_DIR/$MODEL_NAME.tflite" \
            || echo "TFLite conversion failed. The .onnx model still works on the Pi and iPhone."
    fi
    mkdir -p "$REPO_DIR/models"
    cp -v "$OUT_DIR/$MODEL_NAME.onnx" "$REPO_DIR/models/"
    [ -f "$OUT_DIR/$MODEL_NAME.tflite" ] && cp -v "$OUT_DIR/$MODEL_NAME.tflite" "$REPO_DIR/models/"
    # openWakeWord needs these two feature models next to the wake word model when it runs outside Python's package
    cp -v openwakeword/openwakeword/resources/models/melspectrogram.onnx "$REPO_DIR/models/"
    cp -v openwakeword/openwakeword/resources/models/embedding_model.onnx "$REPO_DIR/models/"
    echo "Model saved to: $REPO_DIR/models"
}

case "$STEP" in
    generate) run_generate ;;
    import)   run_import ;;
    augment)  run_augment ;;
    train)    run_train ;;
    export)   run_export ;;
    all)      run_generate; run_import; run_augment; run_train; run_export ;;
    *) echo "Unknown step '$STEP'. Use: generate, import, augment, train, export or all"; exit 1 ;;
esac
