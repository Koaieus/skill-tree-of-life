# The temp-addon shop

How a melee swing's budget is spent on temporary addons. Every addon with `temp_placeable` is offered; a kind costs blade size plus zero to two aspect currencies. Three surfaces share one door, `PlayerInputController.request_temp_upgrade_at`, so a fan pick, a quickbar placement and a receipt refund all take the same toggle a graph click does.

## Surfaces

**Blade-node menu** (`systems/armed/blade_node_menu_mode.gd`, `ui/hud/blade_node_menu/`). A left-click on a node already in the blade (pivot or member) pushes `BladeNodeMenuMode` over `BladeMode`; a click on an unpicked node still picks it. An armed `TempUpgradeMode` sits above the blade and wins the click, so no menu opens while a card is armed. The HUD face is a `CardFan` anchored at the node, with the un-pick hub under the cursor (a second click un-picks; on the pivot it pops the blade, on a member it drops the member). Cards are fixed-size, stable once the menu is open, and only kinds placeable on that node right now are drawn (`MeleeAttackPlan.placeable_temp_kinds`); a kind the node already carries draws lit. On open the camera nudges (`GraphCamera.reveal`) so the whole fan is on screen, and the node's tooltip fan stays down. A pick toggles the kind, then closes the menu and arms nothing. Any close but pick/unpick leaves the plan untouched. Seat-local, never on the wire. Click routing: `click-grammar.md`.

**Quickbar** (`systems/armed/temp_quickbar.gd`, row `%Quickbar` in `ui/hud/command_tray/bodies/melee_body.gd`). One slot per key in `PlayerInputController.TEMP_UPGRADE_HOTKEYS` (Z X C V B); pressing or clicking a slot arms that blueprint while MELEE is the active attack. The bar lives on `MeleeMemory`: seat memory, kept for the run, never synced, never written to a save. `swap` (right-click a slot, picked from `%SwapFan`, limited to kinds whose aspect costs are all held above 0) pins its slot. Fills only take open slots (empty and unpinned) and never put a kind on the bar twice: the run-start `autofill` happens on the first melee plan, and `on_aspect_gained` fills when an aspect goes from 0 to above 0.

**Tray detail and receipt.** The tray holds the quickbar, a `%Receipt` strip of what this swing has bought (clicking an entry refunds it through the same toggle), and a `%Detail` panel for the blueprint hovered in the fan or on the bar. The fan's own tooltip is minimal (icon and costs).

## Canonical order and roles

`TempUpgradeCatalog.offered()` is the one owner of the order, read by the fan and the quickbar auto-fill: `SkillNodeAddon.role` in enum order (offence, debuff, defence, utility), then blade-size price ascending (`temp_costs_of(scene, 0)`), then scene path.

`SkillNodeAddon.role` is the job an addon does when copied onto the blade, one tag per addon, read without an instance via `SkillNodeAddon.role_of(scene)`. The enum's default is a fifth value, `UNSET`, which no def keeps: Godot omits an export equal to its default when saving a scene, so a default of offence would erase every explicit offence tag on the next resave. A test fails on any def left at `UNSET`.

A def's tag and its offered flag are on its `.tscn` in `skill_node/addons/defs/` (`role`, `temp_placeable`). Role order and order within a role are tentative.
