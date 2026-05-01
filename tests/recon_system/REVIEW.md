# Recon System Fixture Replay (2026-04-26)

This suite adds deterministic fixture/replay coverage for recon intel progression and contact lifecycle behavior.

## Replay utility
Use `scripts/tools/ReconFixtureReplay.gd`:
- `replay_fixture_file(path)` to run one fixture.
- `replay_fixture_dir("tests/recon_system/fixtures")` to run all fixtures.

## Coverage matrix

| Requirement | Fixture |
|---|---|
| Level floors (combat=1, recon=3) | `fixtures/floor_progression_and_cap.json` |
| Independent per-unit progression rolls | `fixtures/floor_progression_and_cap.json` (`progressionChecks`) |
| Multi-success same-turn increments | `fixtures/floor_progression_and_cap.json` (`progressionChecks.minGain=2`) |
| Scout level cap at 4 | `fixtures/floor_progression_and_cap.json` |
| Level 1/2/3/4 discovery behavior and visibility invariants | `fixtures/visibility_size_contact_lifecycle.json` |
| Size accuracy/clamp by scout level and wrong-size lock prevention | `fixtures/visibility_size_contact_lifecycle.json` |
| Size lock persistence while in contact | `fixtures/visibility_size_contact_lifecycle.json` |
| Contact-loss hard reset (hex + unit intel) and re-discovery after regain | `fixtures/visibility_size_contact_lifecycle.json` |
| RNG-seeded repeatability assertions | both fixtures (`deterministicChecks`) |

## Notes
- Assertions intentionally focus on deterministic invariants for each scout level so replay remains stable.
- Progression checks compare direct roll outcomes against a manual per-unit roll reconstruction using the same seed to guard deterministic and independent-roll behavior.
