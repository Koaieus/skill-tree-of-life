# Handoff: domain-doc alignment sweep, 2026-08-23

**Spent when** each row below is either fixed in its doc or filed as an issue.
Delete it then.

Scope: `docs/domain/*.md` (40 files) read against the code, the issue tracker and
the decisions recorded on issues. **Domain docs are the primary** — where a doc
and the code disagree, this file says which one is describing reality, and where
the heading is genuinely unsettled it says so rather than guessing.

## Method, stated honestly

Not a uniform read of all 40. Ranked mechanically: `git log --since=2026-08-18`
over `docs/domain/` versus over the code tree, so **docs whose subject code moved
while the doc did not** became the deep-audit tier. The rest got a
title-and-opening-claim sanity pass plus an automated dead-path check. Tier is
noted per row.

Each row is **doc says → reality says → heading**. A `HEADING UNCLEAR` row is an
owner decision, and those rows are the agenda for the interactive session.

---

## Tier 1 — the ones that change what the remaining work *is*

### 1. ~~`multiplayer-sync-model.md` still rejects lockstep~~ — **RESOLVED 2026-08-24**

> **Spent.** The owner decided on 2026-08-24: **intent-up / confirmed-command-down
> stands**, lockstep rejected on new grounds (cross-OS libm in the blade sim;
> lockstep being contradictory with the partial-information destination).
> `docs/domain/multiplayer-sync-model.md`'s rejection section was rewritten to
> retire the three dead grounds and carry the live ones, and
> `.claude/rules/multiplayer-sync.md` now says the model was re-decided.
> #529 gained a **LAND** column first (commit `bc24e31`) so the half lockstep
> would have stood on was measured rather than assumed — clean, 84 landings, but
> scoped to one machine and therefore silent on the libm question that decided it.
> Filed out of the same session: **#547** (the one live stat-pipeline
> determinism violation), **#548** (upward channel), **#549** (roster seam).
> `docs/handoffs/lan-versus-transport.md` is deleted, its condition having fired.
>
> The row below is kept as the record of what the doc used to claim. Nothing in
> it is an open question any more.

#### (original row, for the record)

**Severity: highest. This is not doc tidiness — it gates the LAN date's last unit.**

**Doc says** (`multiplayer-sync-model.md:16`, and the always-on breadcrule
`.claude/rules/multiplayer-sync.md`): *"Host-authoritative, intent-up /
confirmed-command-down"*, stated as settled, with a `### Rejected: lockstep on
the shared seed` section at line 104. The doc has been partially maintained —
the melee-ordering clause is corrected in place, and the `Array.shuffle()`
clause is annotated as superseded — so the rejection now rests on **one**
surviving argument: *"There is no authority at all"* (line 109), plus the
hidden-information destination.

**Reality says** three things the doc does not mention **anywhere** (grep for
`#529`, `probe`, `snapshot recovery` in that file returns zero hits):

- **#529's probe reported clean, twice.** 773 commands, **zero divergences**,
  `skipped: 0` on every verb, 31/31 attacks re-derived, 86/86 landings
  byte-identical. Re-run at `4174f36` after #545. Numbers are on #463.
- **The reproducibility grounds are retired.** #530 shipped the stable hitscan
  sort; #512 shipped the AI emitting commands (deleting the frame-shaped
  `turn_delay` argument); the loot shuffle is now *explicitly exempt* as a
  host-only roll in the breadcrule itself.
- **The "no authority" ground was aimed at a different proposal.** It assumes
  **pure P2P** lockstep — no referee at all. What the owner pulled toward on
  2026-08-22 is **lockstep + snapshot recovery with the host still refereeing**,
  so an authority survives; #527's graph snapshot is the desync-correction
  channel classic lockstep lacks, which is a separate thing from authority and
  does not by itself create one.
- **The fog ground was withdrawn by the owner, on the record.**
  `docs/handoffs/lan-versus-transport.md` (deleted; its rejection section was
  folded into `docs/domain/multiplayer-sync-model.md`) recorded "Rotating
  authority forecloses fog. **Withdrawn.**" — the owner's fog vision withholds
  *derived* state
  — tier 3 — which is compatible with full replication of tiers 1–2. So the
  hidden-information destination is not the blocker the doc's rejection treats it
  as. Rotating authority was dropped for a different reason: ~1 ms on LAN against
  a handover-quiesce protocol.

