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

echo "Checking GDScript parse errors..."
while IFS= read -r script_path; do
  project_script="res://${script_path#./}"
  if [[ "$project_script" == "res://scripts/core/GameState.gd" ]] || [[ "$project_script" == "res://scripts/core/DisplaySettings.gd" ]]; then
    continue
  fi
  godot --headless --path . --check-only --script "$project_script"
done < <(find . -type f -name "*.gd" -not -path "./.godot/*" | sort)

echo "Running headless project startup check..."
godot --headless --path . --quit

echo "Running main scene smoke test..."
godot --headless --path . --script ci/smoke_test.gd

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
