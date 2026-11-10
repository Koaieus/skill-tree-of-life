Overqualified casting: a spell's point cap is read per caster node (base + a bonus per degree above `min_degree`), the loadout gates which nodes may cast it, the cap is enforced where points are socketed and where sources are gathered, and the magic HUD gets a way back to the base cap. Child of hub #1716; design home `docs/design/elements.md` § The forge, "Overqualified casting", and ADR 0085 §3-§4. It makes `SpellDef.infusion_capacity` finite, which is what gives #{forge}'s ride a price (ADR 0085 §2). Also fixes the stale `infusion_slots` ladder text.

Blocked by: #{forge-ui} (same HUD files, and this unit re-points its cap read), which is behind #{forge}
Blocks: none

## Acceptance spec

**Decisions**
- *"we might just have found a mechanic for *overqualified casting*. if casting from a node of, say degree N, a spell has min required degree M, if N<M it cannot cast it, if N≥M it can cast, and the excess may be used for additional points e.g. 5 or so per excess degree"* (owner, 2026-11-10; `docs/design/elements.md:430-437`, ADR 0085 §3). A node's capacity for a spell = the spell's base cap + a bonus per degree above `min_degree`, one formula. Below `min_degree` the node cannot cast, as today.
- Starting knobs: base 10 (*"maybe 10 is a better starting cap"*, owner, 2026-11-10, after a first 15) and 5 per degree (`elements.md:435-437`, ADR 0085 §3).
- **The loadout gates the caster** (owner, 2026-11-10, picked over sorting casters by degree and over clamping the loadout to today's pick; `elements.md:437-444`, ADR 0085 §4): a loadout of P points is a higher `min_degree`. The target union admits only sources whose capacity carries it, targets light up for those alone, and among them the pick stays the highest node-local `spell_damage`. A point added after the target is picked re-picks the source among those that can carry it, or the socket refuses the point.
- The union depends on the loadout and rebuilds whenever it changes; the cap is enforced where points are socketed and where sources are gathered, not only at launch; `aspect_overrun()`'s total-points term needs the casting node (ADR 0085 Consequences). A loadout no owned node can carry has no targets at all (same place).
- The way back (owner, 2026-11-10; `elements.md:444-450`, doc only): *"an intuitive way to scale loadout back to cap at 0 overqualification so the targets are there again. and some helpful text like "no qualified casters for this loadout | there are {n} targets hidden because of this [reset to cap]" but snappier"*. Once a target is picked the HUD shows the real cap, the best capacity among the casters that reach it.
- Which points count against the cap is #{forge}'s (the ride's with the aspects', ADR 0085 §2). This unit reads its one "points against capacity" total and never sums points itself.
- With no target picked, the cap a socket fills against is the best capacity among the spell's eligible casters (pass pick, tentative: it is the only reading under which the owner's "targets hidden" state and the reset can arise from today's fill-to-the-most sockets; the other reading, the base cap until a target is picked, is the fallback).
- An aimed spell's caster is the player's own drag, so its cap in force is that node's capacity and a point past it is refused, never re-picked (pass pick, tentative).
- The AI fills to the capacity of the source it scores, so it never hides its own targets (pass pick, tentative).

**Knobs** (tentative defaults — easy to change)
- `SpellDef.infusion_capacity` = 10.0 (class default, was `INF`) — the base cap, points at 0 overqualification. `INF` stays legal and means uncapped. No `.tres` authors it today, so every spell reads 10; inspector per spell.
- `SpellDef.infusion_capacity_per_degree` (`@export_range(0, 20)`, int) = 5 — points per degree above `min_degree`; inspector per spell, beside `infusion_capacity`.
- Any size, gap or tint on the reset control and the hint is an `@export` with a setter redraw on the owning `@tool` control.

**Composition**
- The formula has one home: `SpellDef.capacity_at(degree: int) -> int` = `floor(infusion_capacity) + infusion_capacity_per_degree × max(0, degree − min_degree)`; an `INF` base answers uncapped the way `socket_points` treats it today. Example at min_degree 2: degree 2 → 10, 3 → 15, 4 → 20.
- "What can this node carry" has one home beside "can this node cast it": `SpellBook.capacity_of(spell, source, attacker) -> int`, reading the same owned-subgraph degree `_node_meets_source_requirements` reads (`attacker.navigator.get_degree`), with the same bookless fallback the union and the plan already keep. `SpellBook.eligible_sources` stays loadout-blind: it is the spell picker's "can ever be cast" gate.
- `SpellTargetUnion.build` takes the loadout's points (its unused plan parameter is the seam) and keeps as sources only the eligible nodes whose capacity ≥ those points. `sources`, `per_source`, `best_source`, the CASTER highlight and the reach visual all follow from that list, so nothing downstream branches. `_pick_best_sources` is untouched. 0 points admits every eligible node, which is what the AI's whole-territory build passes.
- `MagicAttackPlan` owns the cap in force, `capacity() -> int`: with a target committed, the best capacity among the eligible casters that reach it (the real cap); on an aimed spell with a source, that source's capacity; otherwise the best capacity among all eligible casters. `socket_points` walks against it in place of `spell.infusion_capacity`, and #{forge}'s ride setter is refused past it by the same read.
- Every loadout change that moves the points total marks the union dirty (the plan's existing `invalidate_union` path; never hover). With a target committed the plan then re-reads `union().source_for(target)`: a node → that is the source now; none → a gated write (`set_socket`, the ride setter) is a no-op. The ungated `set_infusion` (ADR 0035: the wire, the AI, the restore) keeps its source and shows in the overrun.
- `aspect_overrun()`'s total term reads the stamped source's capacity, and `capacity()` when no source is stamped. The host runs it on its own board at launch as today (`BattleSystem._can_afford`).
- `MagicAttackPlan.hidden_target_count() -> int`: targets the spell would list at 0 overqualification (every eligible caster a source) that the current union does not. `MagicAttackPlan.reset_to_base_capacity()`: re-walks the sockets front to back against the base cap, so the last sockets give way first, and trims the ride last-in through #{forge}'s setter. It is a one-shot trim: the next socket write walks against the cap in force again.
- `ArmedStack.clamp_infusion` clamps a remembered loadout to the pre-target cap in force, not to the spell's bare number. `AiInfusionPicker.pick` takes the cap of the candidate's source; the controller's per-spell cache becomes per spell and cap.
- HUD (after #{forge-ui}, on its surface): the *used / cap* tally's cap reads `plan.capacity()` instead of `SpellDef.infusion_capacity`, so it shows the real cap once a target is picked. `InfusionChoices`' capacity reason names that same number. `MagicBody` gains one reset control and one hint line: hidden while `hidden_target_count()` is 0; with targets hidden it reads the count; with no caster able to carry the loadout it says so. The copy is the drone's, snappier than the owner's draft. Pressing reset calls `reset_to_base_capacity()`.
- Stale fact: the INT ladder for `infusion_slots` is 10 / 100 / 1000 (`entity/default_entity_board.tres:359-365`); three texts still say 100 / 1000 / 10000 and are corrected to the board.
- Dies: the reading of `infusion_capacity` as a per-spell constant at every call site (`socket_points`, `aspect_overrun`, `clamp_infusion`, `AiInfusionPicker`, `InfusionChoices`).

**Files touched**
- `attack/spell/spell_def.gd` — default 10.0, `infusion_capacity_per_degree`, `capacity_at`.
- `entity/spell_book.gd` — `capacity_of`.
- `attack/targeting/spell_target_union.gd` — the points parameter and the source filter.
- `attack/plan/magic_attack_plan.gd` — `capacity`, the dirty mark, the re-pick, the overrun term, `hidden_target_count`, `reset_to_base_capacity` (#{forge} and cast shapes #{ice-cast} land on this file too).
- `systems/armed/armed_stack.gd` — `clamp_infusion`'s cap.
- `entity/controller/ai_infusion_picker.gd`, `entity/controller/ai_controller.gd` — the cap per source.
- `ui/hud/command_tray/bodies/magic_body.gd`, `infusion_choices.gd`, and the scene `magic_body.gd` is the script of — the cap read, the reset control, the hint (#{forge-ui} owns the tally and lands first).
- `stats_system/defs/infusion_slots.tres` (description), `stats_system/entity_stat_board.gd:190` (comment), `docs/domain/stat-formulas.md:21` (table row) — 10 / 100 / 1000.
- `docs/domain/aspect-cell-authoring.md:215-219` — `infusion_capacity` is a base read per caster node; `docs/domain/hud-widgets.md` § MagicBody — the reset and the hint.
- `test/unit/attack/test_spell_target_union.gd`, `test/unit/spell/test_infusion.gd`, `test/unit/spell/test_set_socket.gd`, `test/unit/spell/test_infusion_choices.gd`, `test/unit/ai/test_ai_infusion_picker.gd`, one HUD test under `test/unit/ui/` (drone names it).

**Acceptance**
1. `test_infusion.gd`: `capacity_at` on a spell with base B, per-degree K, min_degree M answers B at degree M and B + K × n at degree M + n; assert the relation to the def's fields, never 10 or 5. With `infusion_capacity = INF` no total is enforced at any degree.
2. `test_spell_target_union.gd`, on its fixture (owned path, degrees 1 / 2 / 1) with a min_degree 1 spell: built at 0 points the union lists three sources; built at B + 1 points it lists only the degree-2 node, `best_source` maps every listed target to it, and a target only the end nodes reach is absent. Built at more points than the best node carries: `has_eligible_sources()` is false and there are no targets.
3. Same file: with two carrying sources reaching one target, the pick is the higher node-local `spell_damage`, lowest stable id on a tie (the existing pin, re-run under a loadout); a node with higher `spell_damage` that cannot carry the loadout is not picked.
4. `test_set_socket.gd`: with no target, a socketed aspect held above every cap fills to the best capacity among eligible casters; with a target committed that only a base-degree node reaches, the same pick fills to B. After any socket write `aspect_overrun()` is 0 (the existing randomized pin at `:113-124` holds).
5. `test_set_socket.gd`: a target committed from source S; a socket write that takes the total past S's capacity while a higher-capacity caster also reaches the target leaves the target and moves `source` to that caster; when no caster reaching the target can carry more, the write changes nothing (points, order, source all equal before and after).
6. `test_infusion.gd`: a plan with source stamped on a base-degree node and B + 2 points set through `set_infusion` reads `aspect_overrun()` = 2; the same points with a source one degree up (K ≥ 2) read 0. Re-point `:116-121` (capacity 4, 6 points → 2) to state its source; `:108-113` ("no total cap") sets `INF` explicitly.
7. A plan's union is rebuilt after a loadout change that moves the total and not after a hover change: count builds through a spy on the union the way the file's sweep spies do, or assert the union object's identity.
8. `test_infusion.gd`: `clamp_infusion` of a remembered loadout above every capacity returns a total equal to the best capacity among eligible casters. `test_ai_infusion_picker.gd`: `pick` given cap C returns a total ≤ C, and re-point `:45` to pass its cap.
9. `hidden_target_count()` is 0 at or under the base cap; on acceptance 2's fixture at B + 1 points it equals (targets at 0 points) − (targets now). After `reset_to_base_capacity()` the total is ≤ B, the count is 0, and socket 0's aspect survives ahead of the last socket's.
10. HUD test: the hint and the reset control are hidden at count 0; at count n the hint's text contains n; a loadout no caster carries shows the no-caster line; pressing reset leaves the count 0 and the control hidden. With a target committed the tally's cap equals `plan.capacity()` and differs from the spell's base when the best caster reaching the target is above `min_degree`.
11. `grep -rn "10000" stats_system/defs/infusion_slots.tres stats_system/entity_stat_board.gd docs/domain/stat-formulas.md` finds no infusion-slots line; the three texts name 10 / 100 / 1000.
12. `mise run test` stays green (a class default moved: grep `infusion_capacity` and "no total cap" across `test/` and re-point, never delete); `mise run mp:e2e` stays green (the launch check changed).

**NOTES**
- Split seam, if the board wants the mechanic early: acceptances 1-9 and 11 touch no HUD file and depend on no element unit (every seam is on master for aspects; the ride joins through #{forge}'s total whenever it lands). Only 10 needs #{forge-ui}. Filed as one unit it waits for #{forge-ui}.
- Still open (ADR 0085 revisit-when): whether shape points also count against the capacity. Tentative: they do not. This unit reads one total from #{forge}, so the answer changes no code here.
- Still open for the owner: the fill rule with no target (Decisions, tentative), and whether a reset should stick (here it is a one-shot trim). Today a socket has no per-point control: socketing an aspect fills it to the most it can carry, so a held count above the cap overqualifies on the first pick.
- #744 (heatmap of enemy nodes by best available caster power, Needs design) is the neighbouring display: it paints over the same union, so it reads the loadout-gated sources for free. Nothing of it lands here.
- The forge's sockets and the tally itself are #{forge-ui}'s; the ride field and what counts are #{forge}'s; what a shape does on a cast is #{ice-cast}'s (cast shapes).
- The union's loop order is its cost (`spell_target_union.gd:116-124`). The gate filters sources before the gather; `hidden_target_count` must not add a gather per hover or per frame. `test/perf/bench_ai_turn.gd` is the AI-side bench.
- ADR 0085's fallback if hidden targets read badly in play is clamping the loadout to today's pick. Not built here.

**Stubs on master** — none — shapes are named in Composition; the drone adds them.

```drift-stamp 5cb6de79
docs/design/elements.md:430-450 — overqualified casting: the formula, the loadout gates the caster, the way back, the real cap
docs/design/elements.md:646-655 — the ride's points count against infusion_capacity, which is infinite today
docs/adr/0085-the-forge-has-three-kinds-of-slot-and-a-spells-point-cap-grows-with-the-caster-nodes-degree.md:28-41 — §2-§4 and the Consequences this unit builds
attack/spell/spell_def.gd:79-79 — min_degree
attack/spell/spell_def.gd:133-135 — infusion_capacity, INF on every spell
entity/spell_book.gd:102-134 — eligible_sources, is_castable, the degree read behind min_degree
attack/targeting/spell_target_union.gd:116-134 — build: the source list, the unused plan parameter
attack/targeting/spell_target_union.gd:194-224 — the bookless eligibility fallback; _pick_best_sources
attack/plan/magic_attack_plan.gd:190-208 — set_target looks the caster up from the union
attack/plan/magic_attack_plan.gd:404-427 — union(), invalidate_union, the rebuild
attack/plan/magic_attack_plan.gd:679-703 — set_infusion (ungated) and set_socket (re-walks every socket)
attack/plan/magic_attack_plan.gd:737-770 — socket_points and aspect_overrun read the spell's bare capacity
systems/armed/armed_stack.gd:114-150 — restore_infusion and clamp_infusion
entity/controller/ai_infusion_picker.gd:14-22 — the AI's fill reads the spell's bare capacity
entity/controller/ai_controller.gd:672-725 — one infusion per spell, applied to every probe and to the armed plan
test/unit/attack/test_spell_target_union.gd:56-60 — the fixture: an owned path with degrees 1 / 2 / 1
entity/default_entity_board.tres:359-365 — the infusion_slots ladder, 10 / 100 / 1000
systems/battle_system.gd — seam: the launch check calls aspect_overrun (:506)
systems/armed/magic_mode.gd — seam: pushes invalidate_union on ownership and turn (:63)
ui/hud/command_tray/bodies/infusion_choices.gd — seam: the capacity reason string (:34-35)
ui/hud/command_tray/bodies/magic_body.gd — seam: the crucible body the reset and hint land on
ui/spell_picker_bar/spell_picker_bar.gd — seam: the no-caster gate reads eligible_sources (:200), stays loadout-blind
stats_system/defs/infusion_slots.tres — seam: the stale description
stats_system/entity_stat_board.gd — seam: the stale comment (:190)
docs/domain/stat-formulas.md — seam: the stale table row (:21)
docs/domain/aspect-cell-authoring.md — seam: infusion_capacity's contract (:215-219)
docs/domain/hud-widgets.md — seam: MagicBody's contract (:46-84)
test/unit/spell/test_infusion.gd — seam: the overrun and clamp pins (:108-156)
test/unit/spell/test_set_socket.gd — seam: socket walk pins
test/unit/spell/test_infusion_choices.gd — seam: the capacity reason
test/unit/ai/test_ai_infusion_picker.gd — seam: the capped pick (:45)
test/perf/bench_ai_turn.gd — seam: the AI union bench
```
