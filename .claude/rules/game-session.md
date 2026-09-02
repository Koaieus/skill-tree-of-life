---
description: GameSession + the seed determinism contract — one-shot resolution, and what the seed is deliberately NOT for
paths:
  - "session/**"
  - "autoload/game_session.gd"
  - "procgen/graph_procgen.gd"
  - "scenes/meta/**"
---

`RunConfig.resolve_seed` is the ONE place a `seed == 0` sentinel resolves — `GameSession.start`/`ensure_started` calls it once up front and `GraphProcgen.generate` asserts it already happened, because a seed nobody recorded is a run nobody can replay. The seed is for procgen and nothing else, and since #715 for procgen on ONE machine — it is a replay input, never a cross-peer determinism contract (a joining client runs no procgen at all and receives the host's serialized world). The same seed reproduces the same MAP, not the same FIGHTS (combat rides the per-attack `AttackPlan.resolve_seed`, loot rolls are host-only per #473), so never thread it into `BattleSystem` / `SpellResolver` / `LootSystem` / `SkillDustAddon`. See docs/domain/game-session.md