**Careful with the shape of this claim.** It is *not* "every ground is retired,
therefore lockstep." It is: the doc's rejection rests on grounds that have either
been fixed in code, been withdrawn by the owner, or been aimed at a proposal
nobody is now making — and the doc records none of that.

**Heading: HEADING UNCLEAR — owner decision, and it is the last one on the LAN
critical path.** #529's spec is explicit that *"the decision is yours"*, and
FOCUS records the upward-channel unit as deliberately unfiled until the model is
picked. Do not let a doc pass resolve it by editing.

The one thing arguing against a straight "take lockstep": **caveat 3 from the
probe write-up** — broad in count, narrow in *shape*. Ten autopilot sweeps on one
hand-authored 71-node graph. Nothing there stress-tests the model; it confirms
the flip did not break it. #533 (rung 2, procgen'd graph) is what would widen it.

**What the doc should carry either way**, independent of which model wins: that
the rejection's three original grounds are retired, and that the live question is
decided by measurement. Right now a reader — human or drone — takes
"intent-up/confirm-down, settled" at face value from both the doc and the
always-on rule.

### 2. `attack_plan_system.md` does not know `CombatWorld` exists

**Tier 1, deep-audited.**

**Doc says** — nothing about the substrate that landed 2026-08-23. Zero mentions
of `CombatWorld`, `NodeCombat`, `resolve_against`, #535 or #536.

**Reality says** #535 introduced `combat/` (`combat_world.gd`, `node_combat.gd`,
`entity_combat.gd`, `dealloc_entry.gd`), #536 gave all three modes
`resolve_against(slice)` and **collapsed `BattleSystem`** so the host replays its
own record like any peer. `attack-timeline.md` covers this well; the plan doc is
the one a reader lands on from CLAUDE.md's `BattleSystem` row and it describes
the pre-#535 world.

Also carries two **dead paths**: `attack/formulas/magic_damage.gd` and
`attack/formulas/melee_damage.gd`.

**Heading: clear — fold in the slice substrate, or explicitly demote this doc to
"plan construction only" and point resolution at `attack-timeline.md`.** The
second is probably right: two docs both trying to own resolution is how this
drifted. Owner picks which.

### 3. `node-hp.md` describes a `take_damage` that no longer owns the mutation

**Tier 1, deep-audited.**

**Doc says** (lines 16-24) `SkillNode.take_damage(amount, source)` applies
mitigation, soaks the pool, routes overflow to the core, and emits the signals —
one method doing all of it.

**Reality says** #535 split that: `combat/node_combat.gd` holds the
**state-change** half of `take_damage` / `heal_damage` / `refill`, and the
**notification** half stays on `SkillNode` reached via `host.notify_*`.
`SkillNode.take_damage` still exists at `skill_node/skill_node.gd:1124`, so the
doc is not *wrong* at the call site — it is wrong about where the behaviour
lives, which is exactly what someone reads this doc to find out. It also cannot
explain how a shadow resolution damages nothing real.

**Heading: clear — document the live/shadow slice split.** No decision needed.

### 4. `effect-system.md` predates slice-aware effects entirely

**Tier 1, deep-audited.** Last touched 2026-07-20 — the oldest doc in the
deep tier.

**Doc says** effects act on an `Entity`.

