Element arrows: one ammo type per element, minted 1:1 from the element count into its own bin beside the plain pool, and a stock cap scaled by the mint. Child of hub #1716; design home `docs/design/elements.md` § The forge and § Acquisition. Its sibling `forge` is the cast half of child 9 and owns the forge's shape field, ride field and aspect slots (ADR 0085 §1); the starter counts are #{forge}'s, not this unit's. The two share no file. An arrow is a ride only: it plants its terrain status on a hit and has no shape (`elements.md` § Shape and ride: "arrows and blades have only this"). The access shape #1765 asked for is settled in the doc; #1765 is closed at filing with a pointing comment, not by this issue.

Blocked by: #{fire}, #{lightning}, #{ice}
Blocks: #{forge-ui}

## Acceptance spec

**Decisions**
- *"arrow pools are *per type* given Fuel is now an Aspect called Catalyst, we can reintroduce plain fire arrows that simply add heat stacks. 1:1 fire_element -> fire arrows each reload. possibly more scalers later idk. then ranged could add 1 type of elemental arrows with their volley, and they can reorder it with the others"* (owner, 2026-11-09; `docs/design/elements.md:390-398`). An arrow is an aspect subtype *or* an element, never both (`:399-400`).
- **No cap on elements per volley** (owner, 2026-11-09, picked over one element per volley; `elements.md:405-408`).
- **The count is the access** — every reload mints `fire` fire arrows into their own bin, nothing to find or buy (owner, 2026-11-09, picked over a temp quiver addon and a starter ammo type; `elements.md:1161-1168`). Element bins sit beside the plain pool, not inside its capacity (`:1170-1171`).
- Stock cap: *"storing 1000 heat arrows sounds like bad juju"* (owner, 2026-11-05); the knob is a multiplier on the type's own per-reload mint, default 2 (pass pick, tentative; `elements.md:1149-1153, 1172-1176`).
- No int:int rate on `AmmoType`: the mint stays 1:1 through `per_reload_stat_id` and an arrow carries an authored load; a count-scaled load per arrow is the per-hit load the doc rejects (`elements.md:412-417`; owner's *"possibly more scalers later idk"*) (pass pick, tentative; kept 2026-11-10).

**Knobs** (tentative defaults — easy to change)
- `AmmoType.stock_cap_reloads` (`@export_range(0, 20)`, int) = 2 on the three element types, 0 elsewhere (0 = the flat `max_stock` as today) — a bin banks this many reloads' mint; inspector on each `.tres`.
- Each element type's rider `ApplyStatusEffect.power` = 1.0 (the class default) — the authored Heat / Cold / Charge per arrow.
- Element type `order` = 3 / 4 / 6 (Heat / Charge / Cold arrows) — after Catalyst's goo (2) as the owner's *"launch Catalyst shots first, then elemental"*; the player's card order overrides it (`ammo_type.gd:19-21`).

**Composition**
- The Cold arrow is this unit's: the `ice` type below, planting Cold once #{ice} has landed the terrain status; #{ice} points here for it.
- The count is read from the stat; its starter value is #{forge}'s, so a reload mints that many. Three `AmmoType` `.tres`, ids = the element concept ids (`fire` / `ice` / `lightning`, whose COUNT facets are `fire_element` / `ice_element` / `lightning_element`, #{defs}), each one `ApplyStatusEffect` of its terrain status (Heat / Cold / Charge, #{defs}) and registered in `ammo_type_roster.tres`. `per_reload_stat_id()` falls back to the COUNT facet of the id (#{defs} renamed ASPECT → COUNT), so the mint branches on nothing.
- `AmmoType` exposes `stock_cap(mint: int) -> int` — `stock_cap_reloads × mint` when positive, else `max_stock`. Every caller that passes `max_stock` to `Quiver.add` / `room_for` passes `stock_cap(that type's mint)` instead: `Entity.reload`, the AI reload composition, the arrow gallery. `Quiver` itself is unchanged (it already banks specials outside capacity, ADR 0041).
- Visual: each element type needs a `visual_scene` inheriting `status_arrow.tscn` (pinned by `test_ammo_type_roster.gd:81-99`); this unit lands three bare inherited scenes tinted by their status, `forge-ui` dresses them.
- Dies: nothing.

**Files touched**
- `attack/ammo/types/` — three new element `.tres`; `attack/ammo/ammo_type_roster.tres` — registration.
- `attack/ammo/ammo_type.gd` — `stock_cap_reloads`, `stock_cap`.
- `entity/entity.gd` (`reload`), `entity/controller/ai_controller.gd`, `addons/arrow_gallery/arrow_gallery_panel.gd` — pass `stock_cap`.
- `ui/vfx/projectile/visual/arrows/` — three bare inherited arrow scenes (shared with `forge-ui`).
- `test/unit/attack/test_ammo_type_roster.gd`, `test/unit/test_quiver.gd`.

**Acceptance**
1. `test_ammo_type_roster.gd` re-pointed pins: `_IDS` gains the three element ids; `:37-50`'s per-reload assertion reads the COUNT facet; `:52-58`'s "carries its own status" becomes "carries its own status, or a member status of its element" for element types; the scene test (`:81-99`) holds for the three new types.
2. `test_quiver.gd` (or a reload test beside it): an entity with element count n reloads → its element bin gains n, the plain pool's `current` is unchanged by it, and a second and third reload stop at `stock_cap_reloads × n`.
3. A volley composed with Heat, Charge and Cold arrows together lands all three riders (no per-volley element cap).
4. The quiver HUD lists the element types as cards in the volley order with no HUD code change (it walks the roster); the bespoke look and the stock-cap readout are `forge-ui`'s.

**NOTES**
- Reading list and seam map were cut before #{defs}…#{catalyst} landed; #{refresh} re-cuts the stamp. If `mise run issue-drift` still flags this issue at dispatch, stop and say so.
- The look may be handed to a sub-agent working in this same worktree once the hook it draws from (signal, record field, scene stub) exists; the unit's drone stays the owner and reviewer of the result.
- The blade addon budget by element count is `blade-elements`'s, not this unit's.

**Stubs on master** — none — shapes are named in Composition; the drone adds them.

```drift-stamp efba0bc3
docs/design/elements.md:390-417 — one ammo type per element, 1:1 mint, no per-volley cap, no rate seam on AmmoType today
docs/design/elements.md:1142-1176 — #1765's access shape settled, bins beside the pool, stock cap arithmetic
attack/ammo/ammo_type.gd:16-59 — id, order, on_hit_effects, per_reload_stat_id fallback, max_stock
attack/ammo/ammo_type_roster.gd:15-40 — types, sorted, by_id
attack/ammo/types/explosive.tres:1-21 — the template: one ApplyStatusEffect rider, order, visual_scene
stats_system/quiver.gd:40-95 — bins, add clamped to room, room_for (special = max_stock − bin)
entity/entity.gd:700-749 — reload_yield mints per type; reload passes max_stock to Quiver.add (:747)
test/unit/attack/test_ammo_type_roster.gd:1-99 — the roster pins to re-point
attack/ammo/ammo_type_roster.tres — seam: the one registration point
entity/controller/ai_controller.gd — seam: AI reload composition reads max_stock (:466-473)
addons/arrow_gallery/arrow_gallery_panel.gd — seam: quiver.add with max_stock
addons/sandbox_host/tabs/13_ammo_widgets_panel.gd — seam: preloads the roster
ui/vfx/projectile/visual/status_arrow.tscn — seam: the base scene every statused type inherits
ui/vfx/coordinator/arrow_volley_coordinator.gd — seam: flies visual_scene, default when null (:305)
ui/hud/command_tray/bodies/ranged_body.gd — seam: quiver HUD walks the roster
test/unit/test_quiver.gd — seam: bins and room
```
