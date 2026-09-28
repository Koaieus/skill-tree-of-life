# Architecture review — 2026-09-27

Top-down review of the core structure: are the layers separated, is the
composition clean, does the backlog cover the structural work the roadmap
needs. Four read-only audits (layering, composition, tests/process, backlog)
plus churn measurement; every cited line was re-read before it was asserted.
The issues this review filed are listed at the bottom.

## Verdict

Healthy, and better than a typical solo-grown project. The layers exist and
mostly hold. One seam is genuinely leaky (`SkillNode` is both model and view),
the wiring is clean at the core and frays at the controllers, and the board has
drifted from the roadmap. Velocity is real but partly paid for by accretion
into four files.

| File | Lines | Commits, 3 months to 2026-09-27 |
|---|---|---|
| `skill_node/skill_node.gd` | 2115 | 124 |
| `scenes/game_root.gd` | 1325 | 83 |
| `systems/battle_system.gd` | 1265 | 61 |
| `entity/entity.gd` | 991 | 59 |
| new source files created in the window | | 562 |

The biggest files are also the hottest: the accretion signature. The new-file
count says growth is still mostly additive, so this is a warning, not a crisis.

## Boundaries

Each boundary states the test "separated" would pass, then the verdict.

**Simulation vs presentation** — could a turn run with no viewport, could the
HUD be swapped without touching rules? *Leaky at one place, clean elsewhere.*
The scene node is the model: ownership, allocation level, stake, modifiers,
effects and the node board all live on an `Area2D`
(`skill_node/skill_node.gd:74-426`), and roughly 35-40% of that file is visuals
and input. Around it the discipline holds: no `ui/` or `presentation/` code
writes authoritative state; the reveal clock is honoured (mutation on
`BeatClock`, VFX unawaited, `battle_system.gd:1019-1039`); `Entity` has no
visual references; `CombatWorld` already proves a scene-free model works for
combat. Smells: a content node looks up `BattleSystem` through a group
(`skill_node.gd:728-744`); a stat is written into a physics collision layer and
read back by the rules via `intersect_shape` (`skill_node.gd:1557-1564`,
`attack/melee/sim/blade_hit_scan.gd:177`). Headless works in a headless Godot,
not off-tree: melee needs a physics broadphase and group lookups need a
`SceneTree`.

**Simulation vs network** — one choke point for every authoritative mutation,
no system knows the transport? *Clean with one deliberate escape hatch.* Local
and mirror commands both enter `CommandApplier._drain`
(`command/command_applier.gd:304-316, 480-520`); the applier knows only
`is_authority`. The hatch is `launch_attack` with no applier
(`battle_system.gd:487-497`), kept so the loot suite runs without one. Leaks:
`LootSystem` exports a `CommandLink` (`systems/loot_system.gd:79`);
`CommandLink` is five protocols in one file (commands, lobby, seat handover,
loot offers, resync); the spine has two cycles — command → network via
`WorldFingerprint` (`command_applier.gd:489`), session → network via
`NetworkTransport.Role` (`session/network_config.gd:42`).

**Composition** — deps arrive through the scene, the root wires then steps
aside? *Systems pass, controllers fail, GameRoot carries cargo.* Every system
takes deps by `@export`. `AIController` walks up to `GameRoot`
(`entity/controller/ai_controller.gd:826-856`); `Entity` and the input
controller find systems by group lookup (`entity.gd:974`,
`player_input_controller.gd:1199`). `GameRoot` holds ~130 lines of multiplayer
test harness (`game_root.gd:416-545`), a blocker factory (1091), seat handover
(621-690), balance math (1142) and an initiative-stagger rule (307-366).
`BattleSystem` mixes plan-building, resolve, replay and presentation
(876-1065), and the AI drives the human's single plan slot
(`ai_controller.gd:690-724`). `HudRoot` is clean.

**Tests and process** — *an asset.* 531 unit / 43 integration / 15 perf
scripts; unit tests are formula-shaped; 17 unscoped rules total ~700 words;
debt markers are very low. Soft spots: ~20% of unit tests poke internals as an
arrange step; `owned_by` appears in 106 test files, so a rename there is a
scripted migration.

**Backlog** — *coherent for in-flight polish, drifting from the roadmap.* 230
open, `Ready` empty, 141 unmilestoned. None of the structural items below had
an issue framed as such before this review.

## Forward fit

- **Save/load and metagame** have a natural seed in the join-time snapshots
  (`network/graph_snapshot.gd`, `entity_snapshot.gd`, `world_fingerprint.gd`).
  Not a finished save format: initiative, pending loot offers, status effects
  and RNG state are unverified. #23.
- **Fractal / nested graphs** are feasible: no static single graph; every system
  takes its graph by export.