**Reality says** `effects/effect_context.gd:16` opens with *"The owner slice this
context acts through (#520). NOT an [Entity]"*, carries a `world: CombatWorld`
property, and routes `add_local_modifier` through `world.combat_for(node)` so
identical `Effect` code recomputes against a shadow board. That is #520
(slice-aware `EffectContext` + `AuraEffect.recompute`), shipped.

**Heading: clear — the doc needs the slice section.** No decision needed.

### 5. `allocation_system.md` never mentions the command layer

**Tier 1, deep-audited.**

**Doc says** `allocate` / `deallocate` (gated) + `force_allocate` /
`force_deallocate` (primitives). Still accurate *as a description of the system's
own API*.

**Reality says** nothing outside `CommandApplier` calls them any more.
`systems/player_input_controller.gd:43` states the rule in its own docstring —
*"[Command] (#510) — never a direct `allocation_system.allocate(...)` call"* —
and `command_applier.gd:507/509/439` are the only production callers. The doc
that owns allocation does not say allocation is now reached through one serial
applier.

**Heading: clear — add the "who may call this" paragraph.** Cheap, and it is the
invariant a drone is most likely to break.

### 6. `seat-policy.md` and `seat_policy.gd` both say the menu drops `RunConfig` on the floor

**Tier 1, deep-audited. Half-stale, which is the dangerous kind.**

**Doc says** (`seat-policy.md:113-115`, and the same claim in
`session/seat_policy.gd:81-82`): *"The menu path does not reach here yet —
`scenes/meta/meta_root.gd` still drops its `RunConfig` on the floor pending
#457."*

**Reality says** #457's half landed: `meta_root.gd:95` calls
`GameSession.start(run_config)` and routes. But the *conclusion* stays true for a
different reason — `scenes/procgen_play_sandbox.gd:99-122` **builds its own
roster from scratch** (one `LOCAL_HUMAN` + N `AI`) and ignores
`GameSession.roster` entirely; it then *overwrites* the session's roster with its
own at line 125, with a comment saying so.

So: right answer, retired reason. A reader fixing #457 would conclude the seam is
now live. It is not.

**Heading: clear on the doc fix; the underlying work is item 3 of the Q1 gap list
below.** Restate the blocker as "the level does not consume the session's
roster", not "the menu discards the config".

Verified while checking: `PlayerInputController.set_input_frozen` (cited at
`seat-policy.md:96`) **does** exist, at `player_input_controller.gd:1124`. That
cross-reference is good.

---

## Tier 2 — accurate but silently outrun

### 7. `multiplayer-harness.md` + `.claude/rules/multiplayer-harness.md`: the ladder moved under them

**Doc says** the rung ladder with #532 as rung 1, #533 as rung 2, and *"An
intent channel upward is #463 (`Needs design`) — don't open it here."*

**Reality says** #532 **closed** 2026-08-23; #533 is open. The `Needs design`
label on #463 is still literally correct. The rule is one of the better-maintained
files in the repo and is broadly right.

Two gaps worth adding, both cheap:

- **#546 is not mentioned anywhere in the doc.** A harness host that cannot bind
  its port **keeps running**, and the client silently links to whoever *is*
  listening. This produced a run comparing a `dc5ef29`-era host against a
  current-master client, caught only by backtrace line numbers. The doc still
  documents 9099 as the default port — which is exactly the trap. **This
  corrupts the instrument while looking like a clean run**, so it belongs in the
  rule tier, not just an issue.
- The doc names `docs/domain/determinism-probe.md`'s port convention without
  noting that both #534 closing runs were taken on **9109** for that reason.

**Heading: clear — add the stale-host warning to the rule file, ahead of fixing
#546 itself.**

### 8. Dead file paths — mechanical, 13 of them

Found by extracting every backticked full path from every domain doc and
stat'ing it. Bare basenames excluded (too many false positives).

| Doc | Dead path |
|---|---|
| `attack_plan_system.md` | `attack/formulas/magic_damage.gd` |
| `attack_plan_system.md` | `attack/formulas/melee_damage.gd` |
| `procgen-v2.md` | `procgen/tags_constants.gd` |
| `procgen-v2.md` | `procgen/tags.tres` |
| `sandbox-framework.md` | `scenes/dev/allocation_vfx_showcase.tscn` |
| `sandbox-framework.md` | `spell_playground/playground_panel.tscn` |
| `sandbox-framework.md` | `tabs/18_tooltip_fan_tab.tscn` |
| `scene-composition.md` | `skill_node/addons/skill_node_addon.tscn` |
| `skillnode-emblem.md` | `skill_node/core_marker.gd` |
| `spell-propagation.md` | `test/unit/spell/test_all_neighbours_propagation.gd` |
| `stat-knobs-and-bins.md` | `ui/stats_panel.gd` |
| `stats_panel_refactor.md` | `ui/stats_panel.gd` |
| `tooltip-fan.md` | `tabs/70_bloom_tab.tscn` |

**Heading: clear.** Note `ui/stats_panel.gd` is dead in two docs —
`stats_panel_refactor.md` may be a spent doc rather than a stale one; check
before repairing rather than after.

---

## Tier 3 — sanity pass only, no findings

`degree.md`, `ownership-vocabulary.md`, `breadcrules.md`, `hdr-color.md`,
`rendering-performance.md`, `godot-workflow.md`, `modal-system.md`,
`scene-composition.md`, `presentation-clock.md`, `victory-system.md`,
`loot-system.md`, `vision-system.md`, `determinism-probe.md`,
`attack-timeline.md`, `game-session.md`, `issue-workflow.md`, `seat-policy.md`
(beyond item 6), `sandbox-framework*.md`, `procgen*.md`, `stat-*.md`,
`emblem-bake.md`, `skillnode-emblem.md`, `melee-blade-sim.md`,
`spell-propagation.md`, `strikethrough-toast.md`, `tooltip-fan.md`,
`overlay-field-rendering.md`, `node-hp.md` (beyond item 3),
`allocation-vfx.md`, `stats_panel_refactor.md`.

Opening claims read true against the code; **not line-by-line verified.**
`attack-timeline.md` and `determinism-probe.md` are the two best-maintained docs
in the corpus and were used as the reference for what "aligned" looks like.

---

## Where the code stands for 1-host-1-client versus (Q1 context)

Recorded here because item 6 above is one of these, and because FOCUS is stale on
several. **Not a decision — an inventory.**

| Gap | State |
|---|---|
| **Upward channel (client→host intent)** | **Does not exist.** `CommandLink` sends only on `Mode.BROADCAST` (`command_link.gd:189`). Unfiled on purpose — blocked on item 1's decision |
| **Join handshake never fires in production** | `send_graph_snapshot` / `send_run_setup` (#527/#528) have **zero non-test callers**. `GameRoot._greet_if_linked` sends `hello` only. Survivable, per the row below |
| **Procgen is genuinely seed-reproducible** | Checked, not assumed: every roll under `procgen/` goes through an `rng` instance — no bare `randi()`/`randf()`/`shuffle()` in the pipeline (the one global `randi()` is `playground_panel.gd:298` seeding its own dev RNG). So `HostJoinScreen`'s "both type the same seed" hint **works**, and #527's snapshot is robustness, not a hard prerequisite |
| **Level ignores the session roster** | `procgen_play_sandbox.gd:99-125`, per item 6 |
| **Menu forces `COOP_HOTSEAT` for networked runs** | `meta_root.gd:59/63`. `RunConfig.Mode.VERSUS` exists and is never constructed |
| **No authority gate on human input** | `CommandApplier.is_authority` is read by `ai_controller.gd:92` and `skill_dust_addon.gd:246` — **not** by `PlayerInputController.can_player_act()`. Latent divergence on the menu path; the harness dodges it by having no human |
| #533 rung 2 | Open, `Backlog` |
| #546 stale-host bind | Open, per item 7 |
| #516 versus map preset | Open, `Needs design` — playability, not correctness |

#519 and #521 are the fog/stat-delta **destination**, not gates. Listing them as
remaining work would pad the estimate.

## FOCUS.md corrections found in passing

- The #458 row still says loot picks are un-routed. **#522 closed** — that verb
  crosses now, and the harness rule already says so.
- The #463 row describes #527/#528/#530/#531/#532 as `Ready` children. **All
  five closed** 2026-08-23; #463 shows 4/4 sub-issues complete while the hub
  itself stays open on the unfiled upward channel.
- `docs/handoffs/lan-versus-transport.md` declares its spend condition as
  "#529 has produced a number **and** the sync model is chosen". **Half has
  fired** — updated in this pass.
