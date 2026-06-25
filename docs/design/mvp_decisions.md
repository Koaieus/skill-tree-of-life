# MVP design decisions log

Authoritative current state for design decisions that gate MVP work. Where this doc disagrees with older docs (`combat_system.md`, `spells.md`, etc.), **this doc wins** — the older docs predate implementation choices and may contain superseded sketches.

Each decision lists: the question, the resolution, the rationale, and the implementation status.

---

## D-1 — Melee damage source

**Question:** edges vs blade-nodes vs both deal damage? Cycle/face bonus?

**Resolution:** **Blade-nodes deal damage; edges become inert.** No face/cycle bonus for MVP — door is left open for post-MVP.

**Rationale:** Visual weight already lives in the nodes; edges are spaghetti between them. Building triangulated/rigid blades still rewards the player because rigidity affects whether the swing actually contacts enemy nodes (a floppy blade may not sweep through), even without an explicit damage bonus. Other damage levers are richer: stat scaling, blade velocity, damage envelope, swing direction, easing of the drive.

**Impl status:** `attack/melee/skill_blade.gd` currently emits damage for both edges and nodes. MVP issues:
- Make edges inert (no `EDGE_DAMAGE` emission).
- Add **STR//10** scaling to blade-node hit damage.
- Add **CW/CCW toggle** for swing direction (small UX win — exposed per attack-plan or per-entity stat).

**Deferred (post-MVP):**
- Face/cycle bonus model (see `combat_system.md` §Melee for the design sketch).
- Drive-easing variations (different pivot-driven motion curves).

---

## D-2 — Magic cast range scaling

**Question:** does cast range scale with source-node degree, INT, or stay flat?

**Resolution:** **INT-scaling, not degree-scaling.** Introduce a new stat `spell_range` (scalar) that INT contributes to via an intrinsic modifier. Per-spell base range becomes `base × (1 + spell_range_pct)` via `LocalStat`. **Degree gating remains the sole degree-axis effect on spells.**

**Rationale:** Single scaling axis keeps balance tractable. Degree already gates *which* spells are available; making it also scale *how far they reach* compounds non-linearly. INT-scaling rewards build investment and aligns with stats-system idioms.

**Open follow-ups (post-MVP):**
- "Overqualified casting" bonuses: when source-node degree exceeds `min_degree`, grant *something other than range* (extra damage tick? extra fork? penetration?). To be designed; not MVP.
- A 1-degree spell cast from a 5-degree hub should NOT outclass a 5-degree spell cast there — verify via balance pass.

**Procgen tie-ins (post-MVP):**
- Add `spell_range` to procgen modifier pool, weighted toward INT-archetype nodes.
- Self-loop generation today is naive per-node RNG. Want a better draw mechanic that supports rare-but-possible *double* self-loops on a single node (an instant magic powerhouse). Carve as a procgen issue.

**Impl status:** Cast range is flat per-spell today (`HopRangeFinder.max_hops`, `EuclideanRangeFinder.max_distance`). MVP issue: add `spell_range` stat + intrinsic INT contribution + RangeFinder consumption.

---

## D-3 — Addon application model

**Question:** per-unit vs per-node chance, unique vs stackable, ratio tunability.

**Resolution:** **Current architecture is correct, keep it.** Per-node procgen application via `AddonPolicy.slot_count_weights`, `weight_profiles`, and `pool`. `SkillNodeAddon.unique` flag enforces "at most one of this addon per carrier" — kept. Stacking up to slot-count (default 3) — kept.

**Rationale:** Aligned with design intent and implementation; no architectural change needed.

**MVP work:** Balance pass — **tune procgen ratios/spread** so addons feel meaningful and not overwhelming. This is empirical: roll a few procgen runs, eyeball distribution, adjust `slot_count_weights` and per-pool weights. Carve as a balance issue (not architecture).

**Deferred (post-MVP):** Specializations (Corrupted / Crystallized / Anchor / Doubled) per `skill_node_specializations.md` — separate system from addons, not yet implemented.

---

## D-4 — Spell gating: degree definition

**Question:** true graph degree vs allocated-degree?

**Resolution:** **Allocated-degree** — count only edges to friendly allocated neighbors via `EntityNavigator.get_degree()`. Already implemented and matches design intent.

