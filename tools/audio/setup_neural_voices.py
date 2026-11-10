#!/usr/bin/env python3
"""One-time provisioner for Life Simulator native neural voice (Piper CPU).
Usage: python3 tools/audio/setup_neural_voices.py --install-deps
Downloads ~127 MB to a persistent, separate model-library directory, not to the
web game export. The models have their own cards/licenses on Hugging Face.
"""
from __future__ import annotations
import argparse
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import urllib.request

MODEL_ROOT = "https://huggingface.co/rhasspy/piper-voices/resolve/main/cs/cs_CZ"
MODELS = {
    "kasandra": ("cs_CZ-kasandra-medium.onnx", 63511038),
    "jirka": ("cs_CZ-jirka-medium.onnx", 63201294),
}
DEFAULT_DIR = "/app/library/lifesim/neural_models"

def install(root: Path) -> None:
    root.mkdir(parents=True, exist_ok=True)
    for speaker, (filename, size) in MODELS.items():
        src = MODEL_ROOT + f"/{speaker}/medium/{filename}"
        for extra, expected in (("", size), (".json", 0)):
            dest = root / (filename + extra)
            if dest.is_file() and dest.stat().st_size > (size - 1024 if not extra else 1000):
                print("Ready:", dest.name, dest.stat().st_size, flush=True)
                continue
            tmp = root / (filename + extra + ".part")
            try:
                with urllib.request.urlopen(src + extra + "?download=true", timeout=90) as response, tmp.open("wb") as out:
                    while True:
                        piece = response.read(1024 * 1024)
                        if not piece:
                            break
                        out.write(piece)
                length = tmp.stat().st_size
                if (not extra and length != expected) or (extra and length < 1000):
                    raise ValueError(f"Invalid voice file size for {filename}{extra}: {length}")
                tmp.replace(dest)
                print("Downloaded:", dest.name, length, flush=True)
            finally:
                tmp.unlink(missing_ok=True)

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--install-deps", action="store_true")
    ap.add_argument("--models-dir", default=os.environ.get("LIFESIM_PIPER_MODEL_DIR", DEFAULT_DIR))
    args = ap.parse_args()
    if args.install_deps and importlib.util.find_spec("piper") is None:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "piper-tts==1.3.0"])
    if importlib.util.find_spec("piper") is None:
        ap.error("Piper not installed; run with --install-deps")
    install(Path(args.models_dir))
