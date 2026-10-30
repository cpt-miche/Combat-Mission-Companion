# Scenarios

This directory is the single source of truth for completed scenarios.

Validated scenario-version-3 JSON files placed here automatically appear in the in-game Scenario Library. The scenario editor creates, updates, renames, imports, and deletes files in this directory directly. Incomplete drafts remain under `user://scenario_drafts` and do not appear in the library.

## Ardennes Crossroads

`Ardennes_Crossroads.json` is a fictional December 1944 starter mission on an 8×8 map. Nine American rifle platoons advance from the west against nine German grenadier platoons holding a village crossroads. Each side has three companies under a battalion, with eight platoons spread across all eight rows and one platoon behind them as a reserve. Each platoon occupies one hex. Both forces use the existing infantry catalog, including their subordinate squads and HQ sections; support weapons and vehicles are omitted.

Open **Scenario Library**, select **Ardennes Crossroads**, press **Play**, and choose either detachment. Authored positions are ready to play; the Americans always act first, including when controlled by the AI.

The sole primary objective is the village at hex **4,3** (the map's zero-based column,row coordinates). Americans must seize it; Germans must hold or retake it. For a short playtest, play six full rounds, each consisting of one American turn and one German turn. At the end, the side with a living unit on the objective and no adjacent living enemy wins; otherwise draw. Assess this outcome manually; this scenario adds no automatic victory or turn-limit system.

### Playtest

- Launch once as each side. Confirm nine friendly platoons, a continuous eight-hex deployment front, one reserve behind it, the crossroads marker, and the American first turn.
- Compare a direct road advance with a flank through woods or medium terrain; check movement, selection, and order previews.
- Attack across adjacent hexes and complete the existing battle-result/casualty-entry flow. Check retreats, advances, and objective ownership after an attacker victory.
- Use Dig In, combine/split a friendly stack, and confirm the AI continues taking turns.
- Save/continue during the mission and confirm forces, casualties, positions, and the objective survive.

The automated starter checks run as part of `bash ci/godot_check.sh` under Godot 4.7. They load the checked-in JSON through `SaveManager`, validate it, round-trip its export, launch both side-selection buttons, initialize all eighteen gameplay counters, and check full-width deployment coverage, the separate reserves, routes to the objective, and AI turn resolution.