**Rationale:** Allocated-degree is meaningful (it's the player's *committed* topology), creates real gameplay tension around what to allocate, and is already wired correctly.

**Impl status:** ✅ Done. `SpellBook._node_meets_source_requirements()` uses `attacker.navigator.get_degree(source)`. No further action.

---

## D-5 — Damage type taxonomy

**Question:** R/G/B color triangle (per design doc) vs PHYSICAL/MAGIC/TRUE (current impl) vs hybrid?

**Resolution:** **Defer entirely. MVP ships with single `armor` stat only.** Damage taxonomy is post-MVP.

**Rationale:** Scope discipline. The current `Mitigation` (flat `max(min_damage, raw - armor)` + TRUE bypass) is sufficient for MVP combat to feel meaningful. Building out R/G/B colors AND per-type resists AND procgen affixes for those resists is a milestone in itself.

**Post-MVP:** Re-open as part of "Content depth" milestone. The R/G/B design from `combat_system.md` is the leading proposal but will need a fresh look at that time.

**Impl status:** No change. `DamageInstance.Type` enum (PHYSICAL/MAGIC/TRUE) stays as-is; `armor` is the only defensive stat.

---

## D-6 — Battle-mode UI

**Question:** keep 3-button radio toggle vs world-context fan-out on node click?

**Resolution:** **Contextual action bar (SC2-style).** Click an own-node → 3 action buttons (Melee / Ranged / Magic) appear in the bottom-center action bar. Clicking one transitions to per-action context:
- **Magic** → bottom bar morphs into spell-list bar; click a spell to arm.
- **Melee** → clicked node becomes the pivot; standard blade-build flow follows.
- **Ranged** → enters target-selection mode; existing leaf-firing plan logic applies.

**Ranged + non-leaf source node:** the Ranged button is **grayed out with a tooltip** ("only leaf nodes can fire") when the clicked node isn't a leaf. Teaches the mechanic without removing the button.

**Rationale:** Better real-estate usage (bottom bar serves multiple purposes), shortcuts the click-mode-then-click-source flow, and aligns with familiar RTS unit-selection idioms. Not as game-world-native as floating action buttons around the node, but achievable with much less UX churn and remains scalable to future per-node abilities.

**Impl status:** New work. `ui/attack_mode_bar/` becomes a contextual action bar (or is replaced); selection routed through clicked-node state; spell picker bar consolidates into the same bar.

**MVP must-haves alongside:**
- Launch-attack as a FAB over the central viewport.
- Dim battle UI when AP = 0 (with tooltip).
- Spell tooltip becomes a scene (not multi-line text).
- Spells in the bar: castable first, uncastable dimmed with reason tooltip.

---

## D-7 — NPC factions

**Question:** single-faction (all NPCs hostile to player) vs multi-faction?

**Resolution:** **Single faction for MVP, with one future-proofing change:** add `Entity.faction: StringName = &"npc"` (player gets `&"player"`). All hostility checks today (`owned_by != attacker`) keep working; multi-faction is a one-line filter swap later (`other.faction != self.faction`).

**Rationale:** Zero behavior change today, trivial code addition, removes the future refactor risk of NPCs accidentally fighting each other when multi-faction lands.

**Impl status:** Tiny code change. New field on `Entity`, default per type, no consumers wired yet. Carve as small `core` issue.

---

## D-8 — Announcer toaster stale-drop policy

**Question:** when player rapidly end-turns, queued toasts lag and announce phases already past. Rule?

**Resolution:** **Drop-stale on dequeue.** When `BannerLayer` pops the next pending banner, check it against the current entity + phase: if the banner's announced phase has already been exited (or the announced entity's turn has ended), drop the banner instead of playing it. Plus: **dedup adjacent identical entries** (e.g. two `TURN_STARTED` for the same entity).

**Rationale:** Banners exist to tell the player what's happening NOW. A banner for a phase already over is noise. Drop-on-dequeue (not drop-on-enqueue) ensures we don't drop a banner that becomes relevant by the time we get to it. Dedup catches the most common spam shape.

**Impl status:** `ui/banner_layer/banner_layer.gd` — add `_should_skip(req)` check before play, plus a `BannerRequest.context` field carrying `{entity, phase}` for the check. Carve as `ui` issue.

---

## Decisions log

- 2026-06-25: All 8 D-decisions resolved in roadmap session. Issues to follow.
