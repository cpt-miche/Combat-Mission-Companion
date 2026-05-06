#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

if ! command -v godot >/dev/null 2>&1; then
  echo "Godot was not found on PATH." >&2
  exit 1
fi

echo "Godot version:"
godot --version

echo "Importing project assets..."
godot --headless --path . --import

echo "Validating autoload singleton scripts first..."
for autoload_script in \
  "res://scripts/core/GameState.gd" \
  "res://scripts/core/DisplaySettings.gd"; do
  if ! godot --headless --path . --check-only --script "$autoload_script"; then
    echo "Autoload singleton failed to parse; downstream Identifier not found errors are secondary." >&2
    echo "Troubleshooting hint: verify [autoload] entries in project.godot point to valid script paths." >&2
    exit 1
  fi
done

echo "Loading all project scenes to expand parse coverage in project context..."
while IFS= read -r scene_path; do
  echo "Loading scene: ${scene_path}"
  godot --headless --path . --quit --scene "$scene_path"
done < <(find scenes -type f -name "*.tscn" | sort)

echo "Running headless project startup check..."
godot --headless --path . --quit

echo "Running main scene smoke test..."
godot --headless --path . --script ci/smoke_test.gd

echo "Running unit notation validation check..."
godot --headless --path . --script ci/unit_notation_check.gd

echo "Running gameplay AI service test..."
godot --headless --path . --scene tests/gameplay/GameplayAIServiceTest.tscn


if [ -f export_presets.cfg ]; then
  mkdir -p build

  if grep -q 'name="Linux/X11"' export_presets.cfg; then
    echo "Running Linux/X11 debug export..."
    godot --headless --path . --export-debug "Linux/X11" build/game.x86_64
  elif grep -q 'name="Linux"' export_presets.cfg; then
    echo "Running Linux debug export..."
    godot --headless --path . --export-debug "Linux" build/game.x86_64
  else
    echo "No Linux export preset found; skipping export test."
  fi
else
  echo "No export_presets.cfg found; skipping export test."
fi

echo "Godot checks passed."
