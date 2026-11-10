The display for the forge and the quiver: the forge's two element sockets in the magic HUD — the shape socket and the ride socket (each one's authored default, add or replace, the units, why a spell refuses an element, the points spent under the spell's capacity) — and the element arrows in the ranged HUD (arrow looks, bins, stock cap). Child of hub #1716; design home `docs/design/elements.md` § The forge and § Shape and ride. Display only — every number it shows is read from the units below, never derived again.

Blocked by: #{forge}, #{quiver}, #{terrain-ui} (the last for one shared element icon and colour, not for any mechanic)
Blocks: none

## Acceptance spec

**Decisions**
- *"one slot determines the color of the crystal in your wand {= reach}, another slot for elemental payload {at most 1}, and 'regular' slots besides that"* (owner, 2026-11-10; `docs/design/elements.md:638-646`, ADR 0085 §1): the HUD shows a shape socket and a ride socket beside the aspect sockets; the ride holds one terrain element at most and may differ from the shape.
- *"say you got 3 Fire … you can spend 1 there and 2 on Heat for 2 Heat stack riders"* (owner, 2026-11-10; `elements.md:644-646`, ADR 0085 §1): the same element in both sockets draws on one count, and each socket's pick shows what the other has left of it. The spell's authored baseline is free on top.
- *"the spell should carry at most one Element … forge can add to it (synergy) or replace it for the cast (original cleared, your choice put in)"* (owner, 2026-11-09; `docs/design/elements.md:380-389`); since 2026-11-10 that field is the shape and the ride is a second one, and a spell authors a default for each or none (`elements.md:634-636`) — so each socket shows which of the two a pick does, against its own authored default, before it is made.
- The ride takes no aspect slot, and its points count against `SpellDef.infusion_capacity` with the aspects' points (owner, 2026-11-10, picked *own slot, points count against spell capacity*: *"option 1, good solution"*; `elements.md:646-655`, ADR 0085 §2) — the HUD shows the points spent under that cap, the ride's among them.
- The capacity number itself (base + per degree, per caster node), the caster gate, the reset-to-base control, the "n targets hidden" hint and the real cap once a target is picked are #{overqualified-casting}'s (ADR 0085 §3-§4), not this unit's.
- *"they can reorder it with the others"* (owner, 2026-11-09; `elements.md:390-398`): element arrows are ordinary cards in the volley order.
- *"storing 1000 heat arrows sounds like bad juju"* (owner, 2026-11-05; `elements.md:1149-1153`): the cap is a stated number, so the HUD shows it.
- Visuals ride their unit; a large display surface is its own unit behind the mechanics (owner, 2026-11-10: *"option 1"*). This is that unit for child 9.

**Knobs** (tentative defaults — easy to change)
- `InfusionSockets.element_socket_px` = `socket_px` (44) — the ring edge of the shape socket and the ride socket (one size for both); setter redraws in the editor like `socket_px`.
- Any further size, gap or tint the drone adds is an `@export` with a setter redraw on the owning `@tool` control, or a row on the sandbox host's ammo widgets tab for the arrow looks.

