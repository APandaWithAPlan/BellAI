"""Converts the trained BellAi .onnx model to .tflite (same as step 4 of the training notebook).

Only needed if the training step finished the .onnx but the .tflite conversion failed.
Usage: python export_tflite.py BellAi.onnx BellAi.tflite
"""
import os
import sys
import tempfile

import onnx
import tensorflow as tf
from onnx_tf.backend import prepare

onnx_path, tflite_path = sys.argv[1], sys.argv[2]
tf_rep = prepare(onnx.load(onnx_path), device="CPU")
with tempfile.TemporaryDirectory() as tmp:
    tf_rep.export_graph(os.path.join(tmp, "tf_model"))
    tflite_model = tf.lite.TFLiteConverter.from_saved_model(os.path.join(tmp, "tf_model")).convert()
with open(tflite_path, "wb") as f:
    f.write(tflite_model)
print("Saved", tflite_path)