- **Deeper AI** is blocked: shadow worlds cover only combat; allocation or stake
  lookahead would touch `Area2D`s. *Filed 2026-09-28 as hub #1192:* the AI
  leaves whole toolsets unused (it never spends DP, #1193) and plans no turn
  across budgets; whether #1130's `NodeState` clone lifts the `Area2D` block
  is that hub's first open question.

Found along the way, both verified:

- Seat handover writes `Participant.Kind.AI` into the run roster
  (`game_root.gd:675`) and the roster survives the pause-menu restart.
  *Corrected 2026-09-27 during swarmify:* handover fires only on peer-left or
  under the autoplay harness, so a departed peer staying AI is correct. The
  real findings are that the pause-menu restart has no networked-run guard
  and that `GameSession.start` adds `RunConfig`'s own `Participant` objects
  to the roster (aliasing). Retitled #1135.
- The melee same-frame broadphase window is guarded only in debug builds
  (`blade_defender_zones.gd:196-206`) and the command drain never yields a
  physics frame, so one drain that attaches an addon and then attacks can
  resolve wrong in release.

## Ranked, by cost if ignored over the next two milestones

1. Finish the `SkillNode` model split — extract a RefCounted state object the
   node holds, keep existing fields as forwarding properties so callers and the
   106 test files do not move. Additive; the `CombatWorld` pattern exists. #426
   covers three mutators only.
2. Inject controller dependencies; `GameRoot` sheds harness, factory, handover.
3. Split `BattleSystem` into plan slot / resolve + replay / presentation; give
   the AI its own plan instance.
4. Decompose `CommandLink`; `LootSystem` off the link; `WorldFingerprint` and
   `Role` moved down so the spine is a DAG. Fix the release melee window.
5. Enforce dependency direction: a one-page layer map plus a mise check.

Already on the board: #721, #442 code-composed UI; #722 coordinator; #428 blade
construction; #434 Board↔Stat cycle; #53 perf budget; #433 no CI gate.

**Not worth fixing:** `Emissive` imports from `graph/` and `attack/`, the
fixed-timer beats, the vision draw lerp, the AI's `GameRoot` fallback on its
own, the test pokes as a campaign.

**Better than typical:** ADR 0026 enforced by an assert; `SeatPolicy` split
from the roster with its invariant written down; `HudRoot`'s per-level vs
per-handover binding; the single mutation path; the reveal-ready contract;
nearly every wiring decision carrying a *why*.

## Opportunities

**Cleanliness**
- Dead and duplicate bus signals: `camera_zoom_changed` (no listener, stale
  doc), `ai_decision` (test-only), `turn_started` emitted on both `TurnManager`
  and the bus with split consumers.
- Order-dependent `entity_dying` listeners (`LootSystem`, `BattleSystem`).
- The input controller's denial-reason ladder hand-mirrors the extract gate
  order (`player_input_controller.gd:457-510`).
- Code-composed ghost labels in the input controller (1211-1236); #721, #442
  cover the lobby screen and allocation VFX.
- Point-to-point signals on the global bus (spell hover, wounded/healed, blade
  vertex popped, volley arrows).
- `skill_dust_addon.gd` runs a multi-round human-in-the-loop flow and submits
  commands (`:228-233, :285-350, :481`) — controller work in a node addon.
- Edge rendering in `graph/`, colour tiers in `ui/`: a `presentation/` home.

**Performance**
- Every `SkillNode` connects to the bus's `turn_started`
  (`skill_node.gd:1415`): one tick runs 800 handlers. #1110.
- Per-frame processing is gated (node visuals, vision lerp); no non-procgen
  source iterates the whole graph per frame. Good.
- Melee resolve coupled to the physics tick; a geometry-only zone query (the
  debug cross-check already walks it) removes the physics server from rules.
  *Corrected 2026-09-28:* already decided against. Owner stance 2026-09-09
  (#817): keep hit-scanning on the engine; the `Geometry2D` port is a parked
  escape hatch, triggered only if AI rollouts must leave the main thread. The
  real hazard, the release same-frame window, is closed by #1136.
- AI rollouts pay for the scene tree until the model split lands.
- Known quadratic walks: #440, #471, #1109 — filed, unmilestoned.
- Sixteen benches, no budget: nothing fails on regression. #53.

**Developer experience**
- No CI or pre-push gate (#433): `check` + the unit shard on push is the
  cheapest single win.
- ~45 unit scripts wait on real time and account for most flakes: #992, #1070,
  #1066, #986, #985.
- `*_override` exports on `AIController` exist only because it walks the tree.
- The no-applier attack hatch lets tests skip the command path; a fixture
  applier would let it close.
- Dependency direction is unchecked; the grep is a twenty-line mise task away
  from a gate.
- Tooling is strong (worktrees, sandbox host, `refresh`, 20 s `check`, sharded
  suite, board pipeline) and worth protecting from the same accretion.

## Issues filed by this review

| # | Lane | Title |
|---|---|---|
| #1130 | Needs design | SkillNode model/view split (ranked 1) |
| #1131 | Needs design | Controllers get injected deps; GameRoot sheds cargo (ranked 2) |
| #1132 | Needs design | Split BattleSystem; AI gets its own plan (ranked 3) |
| #1133 | Needs design | Spine as a DAG; decompose CommandLink; LootSystem off the link (ranked 4), blocked by #1138 |
| #1134 | Needs design | Enforce dependency direction: layer map + `deps-check` (ranked 5) |
| #1135 | Ready | Pause-menu restart unguarded online; roster aliases RunConfig participants |
| #1136 | Backlog | Bug: melee same-frame broadphase window unguarded in release |
| #1137 | Backlog | Events bus hygiene |
| #1138 | Needs design | skill_dust_addon runs a controller flow |
| #1139 | Backlog | PlayerInputController denial ladder + code-composed ghost labels |
