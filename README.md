# Nodex

Answer AI-agent yes/no prompts with AirPods head gestures.

Nodex is a tiny macOS CLI for hands-light agent control. It asks one binary question, reads it aloud with macOS `say` or optional Kokoro TTS, then waits for a nod, shake, AirPods squeeze/media key, or keyboard fallback. The point is simple: when an agent is working and only needs a small decision, you should not have to speak, unlock your phone, or walk back to your keyboard.

```bash
nodex ask "Should Codex run the focused tests?"
```

Mapping:

- nod = yes
- shake = no
- single AirPods squeeze/media play-pause = yes, when macOS exposes it
- double/triple squeeze/media skip = no, when macOS exposes it
- keyboard `y/n` = reliable fallback

## Status

This is an MVP/prototype. The CLI, keyboard fallback, config, logging, and tests are working. AirPods motion support depends on your macOS version, headphone model, permissions, and calibration. Treat gesture answers as low-risk workflow input, not approval for destructive or sensitive actions.

## Requirements

- macOS 14 or newer
- Swift 5.9+ / Xcode Command Line Tools
- Motion-capable Apple headphones for head gestures, such as recent AirPods models
- Motion/Fitness permission granted on first run
- Optional: Python 3 plus Kokoro ONNX assets for `--voice kokoro`

## Quick Start

```bash
git clone https://github.com/skysmith/nodex.git
cd nodex
swift test
bin/nodex doctor
bin/nodex ask "Does Nodex work?"
```

The wrapper at `bin/nodex` builds the release binary on first use.

For AirPods head-motion input on macOS, use `bin/nodex-motion`. It launches Nodex through a tiny signed `.app` wrapper because macOS privacy services require a LaunchServices app identity for headphone motion.

```bash
bin/nodex-motion ask "Should I keep going?" --motion-only
```

`bin/nodex-motion` speaks a short acknowledgement like "I heard yes" or "I heard no" before it exits, so an agent cannot continue until you know Nodex heard you. Use `--no-confirm` to disable that.

## Install

For a local install, run:

```bash
./install.sh
```

This builds the release binary and symlinks the wrappers into `~/.local/bin`:

```bash
nodex doctor
nodex-motion ask "Should I keep going?" --motion-only
```

Use `PREFIX` or `BINDIR` to choose another destination:

```bash
PREFIX=/opt/homebrew ./install.sh
BINDIR="$HOME/bin" ./install.sh
```

To put Nodex on your PATH for the current shell:

```bash
export PATH="$PWD/bin:$PATH"
nodex ask "Should I keep going?"
```

## Optional Kokoro Voice

Nodex uses macOS `say` by default because it works everywhere. To use Kokoro for warmer local prompts, install the optional Python dependencies and place the ONNX model assets under `~/.nodex/kokoro`.

```bash
python3 -m venv .venv-kokoro
. .venv-kokoro/bin/activate
pip install -r requirements-kokoro.txt

mkdir -p ~/.nodex/kokoro
# Put these files in ~/.nodex/kokoro:
#   kokoro-v1.0.onnx
#   voices-v1.0.bin
```

The model files are distributed separately by the Kokoro ONNX project. See the [`kokoro-onnx` releases](https://github.com/thewh1teagle/kokoro-onnx/releases) and package docs for current download options.

Then run:

```bash
export NODEX_KOKORO_PYTHON="$PWD/.venv-kokoro/bin/python"
bin/nodex ask "Should I keep going?" --voice kokoro
```

Useful options and environment variables:

```bash
bin/nodex ask "Should I run the tests?" --voice kokoro --kokoro-voice af_sarah --kokoro-speed 1.05

export NODEX_KOKORO_MODEL="$HOME/.nodex/kokoro/kokoro-v1.0.onnx"
export NODEX_KOKORO_VOICES="$HOME/.nodex/kokoro/voices-v1.0.bin"
export NODEX_KOKORO_VOICE="af_sarah"
export NODEX_KOKORO_SPEED="1.0"
```

If Kokoro is requested but not configured, Nodex prints the missing path and falls back to macOS `say`.

## Try The Hardware Path

Wear your AirPods, connect them to your Mac, then run:

```bash
bin/nodex doctor
bin/nodex-motion ask "Does nodding mean yes?" --motion-only --debug --timeout 25
bin/nodex-motion ask "Does shaking mean no?" --motion-only --debug --timeout 25
```

If gestures time out, try a more sensitive pass:

```bash
bin/nodex-motion ask "Nod yes now." --motion-only --nod-threshold 0.20 --shake-threshold 0.28
```

If normal head motion triggers false positives, try stricter thresholds:

```bash
bin/nodex-motion ask "Nod yes now." --motion-only --nod-threshold 0.32 --shake-threshold 0.42
```

## Config

Create a default config:

```bash
bin/nodex config init
```

The config lives at `~/.nodex/config.json`:

```json
{
  "defaultTimeout": 25,
  "sayQuestions": true,
  "defaultLogPath": "~/.nodex/events.jsonl",
  "motion": {
    "nodThreshold": 0.26,
    "shakeThreshold": 0.34,
    "window": 1.45,
    "warmup": 0.65
  }
}
```

## Logging And Timeouts

Add `--log` to append one JSON line per question/result to `~/.nodex/events.jsonl`:

```bash
bin/nodex ask "Should I keep going?" --log
```

For head gestures, prefer:

```bash
bin/nodex-motion ask "Should I keep going?" --motion-only
```

For keyboard or script usage, add `--confirm` when you also want a spoken acknowledgement:

```bash
bin/nodex ask "Should I keep going?" --keyboard-only --confirm
```

Use `--default no` or `--default yes` when a timeout should map to a concrete answer:

```bash
bin/nodex ask "Should I run the slow suite?" --timeout 20 --default no
```

Exit codes:

- `0` = yes
- `1` = no
- `2` = timeout
- `64` = usage/config error

## Codex Interview Mode

The repo includes a starter Codex skill at `codex-skill/nodex-interview/SKILL.md`.

Install it locally:

```bash
mkdir -p ~/.codex/skills/nodex-interview
cp codex-skill/nodex-interview/SKILL.md ~/.codex/skills/nodex-interview/SKILL.md
```

Then start a Codex session with a prompt like:

```text
Use nodex-interview mode. Work on this task, and when you need me, ask yes/no questions through Nodex because I will not type.
```

The skill assumes `nodex` and `nodex-motion` are on PATH.

## Safety

Use head gestures only for low-risk binary choices. Do not use Nodex as the only approval path for destructive, production, customer-facing, financial, email, remote-server, secret-bearing, or irreversible actions. Require typed confirmation for those.

## Development

```bash
swift build
swift test
swift build -c release
bash -n bin/nodex bin/nodex-motion install.sh
```

## License

MIT