**Composition**
- Magic HUD: two element sockets beside the aspect sockets in `InfusionSockets`, a shape socket and a ride socket; neither is one of `infusion_slots`, so both stay usable at 0 aspect slots and with every aspect socket full. Each reads its own field on the infusion (#{forge}'s shape field and ride field; with nothing forged, the spell's authored default for that field, or empty) and, while picking, marks each element as *adds* (same as that field's default) or *replaces* (different), and greys an element the spell refuses with the reason. The two are told apart at a glance without a label (the shape is the wand's crystal colour in the owner's words; the look is the drone's).
- One count, two sockets: an element's pick shows the count left after the other socket's spend on that same element (count − the other socket's points, both read from #{forge}); a different element in each socket draws its own count.
- Points under the cap: `MagicBody` shows the points that count against the spell's capacity as *used / cap*, the ride's points included with the aspects' — the total and the cap are each one read from the data side (#{forge}'s total, the one `aspect_overrun()` tests; `SpellDef.infusion_capacity` for the cap), never summed here. An infinite cap shows the used count alone. A ride point that would pass the cap is refused in the pick with the capacity reason `InfusionChoices` already gives an aspect. #{overqualified-casting} later re-points the cap read at the caster node's capacity and adds its own controls on this same surface.
- The crucible readout (`ReadoutLines` / `CrucibleReadoutLine`) gains one line per filled element socket — a ride line and a shape line — in the same behaviour-change phrasing as aspects, with the int:int exchange (`Infusion.ratio_of` / `InfusionExchange`). The ride line names the terrain it plants (Heat / Cold / Charge) and its stacks. The shape line names the element and its points only: what a shape does to the walk (disc, level, hops) and its preview are #{cast-shapes}'s and #{ice-cast}'s.
- Ranged HUD: `RangedBody`'s cards already walk the roster (#{quiver}); add the stock cap beside each element bin (`AmmoType.stock_cap(mint)` from #{quiver}) and the bin's count, and nothing for the plain pool's capacity changes.
- Arrow looks: #{quiver} landed three bare scenes inheriting `status_arrow.tscn`; this unit dresses them from kit parts (`arrow_parts/`, the arrow-looks rule), each readable as Heat / Cold / Charge at a glance and in the element's colour from #{defs}' `Identity`.
- Dies: nothing.

**Files touched**
- `ui/hud/command_tray/bodies/infusion_sockets.gd`, `infusion_socket.gd`, `magic_body.gd`, `infusion_choices.gd` — the shape socket, the ride socket, their picks, the used / cap tally (#{overqualified-casting} lands on the same files after this unit).
- `ui/hud/command_tray/bodies/readout_lines.gd`, `crucible_readout_line.gd` — the ride line and the shape line.
- `ui/hud/command_tray/bodies/ranged_body.gd` — stock cap per element bin.
- `ui/vfx/projectile/visual/arrows/` — the three element arrow scenes (#{quiver} created them).
- `docs/domain/hud-widgets.md` — § MagicBody gains the two element sockets and the tally; the RangedBody contract if the drone adds one.
- `test/unit/ui/test_readout_lines.gd` and one test file for the sockets (drone names it under `test/unit/ui/`).

**Acceptance**
1. `test_readout_lines.gd`: a cast with a forged ride yields one ride line whose numbers equal `Infusion.load_of` / `gained` for that element; a ride that replaces the spell's authored ride yields no line for the cleared one. A cast with a forged shape and a forged ride of different elements yields two lines, one each; shape only yields one line and no ride line.
2. Socket test: with nothing forged each element socket shows the spell's authored default for its field (or empty); in either socket a pick of a different element is marked *replaces*, the same element *adds*; setting the shape leaves the ride socket's content unchanged and the reverse; with every aspect socket filled, and on a caster with 0 `infusion_slots`, both element sockets take a pick, and `slots_used()` is the same before and after.
3. A spell that refuses an element shows that element greyed with a reason string in the socket it is refused for, and picking it is a no-op.
3a. Socket test, one count: a caster holding N of an element with k points of it in the shape socket is offered at most N − k of it in the ride socket, and the reverse (assert the relation to the count, never a literal); a different element in the ride is offered its own full count.
3b. Tally test, on a spell def given a finite `infusion_capacity` C in the test: with a aspect points and r ride points the tally reads the data side's used total (a + r while shape points do not count) over C; adding a ride point moves the used number by exactly that point; at used = C a further ride point is greyed with the capacity reason and picking it changes nothing. With `infusion_capacity` infinite the tally shows no cap.
4. `RangedBody`: each element bin shows its count and its cap; the cap equals `AmmoType.stock_cap` of that type's reload mint.
5. `test_ammo_type_roster.gd:81-99` still holds; in the arrow gallery (`addons/arrow_gallery`) the three element arrows are told apart from each other and from goo with no label.

**NOTES**
- Reading list and seam map were cut before #{defs}…#{catalyst} landed; #{refresh} re-cuts the stamp. If `mise run issue-drift` still flags this issue at dispatch, stop and say so.
- The look may be handed to a sub-agent working in this same worktree once the hook it draws from (signal, record field, scene stub) exists; the unit's drone stays the owner and reviewer of the result.
- The doc specifies almost no looks: the required reads are above, the art is the drone's.
- Still open (ADR 0085 revisit-when): whether shape points also count against the capacity. Tentative: they do not. The tally reads one total from #{forge}, so the answer changes no code here.
- The overqualified-casting display — the reset-to-base control (0 overqualification), the "n targets hidden" hint, the real cap once a target is picked (the best capacity among the casters that reach it) — is #{overqualified-casting}'s (`elements.md` § The forge, "Overqualified casting"); #744's heatmap is its neighbour. None of it lands here.
- Terrain display on the node (bars, label, glow) is #{terrain-ui}'s; use its element colour and icon, never a second palette.
- What a shape does on a cast and its preview (Fire's disc, Lightning's level, Ice's "4 hops → 0, seed × N") are #{cast-shapes}'s and #{ice-cast}'s; until it lands a shape socket's points change nothing on the cast, and this unit shows the socket and its points only. The Cold spell (#1789) and its Thermal shock read are not here either.
- The AI forges no element (#{forge} NOTES); nothing here for AI.

**Stubs on master** — none — shapes are named in Composition; the drone adds them.

```drift-stamp efba0bc3
docs/design/elements.md:380-411 — one element per cast (add or replace); element arrows as cards in the volley
docs/design/elements.md:1149-1153 — the stock cap quote
docs/design/elements.md:1170-1176 — bins beside the pool, the cap as a multiplier on the mint
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
