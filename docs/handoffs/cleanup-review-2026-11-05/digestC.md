# Digest C (checked against origin/master; ADR index scanned, no ADR covers any of these)

### #428 Melee blade construction written three times
- **What:** two pairs of near-identical builders (plan vs SkillBlade) have already drifted once; a bug fixed in one copy was missed in the other.
- **Settled already:** duplication dies, one implementation per pair. MeleePreview is no longer a third copy (it calls SkillBlade). `MeleeAttackPlan.build_drivers` stays public (AI rollout uses it).
- **The fork:** where does the shared builder live?
  - A. Statics on existing classes: `BladeState.from_nodes(...)` and `BladeArcDriver.pivot_drivers(...)`. No new files. SPEC LEANED HERE.
  - B. New `BladeStateBuilder` class holding both. One extra file, same behaviour.
  - C. Plan owns it, SkillBlade calls plan. Inverts a dependency (SkillBlade has no plan handle).
  - **Recommend A** (no new class, lives beside the data it builds).
- **Is the fork real?** Barely. C is dead on its own logic; A vs B is taste. The drift to pin (plan omits `inner_radii`) checks out: on master the only `inner_radii` readers under attack/ are blade_state and skill_blade (visuals, line 891), so no sim behaviour change. Can go straight to Ready with A.

