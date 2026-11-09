The display for the forge and the quiver: the forge's element field in the magic HUD (innate element, add or replace, the units, why a spell refuses an element) and the element arrows in the ranged HUD (arrow looks, bins, stock cap). Child of hub #1716; design home `docs/design/elements.md` § The forge. Display only — every number it shows is read from the units below, never derived again.

Blocked by: #{refresh}, #{forge}, #{quiver}, #{terrain-ui} (the last for one shared element icon and colour, not for any mechanic)
Blocks: none

## Acceptance spec

**Decisions**
- *"the spell should carry at most one Element … forge can add to it (synergy) or replace it for the cast (original cleared, your choice put in)"* (owner, 2026-11-09; `docs/design/elements.md:380-389`) — the field shows which of the two a pick does before it is made.
- *"they can reorder it with the others"* (owner, 2026-11-09; `elements.md:390-398`): element arrows are ordinary cards in the volley order.
- *"storing 1000 heat arrows sounds like bad juju"* (owner, 2026-11-05; `elements.md:1099-1103`): the cap is a stated number, so the HUD shows it.
- Visuals ride their unit; a large display surface is its own unit behind the mechanics (owner, 2026-11-10: *"option 1"*). This is that unit for child 9.

**Knobs** (tentative defaults — easy to change)
- `InfusionSockets.element_socket_px` = `socket_px` (44) — the element socket's ring edge; setter redraws in the editor like `socket_px`.
- Any further size, gap or tint the drone adds is an `@export` with a setter redraw on the owning `@tool` control, or a row on the sandbox host's ammo widgets tab for the arrow looks.

**Composition**
- Magic HUD: one element socket beside the aspect sockets in `InfusionSockets` (it is not one of `infusion_slots`). It shows the spell's innate element (`Infusion.element_of` with nothing forged, #{forge}) and, while picking, marks each element as *adds* (same as innate) or *replaces* (different), and greys an element the spell refuses with the reason. The crucible readout (`ReadoutLines` / `CrucibleReadoutLine`) gains the element line in the same behaviour-change phrasing as aspects, with the int:int exchange (`Infusion.ratio_of` / `InfusionExchange`).
- Ranged HUD: `RangedBody`'s cards already walk the roster (#{quiver}); add the stock cap beside each element bin (`AmmoType.stock_cap(mint)` from #{quiver}) and the bin's count, and nothing for the plain pool's capacity changes.
- Arrow looks: #{quiver} landed three bare scenes inheriting `status_arrow.tscn`; this unit dresses them from kit parts (`arrow_parts/`, the arrow-looks rule), each readable as Heat / Cold / Charge at a glance and in the element's colour from #{defs}' `Identity`.
- Dies: nothing.

**Files touched**
- `ui/hud/command_tray/bodies/infusion_sockets.gd`, `infusion_socket.gd`, `magic_body.gd`, `infusion_choices.gd` — the element socket and pick.
- `ui/hud/command_tray/bodies/readout_lines.gd`, `crucible_readout_line.gd` — the element line.
- `ui/hud/command_tray/bodies/ranged_body.gd` — stock cap per element bin.
- `ui/vfx/projectile/visual/arrows/` — the three element arrow scenes (#{quiver} created them).
- `docs/domain/hud-widgets.md` — § MagicBody gains the element socket; the RangedBody contract if the drone adds one.
- `test/unit/ui/test_readout_lines.gd` and one test file for the socket (drone names it under `test/unit/ui/`).

**Acceptance**
1. `test_readout_lines.gd`: a cast with a forged element yields one element line whose numbers equal `Infusion.load_of` / `gained` for that element; a replace yields no line for the cleared innate element.
2. Socket test: with nothing forged the element socket shows the spell's innate element (or empty); a pick of a different element is marked *replaces*, the same element *adds*; filling every aspect socket leaves the element socket usable.
3. A spell that refuses an element shows that element greyed with a reason string, and picking it is a no-op.
4. `RangedBody`: each element bin shows its count and its cap; the cap equals `AmmoType.stock_cap` of that type's reload mint.
5. `test_ammo_type_roster.gd:81-99` still holds; in the arrow gallery (`addons/arrow_gallery`) the three element arrows are told apart from each other and from goo with no label.

**NOTES**
- Reading list and seam map were cut before #{defs}…#{catalyst} landed; #{refresh} re-cuts the stamp. If `mise run issue-drift` still flags this issue at dispatch, stop and say so.
- The look may be handed to a sub-agent working in this same worktree once the hook it draws from (signal, record field, scene stub) exists; the unit's drone stays the owner and reviewer of the result.
- The doc specifies almost no looks: the required reads are above, the art is the drone's.
- Terrain display on the node (bars, label, glow) is #{terrain-ui}'s; use its element colour and icon, never a second palette.
- The concentrate preview ("4 hops → 0, seed × N") moved to #{ice-cast} (Needs design); an Ice cast is a ×1 stub (#{forge}), so there is no hop change to show. The Cold spell (#1789) and its Thermal shock read are not here either.
- The AI forges no element (#{forge} NOTES); nothing here for AI.

**Stubs on master** — none — shapes are named in Composition; the drone adds them.

```drift-stamp bd800181
docs/design/elements.md:380-411 — one element per cast (add or replace); element arrows as cards in the volley
docs/design/elements.md:1099-1103 — the stock cap quote
docs/design/elements.md:1120-1126 — bins beside the pool, the cap as a multiplier on the mint
ui/hud/command_tray/bodies/infusion_sockets.gd:1-30 — the socket arc, socket_px with a setter redraw
ui/hud/command_tray/bodies/infusion_sockets.gd:120-172 — _refresh reads plan.infusion.points; _rebuild sizes sockets
ui/hud/command_tray/bodies/infusion_socket.gd:84-118 — one socket shows one identity
ui/hud/command_tray/bodies/readout_lines.gd:1-25 — the readout line shape and its sources
ui/hud/command_tray/bodies/crucible_readout_line.gd:1-20 — the badge and the behaviour-change text
ui/hud/command_tray/bodies/ranged_body.gd:41-84 — the quiver HUD's roster row and bin_changed
ui/hud/command_tray/bodies/ranged_body.gd:336-425 — type order, clamped specials, stock reads
docs/domain/hud-widgets.md:46-84 — MagicBody's contract
test/unit/attack/test_ammo_type_roster.gd:81-99 — every statused type flies its own status-arrow scene
ui/hud/command_tray/bodies/magic_body.gd — seam: socket fill from infusion.points (:157, :174)
ui/hud/command_tray/bodies/infusion_choices.gd — seam: the pick order
ui/vfx/projectile/visual/arrows/ — seam: the twelve arrow looks; the element ones join them
ui/vfx/coordinator/arrow_volley_coordinator.gd — seam: flies visual_scene (:305)
addons/arrow_gallery/arrow_gallery_panel.gd — seam: dev view of every arrow
addons/sandbox_host/tabs/13_ammo_widgets_panel.gd — seam: sandbox tab for the ammo widgets
test/unit/ui/test_readout_lines.gd — seam: readout tests
```
