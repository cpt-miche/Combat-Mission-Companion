# Deployment UI Maintainer Notes

- **Why `Tree` over `ItemList`:** deployment units come from a command hierarchy and must support per-branch collapse/expand while preserving selection metadata. `ItemList` does not fit this interaction as well.
- **Selected unit state:** `DeploymentScreen.gd` stores current UI selection in `_selected_unit_id` and `_selected_unit_metadata`, both populated from the selected `TreeItem` metadata.
- **Placed-unit annotation:** labels like `"(Placed: x,y)"` are computed from `_deployment_coordinates_by_unit_id(deployments)` and applied while building tree rows.
- **Validator-aligned helpers:** keep `_unit_snapshot`, `_string_for_type`, `_string_for_size`, `_size_rank`, `_preferred_unit_name`, and `_preferred_short_name` aligned with `DeploymentValidator` contracts (`can_deploy_in_territory`, `placement_block_reason`).
- **Godot stable docs used for this UI widget:** [Tree](https://docs.godotengine.org/en/stable/classes/class_tree.html) and [TreeItem](https://docs.godotengine.org/en/stable/classes/class_treeitem.html).
