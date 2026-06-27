# Core movement — implementation plan (#21)

Related: **#58** (extend the movement model), **#39** (core-class buffs).

> **Note (post-#60):** turn phases are gone — there's one phase per turn now. The "phase gating" below is obsolete; core-move is gated by "your turn" + MP, and clicks route battle-plan → core-move → allocate (see `PlayerInputController._on_skill_node_left_clicked`).

## Interaction
- **Click-source-then-target** canonical; **drag** is an accelerator layered on the same state machine. Both map onto future gamepad input (directional graph → D-pad/stick + A).
- No dedicated "move mode" button. Clicking your own core is unambiguous: when an attack plan is active it claims clicks first, otherwise the click enters core-move targeting.
- Drag: real core sprite stays put on source. A **ghost core** snaps to the nearest eligible owned landing under the cursor (filtered by remaining MP). Release on valid landing → commit; otherwise snap back.
- **Hop-count badge** floats near cursor / ghost: `2 hops · 1 MP left`.
- **Path preview**: dim highlight along the BFS shortest path source → landing over owned edges. New highlight roles `CORE_PATH` / `CORE_LANDING` in `AttackHighlightOverlay`.
- **Self-loops are not eligible landings.** Topologically a move, mechanically a no-op — exclude from adjacency set.

## Turn gating
- Gated by "your turn" + `movement_points` ≥ 1. No phase restriction (phases removed in #60). Extensions → **#58**.

## Stats [DONE]
- Default `movement_points` to **1** on `default_entity_board.tres` (verify current default).
- Level-start budget target: 1 dealloc + 1 movement.
- Procgen `+1 movement` rolls → later carving pass.

## Wiring [DONE]
- Public API: `move_core(entity, target_node)` — validates adjacency-along-owned-edges (no self-loops), validates MP, spends `movement_points`, sets `entity.core_location`, plays slide tween. Likely lives in `AllocationSystem` to start (split to `MovementSystem` if it grows).
- `Entity.core_location` setter already emits `core_location_changed` → SkillNode core marker refresh is free.
- `PlayerInputController` gets a "core-move targeting" branch parallel to attack targeting; dispatches when source is the player's own core node and it's the player's turn (no phase check).
- **No cut-vertex checks** — moving the core within an unchanged owned subgraph never disconnects anything.

## Contextual RHS panel — own core selected [DONE]
- Reborn (phase-free) as the **ContextPanel** (`ui/context_panel/`): a priority
  resolver swaps a pre-authored body per context — attack plan > core-move >
  pinned node > idle. Each body is an inherited scene from `ContextBodyBase`
  (the salvaged inherited-scene ergonomics), editor-previewable.
- The **CoreMoveBody** covers this item: core name, `movement_points` segmented
  bar, hint. Active buffs render here once **#39** lands (entity + node bins).
- Pin a node for inspection via right-click (when no attack plan claims it).

## Highlighting during drag/move [DONE]
- Generalized into a single highlight subsystem (one active **HighlightProvider**
  at a time via `HighlightController`; attack plans + core-move are providers).
- `REACHABLE` role rings every owned node within the MP budget (BFS ≤ N hops);
  `PATH` role paints the induced edges of the reachable set; the active drag/click
  landing brightens (`HOSTILE_TARGET`). Fixes "no visuals on first click".
- Drag the core: ghost core snaps to the nearest reachable landing, a hop badge
  (`N hops · M MP left`) floats by the cursor, release commits a multi-hop move
  (chained `move_core` along `AllocationSystem.core_path`).
- See **#65** (persistent entity-tint/neon lit-edge viz — separate from this
  transient highlight system) and the reserved `PROPAGATION` role for the magic
  spell-propagation preview.

## Out of scope
- Extended movement model → #58.
- Procgen `+1 movement` rolls → carve separately.
- Core-class buff design → #39.

## Implementation order (rough)
1. `move_core` API + tests (adjacency, MP spend, self-loop exclusion, no cut-vertex panic).
2. `default_entity_board.tres` movement_points default bump.
3. Click-source-then-target wiring in `PlayerInputController`.
4. Slide tween + `CoreMarker` follow.
5. Highlight roles (`CORE_PATH`, `CORE_LANDING`) in `AttackHighlightOverlay`.
6. Drag UX + ghost + hop-count badge.
7. Contextual RHS panel for own core.
