# System map

One line per system: what it owns, where it lives, which doc holds the rest.
The layer/dependency rules are in `docs/architecture.md`.

`GameRoot` (`scenes/game_root.gd`) — per-level composition root; mounts VFX, wires systems, calls `_setup_level()`, then `HudRoot.compose(self)`. Subclass + override `_setup_level()` to author or generate level content.
`HudRoot` (`ui/hud/hud_root.gd`) — the "Arcane Terminal" HUD, sole UI layer; clusters `bind()` their own deps, cross-system deps arrive through one `compose(game_root)` split by lifetime (`bind_systems()` per level, `rebind_player()` per hot-seat handover).
`Graph` (`graph/graph.gd`) — owns `SkillNode`s + `Edge`s + `entities_container`; pure topology, structural signals.
`Entity` (`entity/entity.gd`) — players and NPCs share the class; ownership is set by `AllocationSystem`. Composes a `CoreClass` (`entity/core/`) — identity modifiers + an `on_turn_started` hook.
`SeatPolicy` (`session/seat_policy.gd`) — the per-machine half of a run's setup (who this machine plays, whose eyes it draws with); run shape is the roster's half. See `docs/domain/seat-policy.md`.
`Navigator` (`graph/navigator.gd`) — full-graph `AStar2D` mirror; `EntityNavigator` is the per-entity mirror for cut-vertex / islanding queries.
`TurnManager` (`systems/turn_manager.gd`) — initiative ticks to 100 → entity acts; `end_turn()` deducts 100. See `.claude/rules/turn-manager.md`.
`AllocationSystem` (`systems/allocation_system.gd`) — `allocate` / `deallocate` (gated) + `force_allocate` / `force_deallocate` (primitives). See `docs/domain/allocation_system.md`.
`BattleSystem` (`systems/battle_system.gd`) — owns the active `AttackPlan`; `launch_attack` submits a command to `CommandApplier`, which replays the resolved `AttackRecord` on the reveal clock. See `docs/domain/attack_plan_system.md`.
`VisionSystem` (`systems/vision_system.gd`) — fog of war; reads owned subgraph + per-entity `vision_range` / `sensor_range`. See `docs/domain/vision-system.md`.
`LootSystem` (`systems/loot_system.gd`) — killing-blow XP, tempo, and a relic on the victim's former core; snapshots on `Events.entity_dying`, before the corpse is stripped. See `docs/domain/loot-system.md`.
`StatBoard` (`stats_system/`) — PoE-style modifier pipeline. See `.claude/rules/stats-system.md` — **update it when the stat system changes.**
`VictorySystem` (`systems/victory_system.gd`) — sole emitter of `Events.run_ended(RunOutcome)`; owns the *when* and the *once*, the swappable `VictoryCondition` owns the *what*. See `docs/domain/victory-system.md`.
`GraphProcgen` (`procgen/graph_procgen.gd`) — static pipeline; `generate(config, graph)` returns nodes + starting_nodes. See `docs/domain/procgen.md` (topology), `docs/domain/procgen-v4.md` (content).

Spawning runtime entities: in `_setup_level()`, call `spawn_entity(name, color, core_location, core_class)`. See `scenes/procgen_play_sandbox.gd`.

