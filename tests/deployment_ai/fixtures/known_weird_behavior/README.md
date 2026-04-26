# Known Weird Behavior Regression Traces

Store trace dumps that intentionally preserve currently accepted-but-odd behavior.

## Naming convention
- File name format: `YYYY-MM-DD_<phase>_<slug>.trace.json`
- Example: `2026-04-26_deployment_ai_sanity_stage_reason_wording.trace.json`

## Required metadata block
Each trace JSON should include:
- `regression_case_id`: stable ID used by CI and replay scripts.
- `known_weird_behavior`: short description of what is odd but currently accepted.
- `expected_to_match`: list of fields that must remain stable (`events`, `orders`, `score_windows`).
- `allowed_drift`: list of fields allowed to differ with rationale.

## Lifecycle
1. Add trace when behavior is intentionally accepted.
2. Reference `regression_case_id` from fixture `expected.eventAssertions.known_weird_behavior`.
3. Remove trace after behavior is fixed and tests are updated to the new expected output.
