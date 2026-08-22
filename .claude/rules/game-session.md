---
description: GameSession + the seed determinism contract — one-shot resolution, and what the seed is deliberately NOT for
paths:
  - "session/**"
  - "autoload/game_session.gd"
  - "procgen/graph_procgen.gd"
  - "scenes/meta/**"
---

# GameSession + the seed contract (#457)

`GameSession` (autoload, `autoload/game_session.gd`, deliberately no
`class_name` — that would collide with the singleton) owns the live run: the
`RunConfig`, the `ParticipantRoster`, the `RunOutcome`.

## One resolution site

`RunConfig.resolve_seed(value)` is the **only** place a seed sentinel resolves
(`0` → a concrete draw; anything else passes through, so it is idempotent).
It's a static on `RunConfig` rather than a method on the autoload because
`@tool` editor code — the procgen playground — must reach it, and project
autoloads are not in the editor's tree.

`GameSession.start(cfg)` calls it once, up front, before any level builds.
`GameSession.ensure_started(fallback_seed)` is what a directly-launched level
(dev sandbox, headless test) calls from `_setup_level` — it opens a run seeded
from the scene's authored preset seed, and **leaves a live run alone**. One
visible consequence: the pause menu's restart (`reload_current_scene`) replays
the *same* map. Retry-this-map is the intended semantic; a different map is
menu → new game, which calls `start` afresh.

`GraphProcgen.generate` **asserts** its config's seed is already resolved. It
is not a resolution site: a seed nobody recorded is a run nobody can replay.

## The seed is for procgen. Nothing else.

Owner call, 2026-08-21, verbatim: *"we don't care about that seed beyond the
procgen using it, for now. possibly forever."*

**The same seed reproduces the same MAP, not the same FIGHTS** — an explicit
choice, not an oversight. Combat reproducibility comes from the per-attack
`AttackPlan.resolve_seed` stamped by `BattleSystem` (`8dc6f77`), and loot rolls
stay host-only per #473 (`test/unit/attack/test_attack_determinism.gd` pins
that on purpose, with a warning not to "fix" it).

**How to apply:** never thread `GameSession.config.seed` into `BattleSystem`,
`SpellResolver`, `LootSystem`, or `SkillDustAddon` — a global stream couples
every peer's result to having consumed prior draws in the same order, which is
the ordering fragility that sank lockstep in #473. Deriving a *map*-shaping
stream from it (the territory seeder's `seed ^ 0x57AB02D` salt in
`procgen_play_sandbox.gd`) is fine and intended.
