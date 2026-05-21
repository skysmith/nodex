---
name: nodex-interview
description: Use when a Codex session should work in silent yes/no interview mode with the local Nodex AirPods helper. Codex should ask one binary question at a time through `nodex ask`, continue from the yes/no result, and avoid open-ended user prompts.
---

# Nodex Interview Mode

Use this skill when Codex should keep working while the user answers only yes/no questions, often through AirPods head gestures.

## Contract

- Ask exactly one binary question at a time.
- Phrase each question so `yes` and `no` are both clear.
- Do not ask open-ended questions while in this mode.
- Prefer continuing with a conservative default over asking low-value questions.
- If a question is necessary, call the local helper:

```bash
nodex ask "QUESTION?" --log
```

Use `--no-say` only when the user explicitly wants silent on-screen prompts instead of spoken prompts.

If logging would expose sensitive details, omit `--log`.

If `nodex` is not on PATH, ask the user to add the checkout's `bin/` directory to PATH or provide the full path to `bin/nodex`.

## Interpreting Results

- Exit code `0` means yes.
- Exit code `1` means no.
- Exit code `2` means timeout. Treat this as no for risky actions and as the safest conservative default for ordinary workflow choices.
- For ordinary optional work where no answer means skip, add `--default no`.

## Safety

Never use Nodex head gestures as the only approval for destructive, live production, customer-facing, financial, email, remote-server, secret-bearing, or irreversible actions. For those, require typed confirmation.

## Good Questions

- "Should I run the focused test now?"
- "Should I preserve the current UI exactly?"
- "Should I skip the optional refactor?"

## Bad Questions

- "What should I do next?"
- "Which design do you prefer?"
- "Should I do the risky thing?" without naming the risk clearly.
