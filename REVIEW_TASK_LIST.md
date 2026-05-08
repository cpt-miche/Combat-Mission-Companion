# Comprehensive Review Task List

Use this task list to review the project areas from the comprehensive code review plan. Each task is written for bug hunting and UX validation because the primary reviewer is expected to playtest visible behavior rather than manually inspect every code diff.

## Review standards for every area

For each section below:

- [ ] Run the relevant screen or flow in Godot headless-compatible checks where possible; never use the Godot GUI in automation.
- [ ] Look for crashes, Godot errors, warnings, missing resources, invalid node paths, and broken signal callbacks.
- [ ] Bug hunt edge cases, not just happy paths: empty data, invalid selections, back/forward navigation, repeated button presses, reloads, and cancelled flows.
- [ ] Validate UX design: the player should understand what happened, what to do next, and how to recover from invalid input.
- [ ] Confirm existing gameplay, controls, scenes, and UI were not removed or bypassed.
- [ ] Record findings with severity, reproduction steps, expected result, actual result, affected files, screenshots/logs when available, and a concise fix task.

## 1. Repository orientation

- [ ] Identify the main project entry points: `project.godot`, the configured main scene, and startup scripts.
- [ ] Map the current folder responsibilities for `scenes/`, `scripts/`, `ui/`, `data/`, `tests/`, and `ci/`.
- [ ] Check whether duplicate or legacy scene/script locations still exist and whether they are intentionally retained.
- [ ] Bug hunt stale file references, orphaned assets, unused duplicate screens, and mismatched naming.
- [ ] UX validation: confirm a playtester can start the intended game flow without knowing repository internals.

## 2. Godot project configuration

- [ ] Review `project.godot` for the main scene, autoloads, display settings, input map, and registered script classes.
- [ ] Verify every autoload path exists and its script initializes without errors.
- [ ] Compare input actions in code against input actions defined in project settings.
- [ ] Bug hunt missing resources, stale scene paths, invalid input actions, and startup-time warnings.
- [ ] UX validation: confirm startup, window sizing, and controls support straightforward playtesting.

## 3. Scene/script consistency

- [ ] Review every `.tscn` file against its attached `.gd` script.
- [ ] Verify node paths referenced by scripts still exist in their scenes.
- [ ] Check connected signals point to existing methods with compatible signatures.
- [ ] Inspect exported variables for unset required references or missing resources.
- [ ] Bug hunt renamed nodes, deleted callbacks, broken packed scenes, and scene inheritance problems.
- [ ] UX validation: confirm visible UI elements match the interactions the scripts expect.

## 4. Gameplay flow

- [ ] Trace the full player-facing flow: main menu, map setup, division builder, deployment, gameplay, casualty entry, turn resolution, and combat log.
- [ ] Test forward navigation, back navigation, cancelled actions, and repeated start/new-game attempts.
- [ ] Confirm state is preserved when expected and reset when starting a fresh game.
- [ ] Bug hunt unreachable screens, hidden assumptions between phases, lost selections, and duplicate state mutation.
- [ ] UX validation: confirm every screen clearly communicates the current phase, available actions, disabled-action reasons, and next step.

## 5. Core game state

- [ ] Review game-state reset, new-game initialization, save/load boundaries, rules access, and catalog lookups.
- [ ] Verify mutable state is not accidentally shared between sessions, units, templates, maps, or saves.
- [ ] Exercise save/load with default, partially configured, and post-turn states.
- [ ] Bug hunt invalid defaults, missing catalog IDs, dictionary key assumptions, and silent failure paths.
- [ ] UX validation: confirm player-facing state after save/load or restart is coherent and recoverable.

## 6. Domain model and validation

- [ ] Review unit templates, map data, unit organization rules, deployment constraints, and notation formatting.
- [ ] Validate representative unit compositions across sides, sizes, veterancy values, and equipment assumptions.
- [ ] Test invalid or incomplete inputs where UI allows player configuration.
- [ ] Bug hunt null IDs, malformed templates, inconsistent enums/strings, and invalid organization states.
- [ ] UX validation: confirm validation errors explain exactly what the player must fix.

## 7. Deployment AI

