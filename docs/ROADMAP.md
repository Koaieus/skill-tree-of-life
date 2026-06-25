# Roadmap

Living overview of what's done and what's left. Each theme below is a [GitHub milestone](https://github.com/Koaieus/skill-tree-of-life/milestones); each bullet links to the tracking issue.

Status legend: ✅ done · 🚧 in progress · ⬜ todo

> 📍 **Authoritative current state on contested design questions: [docs/design/mvp_decisions.md](design/mvp_decisions.md).** Older per-system design docs may contain superseded sketches; mvp_decisions.md wins.

## MVP cutline

A "first full playthrough" lands when these four milestones are complete:

1. [MVP playable loop](https://github.com/Koaieus/skill-tree-of-life/milestone/1)
2. [Battle UX rework](https://github.com/Koaieus/skill-tree-of-life/milestone/2)
3. [Stats / UI panel rework](https://github.com/Koaieus/skill-tree-of-life/milestone/3)
4. [MVP content slice](https://github.com/Koaieus/skill-tree-of-life/milestone/4)

Everything below the MVP cutline section is post-MVP.

## Done — the foundation

- Graph + entity + allocation system (`graph/`, `entity/`, `systems/allocation_system.gd`)
- Turn manager, phases, initiative (`systems/turn_manager.gd`)
- Stat board with PoE-style modifier pipeline; local stats, pool stats, growable pools (`stats_system/`)
- Combat: melee blade-sim, ranged volley, magic spell propagation (`attack/`, `ui/vfx/coordinator/`)
- Vision / fog of war (`systems/vision_system.gd`)
- Procgen v3 (StatPack, phased draw) (`procgen/`)
- Core classes (`BalancedCore` baseline) (`entity/core/`)
- Add-on framework (2 implemented; more planned)
- Allocation/dealloc cascade + forced-dealloc on node death
- Battle system + attack plans (`systems/battle_system.gd`)
- Debug tooling: StatBoard visualizer plugin, F3 overlay, hover-clipboard
- Spell-gating uses allocated-degree (D-4 ✅)

## MVP cutline milestones

### MVP playable loop

- ⬜ [#18](https://github.com/Koaieus/skill-tree-of-life/issues/18) Entity death + cleanup on core HP=0
- ⬜ [#19](https://github.com/Koaieus/skill-tree-of-life/issues/19) Core takes wound damage on forced-dealloc
- ⬜ [#20](https://github.com/Koaieus/skill-tree-of-life/issues/20) Core wound + heal animation + floating number
- ⬜ [#21](https://github.com/Koaieus/skill-tree-of-life/issues/21) Core movement — N hops/turn, click-to-move
- ⬜ [#22](https://github.com/Koaieus/skill-tree-of-life/issues/22) AI v1 — minimum-viable enemy turn
- ⬜ [#23](https://github.com/Koaieus/skill-tree-of-life/issues/23) Save/load baseline
- ⬜ [#24](https://github.com/Koaieus/skill-tree-of-life/issues/24) Add Entity.faction field (D-7 future-proofing)
- ⬜ [#25](https://github.com/Koaieus/skill-tree-of-life/issues/25) Melee: edges inert, blade-nodes deal damage, STR//10 scaling (D-1)
- ⬜ [#26](https://github.com/Koaieus/skill-tree-of-life/issues/26) Melee: swing direction CW/CCW toggle

### Battle UX rework

- ⬜ [#27](https://github.com/Koaieus/skill-tree-of-life/issues/27) Contextual action bar (D-6) — click node → fan actions
- ⬜ [#28](https://github.com/Koaieus/skill-tree-of-life/issues/28) Launch-attack FAB over central viewport
- ⬜ [#29](https://github.com/Koaieus/skill-tree-of-life/issues/29) Dim battle UI when AP = 0
- ⬜ [#30](https://github.com/Koaieus/skill-tree-of-life/issues/30) Spell bar v2 — availability sort + dim-with-reason
- ⬜ [#31](https://github.com/Koaieus/skill-tree-of-life/issues/31) Spell tooltip as scene (dynamic value highlighting)

### Stats / UI panel rework

- ⬜ [#32](https://github.com/Koaieus/skill-tree-of-life/issues/32) Tabbed stats panel
- ⬜ [#33](https://github.com/Koaieus/skill-tree-of-life/issues/33) End-turn button: show phase + protect against unspent points
- ⬜ [#34](https://github.com/Koaieus/skill-tree-of-life/issues/34) Announcer drop-stale + dedup (D-8)

### MVP content slice

- ⬜ [#35](https://github.com/Koaieus/skill-tree-of-life/issues/35) Tune addon procgen ratios/spread
- ⬜ [#36](https://github.com/Koaieus/skill-tree-of-life/issues/36) Add 2-3 new spells to round out MVP spellbook
- ⬜ [#37](https://github.com/Koaieus/skill-tree-of-life/issues/37) Add spell_range stat + INT intrinsic + RangeFinder consumption (D-2)

## Post-MVP milestones

### Content depth

- ⬜ [#38](https://github.com/Koaieus/skill-tree-of-life/issues/38) Damage type taxonomy implementation (D-5 deferred)
- ⬜ [#39](https://github.com/Koaieus/skill-tree-of-life/issues/39) More core classes + range-based friendly buffs
- ⬜ [#40](https://github.com/Koaieus/skill-tree-of-life/issues/40) Core-class texture contract

### Procgen content polish

- ⬜ [#15](https://github.com/Koaieus/skill-tree-of-life/issues/15) NPC starter placement with viability-radius spacing
- ⬜ [#41](https://github.com/Koaieus/skill-tree-of-life/issues/41) Movement modifier in procgen pool
- ⬜ [#42](https://github.com/Koaieus/skill-tree-of-life/issues/42) Self-loop draw mechanic upgrade + rare double-self-loop

### VFX & juice

- ⬜ [#43](https://github.com/Koaieus/skill-tree-of-life/issues/43) Spell icon textures
- ⬜ [#44](https://github.com/Koaieus/skill-tree-of-life/issues/44) Floating numbers v2 (scene + variants)

### Spell designer playground

- ⬜ [#45](https://github.com/Koaieus/skill-tree-of-life/issues/45) Full-screen spell playground editor plugin
- ⬜ [#46](https://github.com/Koaieus/skill-tree-of-life/issues/46) Tighten SpellDef ↔ VFX coupling

### AI v2

- ⬜ [#47](https://github.com/Koaieus/skill-tree-of-life/issues/47) Strategy-pattern NPC controller

### Audio

- ⬜ [#48](https://github.com/Koaieus/skill-tree-of-life/issues/48) SFX pass: impact, UI, ambient

### Onboarding & accessibility

- ⬜ [#49](https://github.com/Koaieus/skill-tree-of-life/issues/49) Tutorial / first-session guidance
- ⬜ [#50](https://github.com/Koaieus/skill-tree-of-life/issues/50) Colorblind palette options

### Metagame

- ⬜ [#51](https://github.com/Koaieus/skill-tree-of-life/issues/51) Main menu + intro + overworld (tracking)

### Multiplayer

- ⬜ [#52](https://github.com/Koaieus/skill-tree-of-life/issues/52) Local coop + LAN/online (tracking)

### Cross-cutting / infra

- ⬜ [#4](https://github.com/Koaieus/skill-tree-of-life/issues/4) Effect system
- ⬜ [#5](https://github.com/Koaieus/skill-tree-of-life/issues/5) Active player + global turn UI
- ⬜ [#9](https://github.com/Koaieus/skill-tree-of-life/issues/9) Stat bind system
- ⬜ [#16](https://github.com/Koaieus/skill-tree-of-life/issues/16) Move XP replenish from turn-start to expand-phase-start
- ⬜ [#53](https://github.com/Koaieus/skill-tree-of-life/issues/53) Performance budget + procgen scaling profile
- ⬜ [#54](https://github.com/Koaieus/skill-tree-of-life/issues/54) Design: "overqualified casting" bonuses (non-range)
- ⬜ [#55](https://github.com/Koaieus/skill-tree-of-life/issues/55) Design: face/cycle melee damage bonus (post-MVP)
- ⬜ [#56](https://github.com/Koaieus/skill-tree-of-life/issues/56) Design: melee swing drive easing variations
- ⬜ [#57](https://github.com/Koaieus/skill-tree-of-life/issues/57) Design: node specialization system

## How to use this roadmap

- **Filter by milestone:** `gh issue list --milestone "MVP playable loop"`
- **Filter by label:** `gh issue list --label ui` (or `core`, `vfx`, `ai`, `procgen`, `balance`, `audio`, `meta`, `multiplayer`, `tech-debt`, `blocked`, `design`)
- **Find blocked work:** `gh issue list --label blocked`
- When closing an issue, flip its bullet here to ✅. When in progress, 🚧.
