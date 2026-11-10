#!/usr/bin/env python3
"""Local CPU Piper Czech TTS for Life Simulator. No third-party network service at inference.
Required: pip install piper-tts==1.3.0
Model files are provisioned separately into /app/library/lifesim/neural_models.
"""
import argparse
import os
import pathlib
import sys
import tempfile
import wave

MODELS = {
    "kasandra": "cs_CZ-kasandra-medium.onnx",
    "jirka": "cs_CZ-jirka-medium.onnx",
}
DEFAULT_MODELS = "/app/library/lifesim/neural_models"

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--speaker", choices=MODELS, required=True)
    parser.add_argument("--text", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--models-dir", default=os.environ.get("LIFESIM_PIPER_MODEL_DIR", DEFAULT_MODELS))
    parser.add_argument("--length-scale", type=float, default=1.0)
    parser.add_argument("--noise-scale", type=float, default=0.667)
    args = parser.parse_args()
    text = args.text.strip()[:200]
    if not text:
        print("Empty phrase", file=sys.stderr)
        return 2
    model_path = pathlib.Path(args.models_dir).joinpath(MODELS[args.speaker])
    config_path = pathlib.Path(str(model_path) + ".json")
    if not model_path.is_file() or not config_path.is_file():
        print("Piper model missing: " + str(model_path), file=sys.stderr)
        return 3
    # Only a bounded tempo modification; original game 'resonance' and 'timbre'
    # sliders are NOT equivalent to neural speaker embedding / vocal tract edits.
    from piper import PiperVoice
    from piper.config import SynthesisConfig

    voice = PiperVoice.load(str(model_path), config_path=str(config_path))
    cfg = SynthesisConfig(
        length_scale=max(0.75, min(1.4, args.length_scale)),
        noise_scale=max(0.4, min(1.0, args.noise_scale)),
        noise_w_scale=0.8,
    )
    dest = pathlib.Path(args.output)
    dest.parent.mkdir(parents=True, exist_ok=True)
    # Atomic replace avoids publishing truncated audio; caller's SHA256 output path
    # is used as a reusable per-text cache key.
    tmp = tempfile.NamedTemporaryFile(prefix="piper_", suffix=".wav", dir=dest.parent, delete=False)
    try:
        with tmp:
            with wave.open(tmp, "wb") as wf:
                voice.synthesize_wav(text, wf, syn_config=cfg)
        with wave.open(tmp.name, "rb") as wf:
            if wf.getnframes() < 1000 or wf.getnchannels() != 1 or wf.getsampwidth() != 2:
                print("Invalid Piper WAV output", file=sys.stderr)
                return 4
        os.replace(tmp.name, dest)
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
