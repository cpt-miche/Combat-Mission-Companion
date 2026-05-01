# QA Playtest Checklist — AI Debug Toggle & Logging (2026-05-01)

## Scope
This checklist validates the AI debug toggle behavior from the map scene, level-specific detail output, and regressions when debug is OFF.

## Preconditions
- Start from a fresh run on the map/mission flow.
- Ensure keyboard input is active in-game.
- Use a build/config where AI logging is enabled.
- If an AI log file already exists, note its current size/timestamp before test start.

## Exact Playtest Steps

### 1) Toggle ON from map
1. From the map screen, press `P`.
2. Confirm a debug prompt/confirmation appears.

**Expected:** Prompt appears immediately after pressing `P` from map.

### 2) Select detail level and verify UI indicator
1. In the prompt, select `L1`.
2. Confirm the top-right debug indicator is visible and reflects L1.
3. Repeat by selecting `L2`, then `L3`.

**Expected:** Top-right indicator updates to match selected level (`L1`/`L2`/`L3`) each time.

### 3) Toggle OFF and verify UI clears
1. Press `P` again while debug is ON.

**Expected:** Debug mode turns OFF and the top-right indicator hides.

### 4) Fog-of-war visibility gate
1. Observe fog-of-war while debug is OFF.
2. Turn debug ON (any level) and observe again.
3. Turn debug OFF and observe one more time.

**Expected:** Full fog-of-war visibility occurs only while debug is ON; normal fog behavior returns when OFF.

### 5) Enemy HP/status visibility gate
1. With debug OFF, inspect enemy units.
2. Turn debug ON and inspect same enemy units.
3. Turn debug OFF and inspect again.

**Expected:** Enemy HP/status visibility is only exposed while debug is ON.

### 6) AI log file creation and append behavior
1. Ensure debug is ON and run at least one AI turn.
2. Verify an AI log file is created (if missing) or appended (if existing).
3. Run one additional AI turn at a different level and verify additional appended content.

**Expected:**
- File exists after AI turn in debug mode.
- File grows/appends across turns (no destructive overwrite per turn).
- Content detail matches selected level (see sample expectations below).

## Sample Expectations: One AI Turn per Level

Use one representative AI turn per level and confirm the minimum content profile:

- **L1 (summary-only):**
  - One concise line summarizing what action was chosen.
  - Example shape: `AI Turn 12: Unit E-03 moved to (7,4) and attacked Scout-1.`

- **L2 (includes reasoning):**
  - Includes the chosen action plus a brief **why** explanation.
  - Example shape: `AI Turn 12: E-03 attacked Scout-1 because it had highest hit chance and secured objective pressure.`

- **L3 (scoring/weights):**
  - Includes action, alternatives, and numerical scoring/weights used to decide.
  - Example shape: `AI Turn 12: chose Attack Scout-1 (score=8.4; weights: hit_chance=0.5, objective=0.3, risk=0.2); alt MoveCover score=7.1.`

## Regression Checks (Debug OFF)

Run these with debug OFF before and after using debug mode once:

- Core turn flow remains normal (player input -> enemy turn -> return to player).
- No extra debug UI persists (indicator/prompt hidden unless explicitly toggled).
- Fog-of-war and enemy intel follow normal gameplay rules.
- No debug-only text/noise appears in standard combat/map UI.
- No gameplay balance/behavior changes are observable from merely toggling debug OFF.

## Pass/Fail Recording Template

- Build/commit tested:
- Map/mission tested:
- Debug levels tested: L1 / L2 / L3
- AI log file path:
- AI log append verified: Yes / No
- Regression checks (debug OFF): Pass / Fail
- Notes/screenshots:
