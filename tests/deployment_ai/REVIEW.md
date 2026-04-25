# Deployment AI Deterministic Fixtures (2026-04-25)

These fixtures are intentionally lightweight and deterministic, so they can be consumed by a future automated runner or replayed manually in a local Godot session.

## How to replay manually
1. Set `GameState.players[player_index]["controller"] = "ai"`.
2. Load a fixture payload from `tests/deployment_ai/fixtures/*.json` into `GameState` and planner inputs.
3. Run `DeploymentAIService.run_for_player(player_index)`.
4. Validate that `GameState.players[player_index]["deployments"]` and `GameState.deployment_ai_debug` satisfy each fixture's `expected` section.

## Fixture coverage matrix (critical PRP criteria)
- **Objective modes**: `attack_only_objective.json`, `defense_only_objective.json`, `mixed_objective.json`
- **Wide-front split behavior**: `wide_front_split.json`
- **Artillery range coverage**: `artillery_coverage.json`
- **Reserve anti-clumping**: `reserve_anti_clumping.json`
- **Sanity repair triggers**: `sanity_repair_triggers.json`

Each file includes:
- Deterministic `elements`, `hexes`, and `sectorModel`
- Planner `options`
- `expected` acceptance assertions for regression prevention
