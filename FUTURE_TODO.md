# Future UI/UX Backlog

This backlog records player-facing improvements that are ready for future implementation. Tasks are ordered by priority and dependency. Completing a task must preserve existing gameplay, controls, scenes, fog-of-war rules, and UI behavior unless the task explicitly changes them.

## P0 — Organization correctness

### [x] ORG-001 — Allow reinforced battalions

- Allow up to seven direct subordinate units under one parent.
- Allow up to six company-sized children while continuing to reject a seventh company.
- Keep nested descendants counted only against their immediate parent.

### [x] ORG-002 — Correct the US Infantry Battalion headquarters structure

- Keep five standard companies: Headquarters, three Rifle, and Heavy Weapons.
- Place the section-sized Battalion HQ and Antitank Platoon inside Headquarters Company.
- Remove the standalone Battalion Headquarters section and redundant Headquarters Company HQ section.
- Preserve the Company HQ sections belonging to Rifle and Heavy Weapons Companies.

### [x] ORG-003 — Instantiate higher formations from canonical lower-echelon templates

- Store USA and German formation composition as nation-local template references at every echelon.
- Make Infantry Regiments reuse the same canonical battalion structure available for direct creation.
- Reject missing, duplicate, cyclic, cross-nation, or inline template composition data.
- Keep internal definitions out of root deployment choices while preserving expanded runtime formations.

## P0 — Battle-resolution correctness and readability

### [x] BR-001 — Hide dead units from battle resolution

Dead units should not be shown as casualty choices because they cannot become casualties again.

Acceptance criteria:

- Exclude any unit for which `GameState.is_unit_alive()` is false from both casualty trees.
- Exclude dead engaged roots, dead parents, and dead descendants rather than showing them as disabled rows.
- Never allow a dead unit ID to be collected as a newly confirmed casualty.
- If filtering removes every unit from one side, show the existing appropriate empty-state message.
- Preserve living descendants when their dead parent is omitted, so eligible living units are not accidentally hidden.
- Add casualty-entry integration coverage for dead engaged units and mixed living/dead formation trees.
- Run `bash ci/godot_check.sh` and fix any failure.

### [x] BR-002 — Include unit type in battle-resolution labels

Battle-resolution entries should identify both the formation size and what kind of unit it is.

Acceptance criteria:

- Format each visible entry as `Name (ID) — Size — Type — Health`.
- Read type from the existing `unit_type` or `type` field and convert stored identifiers to player-readable text.
- Use `Unknown` when type data is absent rather than leaving an empty separator.
- Verify representative infantry, machine-gun, armor/tank, recon, and missing-type labels.
- Preserve the current hierarchy, checkboxes, casualty propagation, and health summaries.
- Add or update casualty-entry integration assertions for the new label content.
- Run `bash ci/godot_check.sh` and fix any failure.

## P1 — Map navigation

### [x] MAP-001 — Add deployment-map zoom

The deployment map should support mouse-wheel zoom without disrupting placement controls.

Acceptance criteria:

- Mouse-wheel input zooms the map in and out around the cursor position.
- Clamp zoom to practical minimum and maximum values so the map cannot disappear or become unusably large.
- Scale terrain, territory shading, unit markers, and labels together.
- Keep hex selection, unit placement, right-click undeployment, and pointer-to-hex conversion accurate at every zoom level.
- Preserve click-and-drag panning and prevent wheel input from triggering placement.
- Start each newly entered deployment screen at the default zoom.
- Add focused coverage for zoom clamping and coordinate conversion after combined pan and zoom.
- Run `bash ci/godot_check.sh` and fix any failure.

### [x] MAP-002 — Add gameplay-map zoom

The gameplay map should use the same zoom direction and interaction conventions as deployment.

Acceptance criteria:

- Mouse-wheel input zooms around the cursor and uses the same practical limits as the deployment map.
- Scale hexes, terrain, fog-of-war, unit markers, stacked-unit offsets, order arrows, and path previews together.
- Keep hex selection, unit marker picking, drag-to-move, attack targeting, and hover information accurate at every zoom level.
- Preserve click-and-drag panning and the current distinction between dragging a unit and dragging empty map space.
- Start each newly entered gameplay screen at the default zoom.
- Add focused coverage for zoom clamping, transformed hit testing, and order creation after combined pan and zoom.
- Run `bash ci/godot_check.sh` and fix any failure.

### [x] DEP-001 — Make the deployment sidebar resizable

