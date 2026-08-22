# Focus

**What is live right now, and what is deliberately not.** One page, on purpose.

`ROADMAP.md` is the full inventory (and is stale). The GitHub board is the queue.

Rewritten 2026-08-18. **This file no longer carries a backlog.** Everything that
used to live here as prose — the playtesting findings, the meta-shell units, the
perf follow-ups, the tier-ladder forks — is now filed as issues, and the
**`LAN 2026-08-31` milestone** is the burn-down for the date. What remains here
is the one job a milestone cannot do: saying what is **next**, and by omission
saying everything else is not.

Closed work is not recorded here. Git history and the issue tracker hold it.

## North Star

The bar this project is aiming at, so a perf or scope call has something to be
judged against:

1. **A 2000-`SkillNode` map runs smoothly at 144Hz, at 1440p.** The dev sandbox
   is *not* 1440p, so local framerates are optimistic about resolution. This is
   the number that decides whether a rendering or recompute approach is
   acceptable — see `.claude/rules/rendering-performance.md`.
2. **The player can control that**: windowed / fullscreen / borderless,
   resolution, vsync, framerate cap. Substrate shipped; the settings are #462.
3. **LAN-playable**: single-player, seeded runs, and hot-seat coop by
   **2026-08-31**, with versus if it fits. That is milestone `LAN 2026-08-31`.

## Why this file exists

The board sprawls. This file is the antidote: it names what's actually next, and
by omission says everything else is not.

There is one queue for "needs design" work — **#261** (the swarmify pipeline). If
an issue is in `Needs design`, it sits there until a `/swarmify` pass settles its
forks and moves it to `Ready`. **FOCUS does not catalog `Needs design` work.**

## The rules

1. **WIP limit: 5 — and it is the weakest rule here.** The real failure mode is
   things *rotting* `In progress`. Judge the column by age, not by count.
2. **Any amount of lanes at a time.** Lanes below are grouped by topic.
	Ideally we close out lanes one by one, but any work closed on any lane is
	always welcome.
3. **A fork is a Backlog issue, never an immediate start.** File it, finish the
	current unit, re-read this file. If the forked off issue is relevant to FOCUS, fold it in here,
	if it's more like "nice to have", keep it backlog. Most often an issue wants
	things that lead to 1 or more related issues being filed to get it done, this
	means that it's more about tracking what needs to be done *for that unit* so
	by all means it should be done ASAP in that case. But useful to split so an
	agent can be pointed at it to complete it, instead of "read half of this issue
	 then do that one paragraph".
4. **Legibility ships, fidelity defers.**
5. **Crappy-now beats correct-later for anything not on the critical path.**
6. **`Ready` is a superset, not the queue.** Being `Ready` means "a drone *could*
   take this"; being named below means "a drone *should*".

## The LAN — milestone `LAN 2026-08-31`, hub #456

North Star #3, with a date on it. **Membership in that milestone means "this
gates the 08-31 build"** — read it with `mise gh-project -- roadmap`, which
prints open / ready / needs-design counts per milestone, so the milestone answers
"what is left, and what still needs its forks settled" without this file.

Already shipped under the hub: tier-S plumbing (`SceneDirector`, `session/` data
classes, `GameSettings` + reflected settings menu, `BuildInfo`,
`SkillNode.stable_id`, merged as `db80618`) and the menu shell (`5053afc`).

