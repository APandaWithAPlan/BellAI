"""bella GGUF (f16, llama arch) -> mlx 4-bit orpheus, same layout as mlx-community/orpheus-3b-0.1-ft-4bit

usage: .venv/bin/python convert_bella.py bella_voice_f16.gguf models/bella-orpheus-4bit
       (add "check" as a third argument to only compare the weights to the stock model)
copy the gguf to the Mac's disk first, reading it from an exfat drive stalls
the stock 4-bit model must be in the huggingface cache (start the server once), it gives the layout and tokenizer"""
import glob
import json
import re
import shutil
import sys
from pathlib import Path

import mlx.core as mx

GGUF, OUT = sys.argv[1], Path(sys.argv[2])
TEMPLATE = Path(glob.glob(str(Path.home() / ".cache/huggingface/hub/models--mlx-community--orpheus-3b-0.1-ft-4bit/snapshots/*"))[0])
N_HEAD, N_KV = 24, 8

tmpl = mx.load(str(TEMPLATE / "model.safetensors"))
src = mx.load(GGUF)
print("template tensors", len(tmpl), "gguf tensors", len(src))

NAMES = {
    "attn_q": "self_attn.q_proj", "attn_k": "self_attn.k_proj", "attn_v": "self_attn.v_proj",
    "attn_output": "self_attn.o_proj", "ffn_gate": "mlp.gate_proj", "ffn_up": "mlp.up_proj",
    "ffn_down": "mlp.down_proj", "attn_norm": "input_layernorm", "ffn_norm": "post_attention_layernorm",
}


def unpermute(w, heads):
    # llama.cpp reorders q/k rows for its rope; undo that for the mlx/hf layout
    rows, cols = w.shape
    return w.reshape(heads, rows // heads // 2, 2, cols).swapaxes(1, 2).reshape(rows, cols)


def hf_name(k):
    if k == "token_embd.weight":
        return "model.embed_tokens.weight"
    if k == "output_norm.weight":
        return "model.norm.weight"
    m = re.fullmatch(r"blk\.(\d+)\.(\w+)\.weight", k)
    if m and m.group(2) in NAMES:
        return f"model.layers.{m.group(1)}.{NAMES[m.group(2)]}.weight"
    return None


weights = {}
for k, v in src.items():
    n = hf_name(k)
    if n is None:
        print("skipping", k)
        continue
    if n.endswith("q_proj.weight"):
        v = unpermute(v, N_HEAD)
    elif n.endswith("k_proj.weight"):
        v = unpermute(v, N_KV)
    weights[n] = v
if "lm_head.weight" in tmpl:
    raise SystemExit("template has lm_head; unexpected")

# sanity: the finetune should stay close to the template's weights, a wrong row order would not
def cos(a, b):
    a, b = a.astype(mx.float32).reshape(-1), b.astype(mx.float32).reshape(-1)
    return (mx.sum(a * b) / (mx.linalg.norm(a) * mx.linalg.norm(b))).item()


def template_weight(name):
    base = name[: -len(".weight")]
    return mx.dequantize(tmpl[name], tmpl[base + ".scales"], tmpl[base + ".biases"], group_size=64, bits=4)


for name in ["model.layers.0.self_attn.q_proj.weight", "model.layers.0.self_attn.k_proj.weight",
             "model.layers.5.self_attn.v_proj.weight", "model.layers.5.mlp.up_proj.weight",
             "model.embed_tokens.weight"]:
    print(name, "cosine to template", round(cos(weights[name], template_weight(name)), 4))
if len(sys.argv) > 3 and sys.argv[3] == "check":
    raise SystemExit

out = {}
for k, t in tmpl.items():
    if k.endswith(".scales") or k.endswith(".biases"):
        continue
    base = k[: -len(".weight")] if k.endswith(".weight") else None
    if base and base + ".scales" in tmpl:
        q, s, b = mx.quantize(weights[k].astype(mx.float32), group_size=64, bits=4)
        out[k], out[base + ".scales"], out[base + ".biases"] = q, s.astype(tmpl[base + ".scales"].dtype), b.astype(tmpl[base + ".biases"].dtype)
    else:
        out[k] = weights[k].astype(t.dtype)
missing = set(tmpl) - set(out)
assert not missing, missing
OUT.mkdir(parents=True, exist_ok=True)
mx.save_safetensors(str(OUT / "model.safetensors"), out, metadata={"format": "mlx"})
for f in ["config.json", "tokenizer.json", "tokenizer_config.json", "special_tokens_map.json"]:
    shutil.copyfile(TEMPLATE / f, OUT / f)
print("wrote", OUT, len(out), "tensors")
