# AGENTS.md

## Project

This is a personal Godot 4.7 game project.

The user is not reviewing code manually. The user will playtest the game and report visible bugs, crashes, logs, and screenshots.

## Development-stage compatibility

- This game is in an early graybox phase. Backward compatibility for persisted data is a non-factor unless the user explicitly requests it.
- This applies to current-game saves, maps, scenarios, division templates, settings, AI debug traces, and AI debug indexes.
- Do not spend context or implementation effort on migrations, legacy readers, dual-format writes, compatibility fallbacks, or compatibility-only tests.
- Prefer the simplest correct current schema. Persisted files from older builds may be deleted and recreated after schema changes.
- Current-build serialization and round-trip reliability must still be tested.

## Required workflow

- Work agentically: inspect the repo, make the change, run checks, fix failures, and summarize the result.
- Never run the Godot GUI in Codex or CI. Always use `--headless`.
- After changing `.gd`, `.tscn`, `.tres`, `project.godot`, or `export_presets.cfg`, run:

  `bash ci/godot_check.sh`

- If the check fails, fix the issue and rerun the check.
- Do not remove existing gameplay, controls, scenes, or UI unless explicitly asked.
- Keep changes small and focused.
- Prefer fixing the actual cause over hiding errors.
- In PR summaries, include:
  - what changed
  - files changed
  - the Godot check result
  - what the user should playtest

## Review guidelines

- Treat failing `bash ci/godot_check.sh` as a serious issue.
- Flag removed gameplay behavior unless the user explicitly requested it.
- Flag changes that make the game harder to playtest.