| # | Unit | State |
|---|---|---|
| ~~#473~~ | ~~Design session: the multiplayer sync model~~ | **Decided 2026-08-18** — `docs/domain/multiplayer-sync-model.md` |
| **#457** | `GameSession` + one-shot seed resolution | Sits in `Ready`, forks still open — **owner decision**. The 2026-08-21 call shrank it: the seed is a procgen input, **not** a determinism contract over combat or loot |
| ~~#474~~ | ~~Split world mutation from VFX in `launch_attack`~~ | **Shipped.** VFX is a pure observer. (Mutation was at t=0 here; #504 then moved it onto the reveal clock — see the row below) |
| ~~#488~~ | ~~Presentation clock v2~~ | **Shipped 2026-08-21** as design **B** — the world mutates on the reveal clock; no view store. `docs/domain/presentation-clock.md` |
| **#458** | `Command` + `CommandApplier` (rewritten) | **All four children shipped 2026-08-21** (`b1448fe`, `50d5556`, `2e7b67a`, `6f810be`). One verb is left un-routed: **loot picks** — `CommandApplier` push-warns on `PickLootCommand` and a mirrored client diverges the moment somebody picks. **Do not re-enumerate children here** — this row rotted once by doing that; read `mise gh-project -- roadmap` for live child state |
| ~~#475~~ | ~~Author real faction camps~~ | **Shipped 2026-08-21** — so #459's allied-humans prerequisite is met |
| **#459** | Hot-seat coop: the three rebind seams | **`Ready` — this is the LAN commitment, and it is one issue.** Needs nothing from #511/#512/#463 |
| ~~#460~~ | ~~`VictorySystem` — a run that can end~~ | **Shipped 2026-08-21.** Owner call settled it: last camp standing, pluggable, blockers inert. `docs/domain/victory-system.md` |
| **#461** | Menu shell follow-up: scenic screens, roster wiring, styling | Sits in `Ready` but still carries open forks — see "Known board violations" |
| ~~#462~~ | ~~Display settings (window mode, resolution, vsync, fps cap)~~ | **Shipped 2026-08-21.** North Star #2 is met |
| **#463** | Versus: `NetworkTransport` + ENet lobby | **Hub, swarmified 2026-08-22.** The transport seam, both transports and `CommandLink` already shipped — the body was 60% stale. Four `Ready` children: **#527** graph snapshot, **#528** run-setup replication, **#531** mount + IP screen, **#529** determinism probe (plus **#530**, hitscan sort, which gates it). The sync model is **not** settled — see below |
| ~~#499~~ | ~~Ranged volley: arrival ramp + apply in arrival order~~ | **Shipped.** `OutcomeApplier` orders hits by `arrival_time` |

Also in the milestone, by owner call: **#403** Tech Seeds, `Needs design` —
"should be easy to get *something* going", so it wants a fast swarmify, not a
deep one. (**#300** removable node blockers shipped 2026-08-21, which unblocks
#403; its deferred chokepoint-placement heuristic is #508, unscheduled. **#412**
armed-mode viewport glow shipped 2026-08-21 — the glow values are owner-tunable
`shader_parameter`s, see the glowup section.)

**Order, restated 2026-08-21 after the sync lane's big day.** Multiplayer is a
four-layer stack and **three layers are done**:

