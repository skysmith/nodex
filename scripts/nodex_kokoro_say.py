#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import soundfile as sf
from kokoro_onnx import Kokoro


def main() -> None:
    parser = argparse.ArgumentParser(description="Render a short Nodex prompt with Kokoro ONNX.")
    parser.add_argument("--model", required=True, help="Path to kokoro-v1.0.onnx")
    parser.add_argument("--voices", required=True, help="Path to voices-v1.0.bin")
    parser.add_argument("--voice", default="af_sarah", help="Kokoro voice name")
    parser.add_argument("--speed", type=float, default=1.0, help="Speech speed")
    parser.add_argument("--output", required=True, help="Output WAV path")
    args = parser.parse_args()

    text = sys.stdin.read().strip()
    if not text:
        raise SystemExit("text is required on stdin")

    kokoro = Kokoro(args.model, args.voices)
    samples, sample_rate = kokoro.create(text, voice=args.voice, speed=args.speed, lang="en-us")
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(output_path, samples, sample_rate)


if __name__ == "__main__":
    main()
