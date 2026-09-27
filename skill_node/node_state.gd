class_name NodeState
extends RefCounted

## The authoritative, SILENT state of one [SkillNode] — storage only, no
## signals, no scene. A [SkillNode] composes one and forwards its exported
## fields into it (the node's setters emit; a write here never does), and a
## [NodeCombat] holds one: the node's own when live, a [method clone] when
## shadow. Statuses are NOT here — [StatusHost] stays on the slice whose def
## hooks it addresses. See #1130 and docs/domain/attack-timeline.md
## ("The design: split state from notification").

## null → unallocated; !null → allocated. IDENTITY of the owner, so a shadow's
## clone points at the real [Entity] and resolves its slice through its world.
var owned_by: Entity = null
## The node's [NodeStatBoard], null until [method ensure_board] minted it.
var board: NodeStatBoard = null
## "Minted" as distinct from "authored" — see [member SkillNode.node_board].
var board_ready: bool = false
## Refcounted status markers — see docs/design/status-tags.md.
var tags: Dictionary[StringName, int] = {}
## Entity-scoped offerings this node grants its owner.
var modifiers: Array[StatModifier] = []
## [Effect]s this node grants its owner.
var effects: Array[Effect] = []
## Node-local modifier ledger (addons, direct grants, effect node-grants).
var local_modifiers: Array[StatModifier] = []
## Authored backings that hold the value until the board materialises.
var stake_level_backing: int = 1
var allocation_level_backing: int = 0
var last_allocation_level: int = 0
## Per-node combat bookkeeping — runtime state, never a stat (docs/domain/node-hp.md).
var regen_stacks: int = 0
var shots_fired_this_turn: int = 0
var damaged_since_upkeep: bool = false


## Mint [member board] from [param template] (deep clone) if not yet ready.
## Signal hookups stay with the caller — a connection is not state.
func ensure_board(template: NodeStatBoard) -> NodeStatBoard:
	push_error("NodeState.ensure_board: stub (#1130)")
	return board


## A detached copy at COMBAT depth: [member board] via
## [method StatBoard.clone_live], [member tags] duplicated, everything else
## copied by value or (modifiers, effects, owner identity) by reference.
func clone() -> NodeState:
	push_error("NodeState.clone: stub (#1130)")
	return null
