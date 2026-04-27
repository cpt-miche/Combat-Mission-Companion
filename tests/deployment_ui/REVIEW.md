# Deployment UI Integration Coverage (2026-04-27)

This folder contains deployment-focused UI/domain integration checks for `DeploymentScreen`.

## Coverage
- Re-placing the same unit to another hex keeps a single deployment entry for that unit id.
- Occupied-hex placement still honors deployment validation constraints.
- Tree model initialization preserves parent-child hierarchy and defaults parents to collapsed.
- Non-deployable units remain blocked (`TreeItem.set_selectable(false)` path).
- `_on_finish_deployment_pressed` phase transitions remain intact after `ItemList` -> `Tree` migration.

## Suggested run command
```bash
godot4 --headless --path . --script res://tests/deployment_ui/DeploymentScreenIntegrationTest.gd
```