Long unit names should be readable by widening the left deployment panel.

Acceptance criteria:

- Replace the fixed boundary between the unit tree and map with a draggable horizontal splitter.
- Allow the left panel to grow and shrink while preserving practical minimum widths for both the unit tree and map.
- Keep the right-side deployment controls visible and usable at supported window sizes and UI scales.
- Preserve unit-tree expansion, collapse, scrolling, selection, placement, and status messages while resizing.
- The pointer should visually indicate when the splitter can be dragged.
- Add deployment UI coverage for the resulting layout bounds and retained unit selection.
- Run `bash ci/godot_check.sh` and fix any failure.

## P1 — Stacked-unit selection and orders

### [x] GAME-001 — Replace selected-hex text with clickable unit cards

The selected-hex sidebar should make stacked units individually recognizable and selectable.

Acceptance criteria:

- Replace the plain unit-summary label with a scrollable vertical collection of compact cards.
- Each card shows the unit name, type, size, health, current status, and current order when present.
- Clicking a living friendly card makes that unit the primary active unit for details and orders.
- Clearly highlight selected cards and the primary active card.
- Show enemy units and recon contacts only to the detail level allowed by current recon and debug rules.
- Enemy/contact cards are read-only and cannot become actionable selections.
- Selecting a different hex clears the previous hex's unit selection and rebuilds the card list.
- Empty and no-contact hexes retain a clear empty state.
- Add gameplay UI coverage for card content, primary selection, enemy restrictions, fog-of-war safety, and selection clearing.
- Run `bash ci/godot_check.sh` and fix any failure.

### [x] GAME-002 — Add same-hex Shift-click multi-selection

Dependency: `GAME-001`.

Players should be able to order several friendly units from the same hex together.

Acceptance criteria:

- A normal card click clears the prior selection and selects only that living friendly unit.
- Shift-click adds or removes a living friendly unit from the current selected-hex group.
- The most recently clicked selected unit becomes the primary detail unit; if it is removed, promote another selected unit deterministically.
- Multi-selection is limited to the currently selected hex; changing hexes clears the group.
- Move, attack, and dig-in attempt to create an order for every selected eligible unit.
- Validate each selected unit independently. Keep successful orders, skip invalid ones, and report counts plus readable reasons for skipped units.
- A group move uses the same target hex for each unit but computes and validates each path independently, including stack limits.
- A group attack uses the same target for each eligible attacker. Dig-in applies independently to each eligible selected unit.
- Dead, enemy, hidden, or otherwise ineligible units cannot enter the actionable selection.
- Refresh cards, order highlights, map markers, the order panel, and autosave after group-order changes.
- Add gameplay integration coverage for Shift-toggle behavior, primary-unit promotion, selection clearing, each group order type, partial success, stack limits, and autosave contents.
- Run `bash ci/godot_check.sh` and fix any failure.

## P2 — In-map battle-resolution overlay

### [x] BR-003 — Show battle resolution over the gameplay map

Dependencies: `BR-001` and `BR-002`.

Battle resolution should retain visual context by appearing over the map instead of replacing gameplay with a gray screen.

Acceptance criteria:

- Present battle resolution as a full-screen modal layer above the current gameplay screen.
- Cover the gameplay screen with a slightly transparent dimming layer so the map remains recognizable.
- Freeze background panning, zooming, hex and unit selection, order controls, keyboard shortcuts, and end-turn input while the modal is open.
- Keep all battle-resolution controls fully opaque, readable, keyboard accessible, and above the input-blocking layer.
- Preserve multiple-battle progression, casualty confirmation, combat summary, status reconciliation, autosave behavior, and return to the next turn.
- Loading a save with pending casualty resolution must reconstruct the gameplay map and reopen the overlay at the saved battle or summary step.
- Closing the completed overlay restores gameplay input exactly once and does not duplicate signals or advance the turn twice.
- Add integration coverage for opening the overlay, blocking background input, advancing across multiple battles, restoring from a save, completing the summary, and restoring gameplay controls.
- Run `bash ci/godot_check.sh` and fix any failure.

## Implementation notes

- `GAME-002` follows `GAME-001` because multi-selection depends on interactive unit cards.
- `BR-003` follows the battle-tree correctness tasks because it changes how the existing casualty UI is hosted, not the casualty rules themselves.
- Deployment and gameplay zoom should feel consistent even though their current map drawing implementations are separate.
- Each implementation should remain small and focused; do not combine all backlog items into one change.