- [ ] Review deployment scoring, placement legality, formation decomposition, terrain assumptions, and replay/debug tools.
- [ ] Test maps with constrained terrain, no obvious legal placement, unusual unit counts, and repeated AI deployment.
- [ ] Verify deployment results are deterministic when intended and logged well enough to reproduce failures.
- [ ] Bug hunt illegal placements, overlapping units, out-of-bounds coordinates, and no-placement crashes.
- [ ] UX validation: confirm AI deployment progress and failures are visible enough for playtest reporting.

## 8. Operational and gameplay AI

- [ ] Review AI turn selection, order generation, recon usage, pathfinding integration, and destroyed/routed unit handling.
- [ ] Test AI behavior with limited visibility, blocked routes, weak units, destroyed units, and objective pressure.
- [ ] Verify AI decisions generate legal orders and do not mutate player-only state incorrectly.
- [ ] Bug hunt invalid orders, infinite loops, stuck AI turns, target selection errors, and non-deterministic unreproducible crashes.
- [ ] UX validation: confirm AI turns provide enough visible feedback that the player understands what occurred.

## 9. Turn resolution and combat

- [ ] Review order validation, movement legality, combat resolution, casualty application, recon updates, and combat log entries.
- [ ] Test empty orders, impossible moves, repeated resolve actions, destroyed targets, and post-combat cleanup.
- [ ] Confirm combat logs match actual state changes and do not omit important outcomes.
- [ ] Bug hunt array bounds errors, dictionary missing keys, double-application of casualties, and stale pathfinding data.
- [ ] UX validation: confirm combat results are readable, actionable, and consistent with map/unit visuals.

## 10. UI and playtestability

- [ ] Review main menu, map setup, division builder, deployment UI, gameplay UI, casualty entry, phase header, and debug modals.
- [ ] Test button states, keyboard/mouse controls, error banners, dialogs, scrolling panels, resizing, and recovery actions.
- [ ] Confirm debug controls do not leak information or UI noise when disabled.
- [ ] Bug hunt invisible controls, blocked clicks, stale labels, modal focus traps, and screen layout overflow.
- [ ] UX validation: confirm the interface makes valid actions obvious and invalid actions understandable.

## 11. Test coverage

- [ ] Review tests under `tests/` plus `ci/smoke_test.gd`, `ci/unit_notation_check.gd`, and `ci/godot_check.sh`.
- [ ] Map each major gameplay flow to at least one automated or documented playtest check.
- [ ] Identify critical happy paths and edge cases that lack smoke coverage.
- [ ] Bug hunt brittle tests, tests that only assert no crash, and tests that miss visible UI outcomes.
- [ ] UX validation: ensure automated checks support confidence in playtestability, not just internal implementation details.

## 12. Static risk scan

- [ ] Search for `TODO`, `FIXME`, `HACK`, `push_error`, `printerr`, `assert`, `pass`, and hardcoded scene/resource paths.
- [ ] Search for direct node lookups and dictionary/array access patterns that may need guards.
- [ ] Review any high-risk findings in context before filing bugs so intentional code is not misclassified.
- [ ] Bug hunt crash-prone assumptions, hidden debug leftovers, and duplicated constants/defaults.
- [ ] UX validation: connect each risk to whether it can produce a visible crash, confusing behavior, or blocked playtest.

## 13. Finding report format

For every confirmed issue, file it with this structure:

```markdown
## [Severity] Short issue title

- Area:
- Why it matters to playtesting:
- Evidence:
- Reproduction steps:
- Expected result:
- Actual result:
- Affected files:
- Suggested fix:

:::task-stub{title="Concise fix summary"}
Step-by-step implementation instructions.
:::
```

## 14. Required checks after fixes

- [ ] After changing `.gd`, `.tscn`, `.tres`, `project.godot`, or `export_presets.cfg`, run `bash ci/godot_check.sh`.
- [ ] Treat any failure from `bash ci/godot_check.sh` as a serious issue and fix the root cause before review completion.
- [ ] For documentation-only review updates, still record whether `bash ci/godot_check.sh` was run or intentionally skipped.
- [ ] If a visible runnable web or game UI change is made, capture evidence appropriate to the environment and include what the user should playtest.

## Review completion checklist

- [ ] All sections above have been reviewed or explicitly marked out of scope.
- [ ] All blocker/high findings include reproduction steps and a fix task.
- [ ] UX issues distinguish between cosmetic polish and playtest-blocking confusion.
- [ ] Bug hunting included at least one edge-case pass for each major gameplay flow.
- [ ] Final summary tells the user exactly what changed, what was checked, and what to playtest next.
