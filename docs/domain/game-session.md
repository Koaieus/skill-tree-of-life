# GameSession + the seed determinism contract

`GameSession` (`autoload/game_session.gd`) owns the **live run**: the
`RunConfig` that describes it, the `ParticipantRoster` playing it, and the
`RunOutcome` it ended with. Landed in #457.

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

`end()` clears `config` and `roster` but **not** `outcome`. A run ends and is
routed away from in the same breath (`GameRoot._on_run_ended` records off the
bus, waits out the delay, then ends and routes), so clearing the terminal state
there would delete it at the exact moment a results screen would want to read
it. `start()` is what clears it — the moment a stale outcome could actually
mislead. `is_active()` keys off `config`, so a surviving outcome never makes a
dead run look live.

## The seed is for procgen. Nothing else.

Owner call, 2026-08-21, verbatim: *"we don't care about that seed beyond the
procgen using it, for now. possibly forever."*

**The same seed reproduces the same MAP, not the same FIGHTS.** Two runs on seed
`12345` generate an identical graph and then diverge the first time anything
crits. That is the normal roguelike bargain — seed the world, let combat vary —
and it is an explicit choice, not an oversight.

An earlier pass at #457 assumed the contract had to cover combat and loot too.
Both halves got answered elsewhere first:

- **Combat RNG** — solved by `8dc6f77`. `BattleSystem.launch_attack` stamps a
  per-attack `AttackPlan.resolve_seed`, `MagicAttackPlan` arms its RNG off it,
  and `AttackOutcome` carries the seed back out. Reproducibility comes from the
  **per-attack stamp**, not a run-level stream — strictly better for sync,
  because a global stream couples every peer's result to having consumed prior
  draws *in the same order*, which is the ordering fragility that sank lockstep
  in #473.
- **Loot RNG** — per #473, loot rolls stay **host-only**; only the chosen
  modifier crosses the wire. Seeding it would solve a problem the authority
  model already deletes. `test/unit/attack/test_attack_determinism.gd` pins the
  unseeded shuffle on purpose, with an explicit warning not to "fix" it.

**So: never thread `GameSession.config.seed` into `BattleSystem`,
`SpellResolver`, `LootSystem`, or `SkillDustAddon`.** If exact run replay is
ever wanted, the missing piece is *recording the per-attack stamps* — not
seeding a global stream.

Deriving a **map**-shaping stream from the seed is fine and intended: the
territory seeder in `scenes/procgen_play_sandbox.gd` uses `seed ^ 0x57AB02D`, a
constant salt that keeps enemy seeding independent of the procgen content stream
so adding a modifier roll upstream doesn't shift where enemies start.

## Gotchas when testing this

- **An autoload outlives every test** in GUT's single process. Call
  `GameSession.end()` in `before_each`, or one test's recorded run leaks into
  the next.
- **`GraphProcgen.generate` mutates its config** — `shape_mask.size_for()` sizes
  the mask in place, `_propagate_mask_radius` writes back into radial fields.
  Reusing one config object across two generations makes the second start from
  an already-sized mask, which reads as non-determinism and sends you debugging
  the wrong thing. Build the config fresh (or `duplicate(true)`) per run. See
  `test/unit/test_procgen_determinism.gd`, which is built around this.

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
