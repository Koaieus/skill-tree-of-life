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
   acceptable — see `.claude/rules/skill-node-scale.md`.
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
| **#457** | `GameSession` + one-shot seed resolution | `Needs design` — **owner decision**, it is the determinism contract. Scope grew: it must also cover combat/loot RNG, see its comment |
| **#474** | Split world mutation from VFX in `launch_attack` | **do this first** of the sync lane — required under every model, gates #458 |
| **#458** | `Command` + `CommandApplier` (rewritten) | behind #474. The reroute is small — nine verbs, not 850 lines |
| **#475** | Author real faction camps | was prose inside #459/#463; gates versus, and #459 wants the allied-humans half |
| **#459** | Hot-seat coop: the three rebind seams | **`Ready`** |
| **#460** | `VictorySystem` — a run that can end | `Needs design` — what *is* the win condition |
| **#461** | Menu shell follow-up: scenic screens, roster wiring, styling | `Needs design` |
| **#462** | Display settings (window mode, resolution, vsync, fps cap) | **`Ready`** — cheap, North Star #2 |
| **#463** | Versus: `NetworkTransport` + ENet lobby | `Needs design` — **stretch**, and downstream of #473 |

Also in the milestone, by owner call: **#300** removable node blockers, **#403**
Tech Seeds, **#412** armed-mode viewport tint. All three `Needs design` — "should
be easy to get *something* going", so they want a fast swarmify, not a deep one.

**Order:** the sync model is settled; #457 is the one decision left that shapes
everything else, and it is not a drone unit. Then #474 → #458, in that order.
#459, #461 and #462 can proceed in parallel; #475 is worth pulling early since
#459 needs half of it. #460 wants its own design pass. #463 stays gated — it
opens only once #474, #458 and #475 have landed and offline play is verified
unchanged.

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
+ regen (P0, blocks #278), #278 spell balance pass (an owner session), #366/#367
balance harnesses (`Ready`), #248 the hub.

**Onboarding** — #49 tutorial. (#300 and #403 moved into the LAN milestone.)

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

- **#238 is `In progress` with its only sub-issue (#341) closed — not a false
  positive.** #238's body is a **verdict task** on the other five visual encoders
  (RimRing, RimBonuses, RuneRing, CoreHalos/CoreSigilBloom, SensedOutline,
  BaseCircle): each needs an explicit KEEP/MERGE/CUT applied, gated on #132 (rune
  ring vs. rim diamonds) resolving first. Nothing in the codebase shows that
  verdict has been made.
- Don't trust this section's date — run `mise gh-project -- hygiene`.

## When this file is wrong

It will go stale — but it should now go stale *slowly*, because it holds pointers
rather than content. **If you catch yourself adding a paragraph of detail here,
that paragraph is an issue.** File it, link the number, move on. And when the
structure itself stops fitting: rewrite it rather than patching around it.
