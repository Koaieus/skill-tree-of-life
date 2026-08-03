# Focus

**What is live right now, and what is deliberately not.** One page, on purpose.

`ROADMAP.md` is the full inventory (and is stale). The GitHub board is the queue.
**This file is the tiebreaker**: if something isn't in a lane below, it isn't scheduled,
regardless of what its priority field says.

Set 2026-08-03. (Rewritten, not patched — see "When this file is wrong". The 2026-08-02
version is in git; don't diff it looking for lanes that moved, the lane *set* changed.)

## The rule that was missing

Priority fields and column drags don't cause work to happen — sequence and WIP do.

1. **WIP limit: 3.** No more than three issues in `In progress` across the whole board.
2. **One lane at a time.** Lanes below are ordered. Don't open lane N+1 while lane N has
   unfinished scheduled work.
3. **A fork is a Backlog issue, never an immediate start.** When implementing X reveals Y:
   file Y in `Backlog`, finish X, then re-read this file. "It's a small thing" is the
   phrase that has cost the most.
4. **Legibility ships, fidelity defers.** The visuals test: *does it change what the player
   can read and decide, or how it looks while reading the same thing?* Stat slabs, glass
   contrast, tooltip content → ship. Carved icon geometry, emblem substrates, rune art → defer.
5. **Crappy-now beats correct-later for anything not on the critical path.** A flat
   placeholder icon that ships this week outranks a carved one that ships never.
6. **`Ready` is a superset, not the queue.** 30 issues sit in `Ready`; ~13 are in no lane
   here. Being `Ready` means "a drone *could* take this"; being in a lane below means
   "a drone *should*". The lanes are the filter.

## Right now — the three

| # | What | Why it's takeable |
|---|---|---|
| **#268** | balance harness: scenario fixtures + ratio invariants | Fully specced, file-owned (`tools/balance/**`), invariants pre-named, thresholds ship as `TBD`. Drone-ready as written. |
| **#274** | Spell damage: one `power` × a `spell_damage` stat, ratio-only hop progressions | **Forks settled with the user 2026-08-03 → D-32.** Six knobs collapsed to three layers; `SETTLED` in the body closes every one. Size L. |
| **#362** | `test_fan_scene` trace test is run-order dependent | S-sized, acceptance + file ownership pinned, and it poisons `test:one` for anyone touching fan geometry — i.e. all of lane E. |

All three are in `Ready`. **`In progress` currently holds five other issues** — starting
these means clearing slots first (see "Known board violations"), not stacking to six.

## Lanes, in order

### A — Balance: the game plays fairly

The hard ordering: **measure, then mechanism, then pin.** Anything else re-tunes twice.

1. **#268** balance harness — the apparatus. Everything below is evaluated against it.
2. **#274** spell damage — the mechanism, with placeholder rates. **Settled as D-32**:
   `seed = spell_damage(source) × power`, and a progression *declares* whether it scales with
   the caster (`Multiply` / `ScaledAdd` do, `FlatAdd` deliberately does not). Deletes
   `seed_damage_fraction` + `AffineRamp` (zero users each). Migration is behaviour-preserving.

   > **#274 does NOT bounce back to `Needs design`.** It did that five-plus times because its
   > "open questions" section read as an invitation. There is no such section now — the body
   > has a `SETTLED` list of ten closed forks. If you think you found a fork, it is answered
   > there.
3. **#365** mana is unsettled — pool max and regen were never designed (**D-33 gate 3**).
   `Needs design`, P0. Blocks #278: tuning `mana_cost` against placeholder max/regen is
   tuning against noise. May warrant deletion of the resource rather than a retune.
4. **#278** spell balance pass — degree × reach × progression-kind × cost. **Not a drone
   unit**: it ships numbers, so it runs as a session with the user, after 1–3.
5. **#248** balancing hub (tracking).

Live inputs both #274 and #278 must respect:
- **D-31**: the node ratchet is **territory-wide** — one DP buys `delta × owned_nodes`.
- **D-33**: high INT is gated by **knowing the spell, casting degree, mana, and range** —
  never by tuning damage down. The degree ladder (1–2 low / 3 medium / 4 picky / 5+ endgame)
  and the deliberate tension between degree and reach are #278's real subject matter.
- **D-32**: which progression a spell wears is a *personality* choice, not just a number.
  `FlatAddProgression` is compressive on purpose — it is how a novice caster, or a bruiser
  who spots the right topology, gets a spell that does real work.
- Crits are topological now (Reverberator self-loop, Resonator convergence), so a spell's
  damage is a distribution over graph shapes.

Closed since the last FOCUS: #298 (CON→node_health as a board scalar, not a genesis param),
#346 (ratchet-heal — the cap was moved by a raw `base_value` write).

### B — Spell mechanics

**This lane ran unscheduled and shipped.** #351 (HopDamage) / #352 (Resonator) / #353
(Reverberator rename + self-loop crit fix) all landed 2026-08-02–03, plus the one-degree-API
work (`SkillNode.get_entity_degree`, `docs/domain/degree.md`). Rule 3 lost. It's in the lane
set now because pretending otherwise makes this file lie.

- **#356** unify `PropagationContext` across filter / step / reducer / crit. Debt the above
  created; **gates #355**. `Needs design`, one short `/swarmify` from takeable — the single
  open fork is "one context object vs. an immutable per-landing view over it", which matters
  because `crit_rng` / `global_visit_count` live on the long-lived one.
  **Sequence with lane A: #274 lands first** — it adds a `seed` parameter to a fourth
  pipeline interface, which is more evidence for the refactor, and #356 absorbs that
  signature rather than the reverse.
- **#354** spell preview UI: per-node damage/hit-count chips + skull-on-deplete. Phase 1 only
  (show everything, no gating). Legibility, not fidelity — passes rule 4. `Needs design`:
  chip visual language and the preview-scoped RNG snapshot are both open.
- #355 Chromatic Cascade — **parked on two things**: #356, and having actually played
  Resonator. Not takeable.

### C — Spells come from the map, not from birth

- #206 add spell grants to procgen pools
- #198 spellbook maintenance: grant-vs-learn, add/remove plumbing
- #207 visualize spell-grant presence on a node — **flat placeholder emblem, not a carve**

### D — Auras work and are readable

- #316 heal aura falls off per hop
- #340 node-local modifiers: bind() + cycle gate at the node seam
- #332 node-local formula modifiers, scaled off allocation
- #333 StatFormula can only read a pool cap, not `current`
- "which auras affect this node, with what local effect" → tooltip content, lane E

### E — Legibility

- #159 tooltip V2 (hub), now with its defects filed: **#343** stat slab visual spec,
  **#344** HoloPanel layout inversion, **#345** glass contrast + corner AA
- **#361** `core_panel.tscn` carries two skins — needs a *decision* (which skin wins), not a
  drone. Correctly parked in `Needs design`; it blocks nothing but will re-bite fan geometry.
- #238 prune stacked encoders
- #341 RimRing: allocation dial into the shader + archetype legibility
- #318 CARVE bake decode bug — **in review**
- #350 CARVE thin-stroke icons saturate `GRAD_SCALE` (follow-on to #318)

### F — Performance

- #53 performance budget + procgen scaling profile

### Enablers (pull in only when a lane needs them)

- **Test coverage cluster** (filed 2026-08-02, all `Ready`, all sized): #357 non-melee attack
  path, #358 the 7 unexercised propagation filters/reducers/steps, #359 graph layer,
  #360 integration tier (still `Needs design`). #358 is the natural companion to lane B.
- #249 sandbox host live-tab scaffolding + #347 the SkillNode lab entry point / knobs
- #349 procgen authoring DX: top-down knobs instead of six-deep nesting
- #324–#329 procgen v4 draw model (already decomposed, self-contained)

## Deliberately parked

Nothing here is closed. The design survives; the *scheduling* does not.

| Parked | Why |
|---|---|
| #165 pre-authored **clusters** in procgen | planarity + stitching research. Single-node splice (#180/#327/#330/#336) is kept — that one is cheap. |
| #245, #167, #342, #142 emblem/carve substrate + rune art | the Real Attempt. Fidelity, not legibility. Revisit after lane E ships flat versions. |
| #348 addon **placement** UX | wholly undesigned. #337 staking mechanic ships without it. |
| procgen "stamping" | detour; milestone 6 is already 8/10 closed. Don't reopen. |
| #313 ArchetypePolicy clustering dials | overlaps stamping and cluster work. Revisit after procgen v4 lands. |
| #355 Chromatic Cascade | gated on #356 *and* on having played Resonator. |

## Known board violations (2026-08-03)

Named rather than silently fixed, because clearing them is a scheduling decision:

- **`In progress` holds 5** (#159, #238, #248, #249, #198) against a limit of 3. #248 is a
  tracking hub and arguably shouldn't occupy a slot; the other four are genuinely parked
  mid-flight. Either finish one or drag the rest back.

Fixed in this pass: #298/#346 were closed but still sat in `Needs design`; #357–#359 and
#362 had no milestone; #354/#355/#356 were board items with no Status at all. `hygiene`
now reports clean.

**Lane B has nothing `Ready`** — all three of its items need a design gate pass first. That
is the honest state, and it is why lane A supplies two of the three current units.

## When this file is wrong

It will go stale, like ROADMAP.md did. That's fine — it's short enough to rewrite in
ten minutes. Rewrite it rather than patching around it.