1. *The model* — #473, `docs/domain/multiplayer-sync-model.md`. **Decided.**
2. *Mutation must not be frame-ordered* — the presentation-clock v2 arc
   (#488–#494, #504), #474, and the attack-timeline children #501/#502/#503.
   **Shipped.** This was the real blocker: you cannot broadcast a world change
   whose timing a dropped frame decides.
3. *The command layer* — #458. **Shipped, minus loot picks.** There is now
   exactly one serial path through which the world mutates, it speaks in
   serializable commands, and every player and AI verb reaches it.
4. *The transport* — #463. **Two thirds shipped without anyone noticing**, and
   swarmified 2026-08-22 into four `Ready` children. See the row above.

So the remaining order is short:

- **#459 is the LAN commitment and it is one issue.** Hot-seat coop needs
  nothing from a transport, and #475 (its allied-humans half) landed. Pull it
  first.
- **A verb that never becomes a `Command` is not #463's problem, it is #458's.**
  `CommandLink` mirrors everything the applier handles; what does not cross the
  wire is what nothing submits. Two were found 2026-08-22 — the player's End
  Turn button (fixed, it now goes through
  `PlayerInputController.request_end_turn`) and loot picks (still open). When a
  verb misbehaves in a mirrored sandbox, check the submission site before the
  transport.
- **The harness is a ladder now, and each rung defines "done" for a layer.**
  Rung 1 **#532** (`Ready`): the existing `mp_dev_sandbox`, where no state
  crosses by construction — so a failure there is a *messaging* bug and cannot be
  a serialization bug. Restores the AI opponent (the "#512 makes the AI bypass
  the applier" justification in the code and the doc is **stale** — #512 landed),
  sweeps every verb, and asserts turn-advance + seating. Rung 2 **#533**
  (`Backlog`, blocked-by #527/#528/#531): a procgen'd scene where the graph and
  run settings actually cross. Rung 3 is the client acting, and waits on the
  upward channel. Rung 4 is the real menu.
- **#463 is open, and its sync model is decided by measurement, not argument.**
  `CommandLink` wave 0 is one-directional: the client is a spectator with a real
  applier. What replaces that is genuinely undecided — the owner pulled toward
  **lockstep + snapshot recovery** over intent-up/confirm-down on 2026-08-22, and
  **#529 produces the number that picks it**. #527, #528 and #531 are needed
  under either model, so they start with no bet made; the upward-channel unit is
  deliberately unfiled until the probe reports. Context:
  `docs/handoffs/lan-versus-transport.md`.
- **#457 does not gate any of this.** The 2026-08-21 owner call made the seed
  procgen-only, and #458's entity ids are minted by `Graph` the way `stable_id`
  already is.

**The LAN date's risk is not the sync stack.** It is #498 step 3 (below), plus
#461 and #457 sitting in `Ready` with their forks still open.

**The attack-timeline contract is IN the milestone** (owner call 2026-08-20,
superseding the same-day call that parked it): `docs/domain/attack-timeline.md`,
hub **#500**. The three mode moves — #501 magic / #502 melee / #503 ranged — all
landed 2026-08-21, and **#507** (crits) closed the same day — melee and ranged
now roll through one shared `CritRoll`. What is left under the hub is **#498**
(AI-preview accuracy; steps 1–2 shipped, **step 3 is the outstanding work** and
per its own owner call is plausibly the largest remaining unit in the milestone).
#498's spun-off **#506** (a cloned `StatBoard` must react) is `In review`.

**#501 shipped only half of itself.** Its wave-loop move — magic's gate lives in
candidate selection inside `SpellResolver.resolve()`, so live selection needs
`resolve()` to mutate something throwaway — is recorded as inherited scope on
**#498 step 3**, along with retiring `BattleSystem`'s second apply for magic.
Only the `arrival_time` stamping landed.

The cross-unit seam that governed those waves still holds for anything new:
`OutcomeApplier` sorts hits by `arrival_time`, so **each mode's stamps must be
monotonic in that mode's own intended application order**, or a sibling unit's
sort silently reorders it.

## Perf — as good as fixed, *for now*

The framerate collapse is diagnosed and the big fix landed: `FogOverlay`'s
per-element dimming cost 78.7ms/frame at 200 owned; #414 ported nodes to
self-shading in their own shader (`65a69fc`) and it is 0.2ms. Before that,
`VisionCircles` took the vision recompute from 19.4ms to 6.5ms.

Still open, all measured and filed — pull in if the framerate misbehaves again:

- **#439** AuraOverlay refresh coalescing — a plausible second per-frame repeater, still unmeasured.
- **#470** StatBoard dirty-mark/batched-flush. CON allocation is O(owned); worst-case `force_allocate` is 5.9ms at 200 owned.
- **#471** `VisionCircles` cell size == max radius, so a query scans every circle in the tile.

**The standing rule here: profile before touching anything.** Twice now the
culprit was a quadratic CPU walk and not the GPU. Benches live in `test/perf/`
(`bench_allocation_cost.gd`, `bench_alloc_cost_attribution.gd`,
`bench_fog_refresh_cost.gd`), outside `.gutconfig`'s `test/unit/` and named
`bench_` so nothing collects them by accident.

**Exit condition, not yet met:** 2000-node map, 200 owned, allocation at a steady
144fps at 1440p — needs the owner's eyeball in the real game.

## The glowup — owner tuning, not drone work

**#392** (attack + allocation VFX emissive) and **#393** (strikethrough toast
trace glow) are code-complete on master and **not tuned** — glow values, and for
#393 a scope the owner grew: the trace tip should read as a blooming laser cutter
cutting across, not a static line. **#371** (the foundation hub) closes when they
do. Follow-ons #140 (aura fields span edges) and #257 (node-shatter texture) are
not scheduled.

## Everything else, by topic

Pull these in when something needs them; none are scheduled against the LAN date.

**Node-local & aura mechanics** — #316 heal aura per-hop falloff, #356 unify
`PropagationContext` (gates #355). Both `Needs design`.

**Content from the map** — #327 keystones (needs a *real* design pass: named
examples, several back-and-forths, no coding yet), #330 wire the 4 landmark
keystones into procgen, #336 keystone-as-`.tscn` hub, #206/#207 spell grants in
pools. All `Needs design`. **#472** tier-ladder / roll redesign is the big one
here — roughly the 8th pass at the roll model, three tangled forks, owner session
only.

**Legibility** — tooltip V2 cluster (#343, #344, #345, #281), #354 spell preview
UI, #361 `core_panel.tscn`'s two skins (a decision, not a drone unit), #380
tooltip-fan inherited panels (`In review` — owner wants to drive it first), #362
`test_fan_scene` overlap test (`Needs design`: the reframe is panels that
push/pull each other, sidestepping overlap detection rather than fixing it).

Plus a standing clarity ask, deliberately not yet split into issues: the
**highlight-ring language is overloaded** — hover yellow outline, Manage-mode
allocatable golden-orange ring, attack-plan targeting yellow/red ring — all three
competing with the WIS gold-rim signal, while unallocated nodes read dark gray.
It wants one visual design pass, not more colours.

**Balance — deliberately last.** #373 CON→health remodel (P0), #365 mana pool max
+ regen (P0, blocks #278), #278 spell balance pass (an owner session), #248 the
hub. (#366/#367, the balance harnesses, shipped.)

**Onboarding** — #49 tutorial. (#403 is in the LAN milestone; #300 shipped.)

**AI** — v1 shipped and closed. #410 `AiWeights` archetype personality
(unblocked, unscheduled), #47 strategy-pattern controller (v2), #394
faction-shared vision (a difficulty lever). Note #473 has to say where AI sits in
whatever sync model wins.

**Ergonomics filed 2026-08-18, cheap Sonnet-tier units** — #464 two CommandTray
buttons lit at once (root-caused), #465 button icons + active/inactive states,
#466 reform last blade, #467 `StatModifier.resource_name`, #468 `@export_group`
the procgen config, #469 edge width vs. zoom + bolt dots (wants a design pass).

**Enablers** — #249 sandbox host live-tab scaffolding (7/12 closed; board says
`Needs design`, reconcile before scheduling more), #349 procgen authoring DX
(`Backlog`).

## Deliberately parked

| Parked | Why |
|---|---|
| #165 pre-authored clusters in procgen | planarity + stitching research. |
| #245, #167, #342, #142 emblem/carve substrate + rune art | fidelity, not legibility. |
| #348 addon placement UX | wholly undesigned. |
| #355 Chromatic Cascade | gated on #356 and on having played Resonator. |
| #313 ArchetypePolicy clustering dials | overlaps stamping/cluster work. |
| #23 save/load | metagame; and #457 settles seeds first. |
| #256, #257 blade node visuals, InnerDisk shatter | VFX juice. |
| #197 double-crit as a tier | enhancement on working crits. |
| #409, #407, #408 edge sharpeners, velocity damage, Clamp's second use | design forks with no shape yet. |
| procgen "stamping" | detour; don't reopen. |

## Known board violations

As of 2026-08-22: **#461 is fixed** — moved to `Needs design`, per the owner's
call that an issue with open forks belongs there. **#457 remains** in `Ready`
carrying the `design` label, and the label is honest: its forks are genuinely
open, so `Ready` is what is wrong there. Don't let a drone pull it until a
`/swarmify` pass settles it.

Don't trust this section's date — run `mise gh-project -- hygiene`.

## When this file is wrong

It will go stale — but it should now go stale *slowly*, because it holds pointers
rather than content. **If you catch yourself adding a paragraph of detail here,
that paragraph is an issue.** File it, link the number, move on. And when the
structure itself stops fitting: rewrite it rather than patching around it.
