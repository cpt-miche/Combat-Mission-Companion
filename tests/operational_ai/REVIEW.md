# Operational AI Fixture Review (2026-04-26)

This folder adds deterministic replay fixtures for the 8 PRP operational testing requirements.

## Replay utility
Use `scripts/tools/OperationalAssessmentReplay.gd` to replay one fixture (`replay_fixture_file`) or all fixtures in this directory (`replay_fixture_dir`).

The replay validates:
- Map-level frontline extraction via `OperationalMapAnalyzer`
- Operational assessment outputs via `OperationalEvaluator`
- Scoring delta checks via `OperationalScoringModel`
- Deterministic order assertions for list outputs to guard against flaky ordering regressions

## Fixture coverage matrix

| Requirement | Fixture |
|---|---|
| Frontline detection | `fixtures/frontline_detection.json` |
| Breakthrough severity + reserve request | `fixtures/breakthrough_severity_and_reserve_request.json` |
| Quiet donor legality checks | `fixtures/quiet_donor_legality_checks.json` |
| Reserve clumping warning | `fixtures/reserve_clumping_warning.json` |
| Scout intel pressure boost | `fixtures/scout_intel_pressure_boost.json` |
| Recon request on uncertain critical sectors | `fixtures/recon_request_uncertain_critical_sector.json` |
| Counterattack opportunity for exposed salient | `fixtures/counterattack_exposed_salient.json` |
| Artillery support warning on high-danger sector | `fixtures/artillery_support_warning_high_danger.json` |

## Determinism policy
Each fixture includes `expected.deterministicSortAssertions` with explicit expected ordering for the relevant output collection(s). These are intended to fail fast if sorting behavior changes.
