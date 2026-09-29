# docs/design/lore.md

| Lines | Section | Bucket | Destination / what to cut | Evidence (file:line or grep) |
|---|---|---|---|---|
| 5-9 | Logline | COULD | stays | pure pitch, no code claim |
| 11-51 | Act 0 (incl. "things you kill", intro beat sheet) | COULD | stays | no Fairy/fetch-quest/adventure-game layer in code; `grep -rl "Fairy" *.gd` empty |
| 55-65 | Act 1 — Something is Off | COULD | stays | crash/tree-shudder narrative device, unbuilt |
| 67-79 | Act 2 — Inside | COULD | stays | unbuilt framing narrative |
| 83-124 | The Fairy (+ all subsections) | COULD | stays | no Fairy entity/dialogue system in code |
| 128-142 | Graph Theology — Lord of Edge, Connection is divine, "All edge, no point" | MIXED | mostly COULD (stays); the `coolness` attribute claim ("procgen-sprinkled... tallied at end credits") is stated as if shipped | `coolness` is **not** a field on `EntityStatBoard` (stats_system/entity_stat_board.gd:20-26 lists only strength/dexterity/intelligence/wisdom/perception/constitution) and no `.tres`/`.gd` in repo defines it (`grep -rln coolness . ` → 0 hits). combat_system.md:161 already carries the same idea correctly flagged as design ("does nothing mechanically... Procgen-sprinkled" — itself still unbuilt, but that's the doc's job). Recommend lore.md's paragraph add "(unbuilt)" or drop the present-tense claim. |
| 144-148 | The Ophanim | COULD | stays | no boss/ring-guardian system in code |
| 150-163 | Self-loops | COULD | stays | `grep -rl "self_loop\|self-loop"` — no runtime self-loop mechanic found; explicitly flagged in Open Questions #11 as unresolved anyway |
| 166-232 | The Field, Tethers, Breakout, re-edging, carry-forward | COULD | stays, entire section | `grep -rln "Tether\|Breakout" **/*.gd` → 0 real hits (two false-positive matches are unrelated `ai_combat_scorer`/`entity.gd` identifiers); confirmed no Tether/Breakout code exists at all |
| 236-246 | The Fractal | COULD | stays | depends entirely on unbuilt Breakout/metagame layer |
| 250-268 | Roguelike Loop — Within a Level, Rest State | COULD | stays | Tethers/rest-phase unbuilt |
| 268-269 | Between Runs (the Metagame) | COULD | stays | no metagame/hub code (`grep -rln -i metagame,meta_progress` → 0 real hits) |
| 271-274 | Scaling | COULD | stays | levels/fractal depth unbuilt |
| 276-277 | Run Failure | MIXED | core-death-ends-run half is IS (see docs/domain/victory-system.md, entity core-node loss = death is real); "no Breakout... pending allocation doesn't commit" half is COULD (Breakout/metagame unbuilt) | victory_system.gd owns run-end on entity death today; Breakout/metagame absent |
| 283-300 | Node Types — RGBW table (4-color, White = XP economy) | WAS | delete; superseded by the shipped 6-attribute roster | `entity_stat_board.gd:24-26`: `constitution`=CON/White=durability, `wisdom`=WIS/Gold=XP-economy, `perception`=PER/Purple — contradicts the table's "White = XP/turn lifeblood, no CON/WIS/PER". `docs/design/combat_system.md:163` already names this exact table (lore.md's) as one of the docs needing the White→CON / economy→Gold migration. |
| 302-303 | RGBW roster-expansion note (6 colors) | DUPLICATE | cut; `combat_system.md:146-182` already carries this table correctly and is the one actively migrated | matches `entity_stat_board.gd:20-26` field-for-field (STR/DEX/INT/CON/WIS/PER) |
| 306-322 | The Core (core node, death, aura, movement) | IS (mostly) | `docs/domain/node-hp.md` (aura/D-10), `docs/domain/allocation_system.md` (core-adjacency gate, dealloc/realloc reshaping) already cover the mechanics; keep lore.md's framing prose, cut the "core is a component that can be upgraded... aura falloff curve" claim if not backed | `CoreClass` aura is real (`entity/core/*.tres` `effects` arrays, e.g. ninja_core.tres:117 `aura_strike`); core-node-loss=death matches `docs/domain/victory-system.md` |
| 326-338 | Core Classes (Ninja / Hive / Edgelord blurbs) | MIXED | Ninja: DUPLICATE of `ninja_core.tres` description (roughly matches, minor drift — see below) — trim to a pointer at `core_classes.md`; Hive/Edgelord: COULD, stays as pointer only (full entries "live in core_classes.md" per this doc's own line 328, which already status-tags unbuilt classes per the 2026-09-29 pass) | shipped roster is Balanced/Ninja/Pacifist/Serpent + BasicEnemy (`entity/core/core_class_roster.tres`); Hive and Edgelord are **not** in it. Ninja's shipped description (ninja_core.tres:111-113: "halved Wisdom... intense but very-short-range aura") differs in specifics from lore.md's "small `skill_points_max`... steep penalty far from core" — close in spirit, drifted in detail. |
| 341-348 | SP Reservation — Wounds on the Tree | WAS | delete (or rewrite); the described "wound that locks capacity until healed by health_per_turn" model is superseded | `docs/domain/node-hp.md` "Turn-start regen (D-9) — replaces refill-to-full" section, and its "The dealloc/realloc refill is accepted, not a bug" subsection, explicitly states a lost node can be deallocated/reallocated back to full for a turn-budget price (1 DP) — no locked "Reservation" wound exists. Code's actual `reservation` concept (`systems/allocation_system.gd:443` comment "per-entity reservation") is the unrelated **staking** system (#337, cap-raising), not a combat-loss wound. `health_per_turn` as a stat name does not exist (`grep -rn health_per_turn` → 0 real hits; only unrelated `status_instance.gd`/test hits). See D-9 in `docs/adr/legacy-mvp-decisions.md`. |
| 351-361 | Magic & Spells — the Blue Design Space | IS (partial) / DUPLICATE | degree-gates-casting claim is real; full taxonomy lives in `docs/domain/spell-propagation.md` — trim lore.md to the theology framing, cut the mechanical restatement | `attack/spell/spell_def.gd:50-73` `min_degree` gates casting exactly as described, measured over the caster's own subgraph (matches "Degree is counted over the entity's own (owned) subgraph by default"). "Self-loops add degree" — unverified, self-loops unbuilt (see above), so that clause is COULD/UNSURE. |
| 365-409 | The Core — Extraction and Uprooting (+ charge economy) | COULD | stays | `grep -rln "Extraction\|Uproot\|uproot"` → 0 hits anywhere in `.gd`; `core_charge_capacity` appears **only** in design docs, never in code (`grep -rln core_charge_capacity` hits only `docs/design/*` and `docs/GDD.md`) |
| 412-422 | Constellation Geometry — compact vs. extended | COULD | stays (design framing); "leaves are now firing ports" is IS, matches ranged-fires-from-leaves model (`attack/formulas/ranged_damage.gd`) | partial IS undertone, but section as a whole is design commentary |
| 424-428 | Rings are strong (+ tensegrity) | DUPLICATE (mechanical half) | the triangulation/tensegrity blade mechanic is real and fully specified in `docs/domain/melee-blade-sim.md`; keep the theology framing in lore.md, cut the restated mechanic | `attack/plan/melee_attack_plan.gd:34` "phantom braces" comment + `docs/domain/melee-blade-sim.md` (triangulated mesh rigidity, §throughout) confirm the sim is shipped. Ring-as-2-edge-connected-defense (Islands/cut-vertex side) itself is real per Islands mechanic below, but "rings are hard to sever" as a *combat* claim (attacker needs two cuts) is not verified against any dedicated ring-defense code — mark that half UNSURE. |
| 430-440 | Islands (+ Lifeline / Lifelink addons) | MIXED | Island-dissolves-immediately is IS; Lifeline/Lifelink are COULD (unbuilt) | island logic is pervasive and real (`graph/graph_mirror.gd`, `systems/allocation_system.gd`, `combat/entity_combat.gd`, etc. all reference islanding). `grep -rln "Lifeline\|Lifelink"` → 0 hits; shipped addon roster (`skill_node/addons/*.gd`) is bunker/clamp/dot/fortification/skill_dust/spike_ring/toxin/watchtower — no Lifeline/Lifelink among them. |
| 444-449 | Node Components — The Addon System (Armor Ring, Reinforcement, Buffer, Winch) | WAS | delete/rewrite; none of these four names match the shipped roster | shipped: `bunker_addon.gd`, `clamp_addon.gd`, `dot_addon.gd`, `fortification_addon.gd`, `skill_dust_addon.gd`, `spike_ring_addon.gd`, `toxin_addon.tscn`, `watchtower_addon.gd` — no Armor Ring / Reinforcement / Buffer / Winch. Could be old working-names later renamed (fortification≈Armor Ring? watchtower≈Winch?) but no evidence ties them; flagged UNSURE-leaning-WAS, owner should confirm before deleting outright. |
| 452-460 | Death, Loot §1-2 (XP reward "proportional to level") | WAS (false claim) | delete/correct | `docs/domain/loot-system.md:8`: "the killer gains XP for the **territory** the victim held at death... **Never for its level.**" Direct contradiction of lore.md's "XP reward: proportional to the dead entity's level." |
| 458 | §2 BLITZ (Predator only) | COULD | stays (unbuilt, correctly scoped to an unbuilt class) | Predator is not in `core_class_roster.tres`; `docs/domain/loot-system.md` line ~66 lists BLITZ among mechanics explicitly "Deferred for now" |
| 460 | §3 Relic Node | IS (roughly) / DUPLICATE | matches shipped SkillDustAddon relic-node concept; `docs/domain/loot-system.md` is authoritative, trim lore.md to flavor only | `docs/domain/loot-system.md` "SkillDust drop... victim's former core node becomes a claimable relic" |
| 462-464 | Reaching the loot | IS | matches; DUPLICATE of loot-system.md's territory-reclaim framing | loot-system.md |
| 466-470 | STEAL / PROLIFERATE tension | COULD | stays, but should say "unbuilt" explicitly | `skill_node/addons/skill_dust_addon.gd:21`: "STEAL/PROLIFERATE choice and staining stay deferred"; `docs/domain/loot-system.md` also lists STEAL/PROLIFERATE, DAP bonus, staining as deferred and staining as "shelved indefinitely" |
| 474-497 | The Final Ascent — Apex Entity / Ophanim | COULD | stays | no Apex/Ophanim boss code; `victory_system.gd`/`docs/domain/victory-system.md` show no such condition today |
| 501-521 | Level Design — Field Themes | MIXED / UNSURE | some theme names are real, others unconfirmed | `docs/domain/procgen-v2.md:75`: `theme` field exists with values incl. "Classic Tree / Web / Spiral / …" — overlaps lore.md's "Classic Talent Tree," "The Web," "The Spiral." "Tech Tree Strip," "Constellation Map," "Cluster Web," and the Apex/Grand-Passive-Tree level are NOT confirmed in procgen code within this pass's budget — flag UNSURE, check `procgen/graph_procgen.gd` theme enum directly before deleting/keeping. |
| 525-537 | Themes (pitch/thesis prose) | COULD | stays | narrative thesis, not an implementation claim |
| 541-549 | Tone Notes | COULD | stays | writing guidance |
| 553-555 | Tone Reference: The JRPG Ending | COULD | stays | writing guidance |
| 559-581 | Open Narrative Questions | COULD | stays (explicitly a question list) | — |
| 585-607 | Visual Language table | COULD | stays | entirely Act0/Act2 speculative visual mapping, nothing to verify against code |

## Notes (lore.md)
- **Cross-doc breakage risk:** `metagame.md` and `first_session_walkthrough.md` both cite `lore.md` by name multiple times (e.g. "see `lore.md`" for the Fairy, the curse, the Final Ascent). Any section move/delete in lore.md (SP Reservation, RGBW table, Node Components) should grep those two docs' citations don't point at deleted content specifically (they currently reference sections, not line numbers, so low risk — but the Fairy/curse/Final-Ascent sections themselves must NOT move, since both other docs anchor to them by name).
- The **SP Reservation** and **Node Types RGBW table** sections are the two clearest "cleanup, would confuse everyone" cases in this doc — both describe mechanics the code has visibly moved past (D-9 regen model; six-attribute roster), and both risk a reader treating them as current.
- The **Core Classes**, **Death/Loot**, and **Magic & Spells** sections are largely redundant with `core_classes.md`, `loot-system.md`/`combat_system.md`, and `spell-propagation.md` respectively — worth trimming to one-line pointers rather than restating (partially) stale mechanics inline, per the doc's own "full entries live in X" convention already used for Core Classes.
- Node Components addon names (Armor Ring/Reinforcement/Buffer/Winch/Lifeline/Lifelink) need an owner call: confirm whether these are simply superseded names (delete) or a still-intended-but-unbuilt superset (keep as COULD) before acting.

---

# docs/design/first_session_walkthrough.md

| Lines | Section | Bucket | Destination / what to cut | Evidence (file:line or grep) |
|---|---|---|---|---|
| 1-11 | Title + "Why this doc exists" | COULD | stays | framing prose |
| 13-21 | Beat 1 — Boot | COULD | stays | Act0 adventure-game layer unbuilt |
| 23-37 | Beat 2 — Level up, Fairy nudges | COULD | stays | Fairy/adventure-layer unbuilt |
| 39-47 | Beat 3 — The crash | COULD | stays | crash sequence unbuilt |
| 49-63 | Beat 4 — Panel takeover | COULD | stays | unbuilt narrative transition |
| 65-75 | Beat 5 — Orientation (Core at a node, HUD arrives) | MIXED | HUD elements are IS; "no inventory, no map, no sword" is COULD/flavor | see below (HUD verification) |
| 73 | HUD buttons: "**Allocate, Move Core, Attack, End Turn**" + Skill Points pool + Initiative bar | MIXED/UNSURE | "End Turn" button and "Skill Points" panel and Initiative bar all confirmed real; "Allocate"/"Move Core"/"Attack" as dedicated **buttons** are NOT confirmed — allocation happens by clicking nodes directly, not a mode button, per the code inspected | `ui/hud/action_cluster/action_cluster.gd:43` `_end_turn_button.text = "End Turn"`; `ui/hud/turn_resources_panel/turn_resources_panel.gd:5` "Skill Points `CompositeBarGauge`"; `ui/hud/hud_root.gd:36` `InitiativeBar`. No `"Allocate"`/`"Move Core"`/`"Attack"` string literals found in `ui/hud/action_cluster/`. This is a walkthrough of an imagined UX, so treat as COULD-flavored, but flag the specific button labels as not-yet-real UI. |
| 77-85 | Beat 6 — First turn, expand, vision, NPC turn | IS (mostly) | matches shipped allocation + vision + turn-manager loop | `systems/allocation_system.gd` (allocate/vision extension is `VisionSystem`'s job — see `docs/domain/vision-vision.md`); `systems/turn_manager.gd` initiative loop matches "NPC TURN" framing |
| 87-99 | Beat 7 — Meet an entity (incl. "Coolness" stat callout) | MIXED | entity-vs-entity visibility real; the "+2 to Coolness" beat repeats the unbuilt `coolness` claim | see lore.md row on `coolness` above — not a real stat field (`entity_stat_board.gd`) |
| 101-111 | Beat 8 — Cut vertex / degree-2 bridge, leaf-count ranged tooltip "DEX//10" | IS | matches shipped ranged damage formula and degree mechanics | `attack/formulas/ranged_damage.gd:11`: "entity board intrinsic formula (`floor(DEX / 10.0)`)" — exact match to "Each fires DEX//10"; leaves-fire-ranged matches `.claude/rules/degree.md` + combat_system.md leaf/hub topology roles |
| 113-121 | Beat 9 — First volley, HP regen on enemy turn | IS | matches turn-start regen model (D-9), though under the *current* regen rule this is ramped healing, not a flat full reset unless undamaged long enough — minor drift | `docs/domain/node-hp.md` "Turn-start regen (D-9)": heals `node_healing + regen_stacks × node_healing_ramp` per turn, not necessarily full in one tick — walkthrough's "ticks back to 10/10" implies a full-refill-per-turn model closer to the pre-D-9 behavior. Flag UNSURE/minor-drift, confirm ramp values against playtest before calling it wrong. |
| 123-131 | Beat 10 — Setting up the snipe (aura, SP spend) | IS | matches core-adjacency SP-spend + aura mechanics | `entity/core/*.tres` aura effects; `systems/allocation_system.gd` |
| 133-147 | Beat 11 — The dismemberment (cascade dissolve, force-deallocate) | IS | matches shipped cut-vertex cascade | `CLAUDE.md` names `AllocationSystem.force_deallocate` as the primitive for exactly this; `systems/battle_system.gd`'s cascade (`cascade_started`, referenced in loot-system.md) matches "the three nodes... wink out in sequence" |
| 149-157 | Beat 12 — Session ends, guardrails | COULD | stays (design guardrails, not a code claim) | — |
| 160-178 | Appendix table (Questionable/Funny log) | COULD | stays | recap of unbuilt Act0/Act2 narrative beats |
| 181-186 | Open questions (playtest) | COULD | stays | explicitly a question list |

## Notes (first_session_walkthrough.md)
- This doc is almost entirely COULD by design (a spoiler-free narrative walkthrough of a game whose Act0/Fairy/crash layer doesn't exist yet) — the exceptions are Beats 6, 8, 9, 10, 11, which describe **in-run mechanics that do exist today** (allocation, vision, degree/leaf-fire ranged formula, cascade dissolve, aura). Those beats are accurate and don't need cleanup; they're closer to a (narrativized) domain-doc citation than a design fantasy.
- The one concrete inaccuracy worth a light touch: Beat 5's HUD button list ("Allocate, Move Core, Attack, End Turn") names three buttons that don't exist as such in `ui/hud/action_cluster/`. Low stakes (illustrative UX in a narrative doc), but if this doc is ever used to onboard a UI implementer, it could mislead.
- "Coolness" recurs here (Beat 7) exactly as in lore.md — same unbuilt-stat flag applies.

---

# docs/design/metagame.md

| Lines | Section | Bucket | Destination / what to cut | Evidence (file:line or grep) |
|---|---|---|---|---|
| 1-14 | What the Metagame Is | COULD | stays | no metagame/hub system in code (`grep -rli "metagame\|meta_progress\|meta_skill_tree"` over `.gd` → 0 real hits) |
| 18-30 | The Hub — locked space, rooms unlock, diegetic gating | COULD | stays | unbuilt |
| 32-34 | Class selection as a room (helmet) | COULD | stays; note it presupposes a class roster larger than shipped | shipped roster (Balanced/Ninja/Pacifist/Serpent) has no "worn artifact" selection UI |
| 36-42 | "Does the outside even exist?" / The hub is itself a vertex | COULD | stays | unbuilt, explicitly speculative |
| 46-60 | Meta Skill Tree — allocation is the dive, commit-on-completion | COULD | stays | no meta-tree allocation code exists |
| 62-73 | The intro sequence (scripted table) | COULD | stays | same Act0/Fairy dependency as lore.md's beat sheet |
| 75-97 | The steady-state economy (worked example) | COULD | stays | unbuilt |
| 99-105 | Re-allocation: tweaking your meta build | COULD | stays | unbuilt; also depends on in-run dealloc/reallocate, which IS real (`systems/allocation_system.gd`) but the meta-layer wrapper is not |
| 109-120 | Meta-Progression Content (stat carry, unlocks, run-essence) | COULD | stays | unbuilt |
| 124-133 | Mask-Off — Recommended Resolution | COULD | stays | narrative design recommendation |
| 137-145 | The Way Out — Metagame as Prison | COULD | stays | depends on unbuilt Breakout/Tether concept from lore.md |
| 149-159 | Open Questions | COULD | stays | explicitly a question list |

## Notes (metagame.md)
- This entire document is COULD — there is no metagame/hub/meta-skill-tree code anywhere in the repo. Nothing here needs cleanup for accuracy; it is a pure, consistent, forward-looking design doc, correctly filed.
- **Cross-doc dependency:** every section leans on `lore.md`'s Fairy/curse/Fractal/Breakout concepts (explicitly cross-referenced, e.g. line 64, 139, 141). If lore.md's Field/Breakout section were ever trimmed or reworded, metagame.md's citations would need a pass — but per the lore.md table above, that section is being *kept* (it's COULD, not WAS), so no break is imminent.
- No false-today claims found in this doc — it never asserts a mechanic exists in code; it consistently frames everything as design/TBD (e.g. "hub's physical identity... TBD", "Open Questions" section covering the load-bearing unknowns).
