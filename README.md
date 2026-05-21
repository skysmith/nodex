# Nodex

Answer AI-agent yes/no prompts with AirPods head gestures.

Nodex is a tiny macOS CLI for hands-light agent control. It asks one binary question, reads it aloud with `say`, then waits for a nod, shake, AirPods squeeze/media key, or keyboard fallback. The point is simple: when an agent is working and only needs a small decision, you should not have to speak, unlock your phone, or walk back to your keyboard.

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

## Quick Start

```bash
git clone https://github.com/skysmith/nodex.git
cd nodex
swift test
bin/nodex doctor
bin/nodex ask "Does Nodex work?"
```

The wrapper at `bin/nodex` builds the release binary on first use.

To put Nodex on your PATH for the current shell:

```bash
export PATH="$PWD/bin:$PATH"
nodex ask "Should I keep going?"
```

## Try The Hardware Path

Wear your AirPods, connect them to your Mac, then run:

```bash
bin/nodex doctor
bin/nodex ask "Does nodding mean yes?" --debug --timeout 25
bin/nodex calibrate
```

If gestures time out, try a more sensitive pass:

```bash
bin/nodex calibrate --nod-threshold 0.20 --shake-threshold 0.28
```

If normal head motion triggers false positives, try stricter thresholds:

```bash
bin/nodex calibrate --nod-threshold 0.32 --shake-threshold 0.42
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

The skill assumes `nodex` is on PATH.

## Safety

Use head gestures only for low-risk binary choices. Do not use Nodex as the only approval path for destructive, production, customer-facing, financial, email, remote-server, secret-bearing, or irreversible actions. Require typed confirmation for those.

## Development

```bash
swift build
swift test
swift build -c release
```

## License

MIT