### #435 Finish FusedPanel migration
- **What:** all HUD panels still use the old GlassPanel, so the HUD cannot bloom its borders like the tooltip fan does.
- **Settled already:** GlassPanel gets deleted eventually (if A or B), sites move to `fused_panel.tscn`, per-scene `material =` overrides get dropped, 4-child split ordered after the pick.
- **The issue premise is false (verified):** FusedPanel exports only `glow`, `glow_edges`, `glow_energy`; border, gradient, corner and glow colour are baked on purpose (#391). So it is not a drop-in; ~9 sites (combat cards x6, gates, action cluster, xp_track, minimap) write knobs it lacks.
- **The fork:** who owns a panel's border/glow colour?
  - A. Uniform HUD, all overrides dropped. Cheapest, but kills combat cards' per-mode border (#390) and the gold gates/action-cluster borders. Visible regression.
  - B. Add 3 instance uniforms (`border_color`, `border_width`, `glow_color`) to FusedPanel; defaults = today's shared values. Batching survives. Corner radius and gradient stay baked (xp_track/gates/action cluster lose radius-10 and 90-degree gradient, eyeball pass). Partly reverses #391 for three knobs. SPEC LEANED HERE.
  - C. Keep GlassPanel for tinted sites. Two panel classes forever, no bloom where it is wanted; fails the issue's goal.
  - Sub-fork F2: delete GlassPanel (needs A or B) vs keep (only C). Follows F1.
  - **Recommend B** (one panel class, per-panel tint through instance uniforms; minimap alpha-1 is an owner eyeball call).
- **Is the fork real?** Yes, owner-only: it is a design call on how much the HUD may differ per panel, and it reopens #391's intent.

### #1186 mp:e2e 180s wall cap flips on the random seed
- **What:** the multiplayer e2e gate sometimes fails on a timeout just because the random seed gave a long game, and you cannot rerun the same seed.
- **Settled already:** `--seed N` (forwarded to host only, via a new `LobbyScreen.set_seed`) and print the seed on every verdict. No fork; spec says it can be filed Ready as its own child now. Seed fixes the map, not the fights (say so in help text).
- **The fork:** what does the wall clock mean?
  - A. Raise `--timeout` 180 -> 600 only. Tiny, still a wall-clock gate.
  - B. Turns are the verdict: reaching `--max-turns` (400) in sync with 0 divergences = pass "in sync after N turns"; wall clock stays only as a 600 s hang backstop. SPEC LEANED HERE. Cost: gate no longer proves a run ends.
  - C. B plus fixed default seed. Kills seed exploration; rejected as default.
  - **Recommend: ship the seed child now; decide F1 after measuring.** The turn-limit victory (limit 15) and `--lethal` landed after the evidence (2026-09-28), so the median-run-length premise is stale. If runs now end at ~15 turns, A is enough and B (redefining pass) is unneeded. Lean A.
- **Is the fork real?** Half. Seed half goes Ready now. F1 is a real owner call but probably dissolves after ~10 timed runs (no engine was available to the speccing agent).

### #859 Skipped starter slot mis-zips later participants
- **What:** if the map cannot seat everyone, `plan` returns fewer spawn points and GraphProcgen hands each later player a neighbour's spawn (camps get scrambled, last player gets none).
- **Settled already:** `plan`'s skip stays (pinned by `test_center_core_starters.gd:138`); nothing shipped hits it (first_level seats 14).
- **The fork:** where is the short return resolved?
  - 1. Never return short: place a best-effort point. Contract holds, but changes a tested behaviour and silently cramps spawns.
  - 2. Return null holes. Honest, every consumer needs null handling.
  - 3. `GraphProcgen.generate` checks `starters.size() == sum(camp_sizes)`, push_errors and returns the existing empty result. One guard, one file, test untouched. SPEC LEANED HERE (also the issue's own lean).
  - 4. Document only, same guard without surfacing the failure.
  - **Recommend 3** (guard at the consumer of the positional contract; lobby surfacing is a later child). Guard covers CampAnnulusStarters too (it also `continue`s at line 79).
- **Is the fork real?** Weakly. Owner already leaned 1/3 in the issue; 3 vs 4 is one guard. No ADR. Can go Ready with 3.

### #1026 SpellCatalog const list -> authored .tres catalog
- **What:** spells live in 28 `const` preloads plus a hand-kept `ALL` array; owner wants an inspector-authored catalog like #1008's.
- **Settled already:** `SpellCatalog extends Resource`, `@export var spells: Array[SpellDef]`, authored `.tres`, explicit array not folder scan (order is UI order). Identity via resource cache holds; pin with a test. Owner's quote settles replacing the array.
- **The fork:** how do context-free consumers reach a non-static catalog? (Verified: `EntitySnapshot` restore at :422 and `LootRoundCommand.granted_spell` at :68 are static/value-object; `LootSystem` and `MagicAttackPlan:170` also call `by_id`.)
  - A. Pass the catalog as an argument everywhere (`restore(..., catalog)`, `granted_spell(catalog)`). Pure DI, touches every caller and test.
  - B. Thin static door lazily `load()`ing the `.tres`. Smallest diff, but exactly the static default the owner rejected in #1008.
  - C. Catalog on the command context for the command path, A for snapshots. SPEC LEANED HERE.
  - **Recommend C** (matches #1008's `ctx` shape, avoids B's static door).
- **Is the fork real?** Yes, it decides blast radius (~10 test files, 3 sandboxes). Note `MagicAttackPlan:170` is a fourth consumer the spec's file list omits; the drone should handle it.

### #422 Split graph_procgen.gd into typed phases (hub)
- **What:** a 1614-line static class (issue says 1066) whose `generate()` is one giant function; tests and playgrounds reach into underscore-privates.
- **Settled already:** `RefCounted` phase classes under `procgen/phases/`, `generate()` stays the single entry and orchestrates, RNG salts/draw order unchanged, no shims, no behaviour change.
- **Proposed children:** 
  - 0. `ProcgenModifierRoller` - roll/pick/neutral statics; highest value, unblocks C3/C4, playground.
  - 1. `ProcgenAddonDraw` + subtype roll - blocked by 0.
  - 2. `ProcgenTopology` - triangulate/prune; re-points curl tool and connectivity test.
  - 3. `ProcgenArchetypeStamper` - assign/stamp.
  - 4. `ProcgenPlacement` - blockers, stakes, footprints.
  - 5. Orchestrator shrink - `generate()` under 150 lines, docs; blocked by 0-4.
- **Is the split sound?** Yes: ordered by value, serial landing in the one file, per-child re-pointing. Two tweaks: make the golden-hash test (3 seeds x 2 presets) its own first Ready child (call it child -1) rather than part of each; and note 1 touches the same seam as 0 so keep the chain strictly serial.
- **The fork:** only child names/paths, which are tentative. **Recommend:** confirm the split as is, no real design fork; hub can go to Ready-by-children. No ADR conflict.

### #441 Collapse six IncidentReducers into FoldReducer
- **What:** merge near-duplicate reducer files into one parameterised class.
- **Evidence (verified: 7 concrete reducers plus abstract base on master):** only 4 are pure folds (first 18 lines, max_damage 31, sum 20, cancel_if_multi 22). cyclone (55) does per-incident state and `visited` override; retract (26) extends MaxDamageReducer; expression (69) parses cached expressions. So "five to one" is gone; best case 4 -> 1 saves 3 tiny files. max/sum are each referenced by ~6 `.tres`/`.tscn` plus 7-9 scripts, so a FoldReducer enum rewrites spell defs and must keep `MaxDamageReducer.strongest` and the retract inheritance working. The HopDamageProgression counter-note stands.
- **Recommend: close** (won't do; payoff ~3 files vs churn in serialized resources and a worse `.tres` readability). If the owner still wants it, re-scope to "4 pure folds only, keep `class_name` per fold" as a fresh issue.
