# GameSession + the seed determinism contract

`RunConfig` that describes it, the `ParticipantRoster` playing it, and the
`RunOutcome` it ended with. Per-machine fields sit beside them: `network`
(`NetworkConfig`, how this machine reaches the other one), `local_peer_id` (which
roster peer is this machine), `world_source` and `pending_world`. Signals:
`run_started(config)` once the config is settled and the seed resolved, and
`run_recorded(outcome)` once the terminal state is stored.

It has no `class_name` on purpose — a `class_name GameSession` alongside an
autoload of the same name is a hard parse error ("class hides an autoload
singleton"). The repo already dodges this the same way elsewhere: the `Settings`
autoload, the `GameSettings` class.

## One resolution site, and only one

`seed == 0` is the authoring sentinel for "randomise me". `RunConfig.resolve_seed(value)`
is the **only** place it resolves: `0` draws a concrete number, anything else
passes straight through. That pass-through makes it **idempotent**, which is
what makes "re-reading the seed does not re-randomise it" true by construction
rather than merely true in the test that checks it.

It's a `static func` on `RunConfig` rather than a method on the autoload for one
concrete reason: `@tool` editor code has to reach it — the procgen playground
(`procgen/playground/playground_panel.gd`) draws preview seeds — and **project
autoloads are not in the editor's tree**. A resolver on the singleton would have
forced the playground to keep its own `randi()`, which is exactly the second
resolution site #457 existed to delete.

### Who calls it

| Entry point | What it does |
|---|---|
| `GameSession.start(cfg)` | Opens a run. Resolves the seed once, here, before any level builds. The lobby's START calls it, then routes. |
| `GameSession.ensure_started(fallback_seed)` | What a directly-launched level calls from `_setup_level` (dev sandbox, `godot --path .`, a headless test). Opens a run seeded from the scene's authored preset seed — and **leaves a live run alone**. |
| `GameSession.end()` | Drops the run so the next `ensure_started` resolves fresh. Called when routing away from a finished run. |
| `GameSession.apply_received(cfg, roster)` | A joiner's entry: takes the host's already-resolved config and roster (never re-resolves the seed), sets `world_source = ARRIVES`. |
| `GameSession.open_saved(save)` | Opens a run from a `SaveFile`: same shape as `apply_received`, the saved world parked in `pending_world` for the level. False, session untouched, for a save that did not load. |

`GraphProcgen.generate` **asserts** its config's seed is already resolved. It is
deliberately not a resolution site: a seed nobody recorded is a run nobody can
replay, which was the original bug — seed 0 *did* randomise, but the `randi()`
it drew was thrown away. (The assert is debug-only, so there's a
`RunConfig.resolve_seed` call behind it as the release-build floor; it's a no-op
on any already-resolved seed.)

### Restart replays the same map

`ensure_started` leaving a live run alone has one visible consequence: the pause
menu's restart is `reload_current_scene()`, which does not end the session, so
the reloaded level finds the same resolved seed and regenerates **the same map**.
Retry-this-map is the intended semantic. A *different* map is menu → new game,
which calls `start()` afresh. Pinned by
`test_a_scene_reload_replays_the_same_map`.

### The outcome outlives `end()`

`end()` clears `config`, `roster`, `network` and `pending_world`, resets
`world_source` to `GENERATE`, and calls `Wire.stop()` (the socket outlives the
level, so a listener left behind would hold the port the next Host click needs) —
but **not** `outcome`. Recording is `GameSession._on_run_ended` (off
`Events.run_ended`, emitting `run_recorded`); `GameRoot` then waits out the delay
and routes via `route_to_meta_now`, which calls `GameSession.end()`. Clearing the
terminal state there would delete it at the moment a results screen would want to
read it. `start()` is what clears it. `is_active()` keys off `config`, so a
surviving outcome never makes a dead run look live.

## The seed is for procgen. Nothing else.

Owner call, 2026-08-21, verbatim: *"we don't care about that seed beyond the
procgen using it, for now. possibly forever."*

**The same seed reproduces the same MAP, not the same FIGHTS.** Two runs on seed
`12345` generate an identical graph and then diverge the first time anything
crits. That is the normal roguelike bargain — seed the world, let combat vary —
and it is an explicit choice, not an oversight.

The seed is a replay input, never a cross-peer determinism contract: a joining
client runs no procgen — it receives the host's serialized world.

Reproducibility of fights comes from elsewhere:

- **Combat RNG** — `BattleSystem.launch_attack` stamps a per-attack
  `AttackPlan.resolve_seed`, `MagicAttackPlan` arms its RNG off it, and
  `AttackOutcome` carries the seed back out. Reproducibility comes from the
  **per-attack stamp**, not a run-level stream — a global stream would couple every
  peer's result to having consumed prior draws *in the same order*, the ordering
  fragility that sank lockstep.
- **Loot RNG** — loot rolls stay **host-only**; only the chosen modifier crosses
  the wire, so seeding it would solve a problem the authority model already
  deletes. `test/unit/attack/test_attack_determinism.gd` pins the unseeded shuffle
  on purpose, with an explicit warning not to "fix" it.

**So: never thread `GameSession.config.seed` into `BattleSystem`,
`SpellResolver`, `LootSystem`, or `SkillDustAddon`.** If exact run replay is
ever wanted, the missing piece is *recording the per-attack stamps* — not
seeding a global stream.

Deriving a **map**-shaping stream from the seed is fine and intended: the
territory seeder in `scenes/procgen_play_sandbox.gd` uses `seed ^ 0x57AB02D`, a
constant salt that keeps enemy seeding independent of the procgen content stream
so adding a modifier roll upstream doesn't shift where enemies start.

## World source: generate it, or await it

`GameSession.world_source` (`WorldSource.GENERATE` / `ARRIVES`) answers one
per-machine question: does this machine build the world from the seed, or is
the world delivered to it? A level's `_setup_level` branches on it — **never on
`network_session.is_client()`**, which keeps its other callers (wire roles, the
restart gate). Owner call on #23 (2026-10-02): the run carries it.

| Writer | Sets |
|---|---|
| `start()` (lobby START, `ensure_started`) | `GENERATE` |
| `apply_received()` (the joiner's entry) | `ARRIVES` |
| `end()` | back to the default, `GENERATE` |
| `scenes/dev/mp_procgen_sandbox.gd` (`--role=client`, its own lobby) | `ARRIVES`, before its run arrives |

It lives on the autoload, not on `RunConfig`: the config is the run's shape,
crosses the wire and is identical on every peer, while this fact differs per
machine (the host generates, a joiner awaits). The `ARRIVES` branch seats the
roster, generates nothing and holds the curtain; **who delivers the world is
not its concern** — the wire today, a save file as well. Pinned by
`test/integration/session/test_world_source_arrives.gd` (no network at all).

## Gotchas when testing this

- **An autoload outlives every test** in GUT's single process. Call
  `GameSession.end()` in `before_each`, or one test's recorded run leaks into
  the next.
- **`GraphProcgen.generate` never writes to its config** — it resolves the
  auto-scaled mask and back-filled fields on a copy, returned as
  `result.config`. Read resolved values there, never off the argument. See
  `test/unit/test_procgen_config_purity.gd`.

## Where the pieces live

- `autoload/game_session.gd` — the singleton
- `session/run_config.gd` — `RunConfig`, and `resolve_seed`
- `session/participant_roster.gd`, `session/run_outcome.gd`
- `procgen/graph_procgen.gd` — the assert
- `ui/frontmatter/panels/lobby_screen.gd` — the seed field in
- `ui/pause_menu.gd` — the seed field out (click the footer to copy it)
- `test/unit/session/test_game_session.gd`, `test/unit/test_procgen_determinism.gd`

Related: [seat-policy.md](seat-policy.md) (the per-machine half of a run's
setup), [multiplayer-sync-model.md](multiplayer-sync-model.md) (why host-only
rolls are exempt), [victory-system.md](victory-system.md) (who decides a run
ended).
