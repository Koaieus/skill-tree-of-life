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


## Mint [member board] if not yet ready: a DEEP clone of the authored
## [member board] when one is set, of [param template] otherwise, so this state
## owns its Stat instances outright. Raises [member board_ready]. Returns the
## board; a no-op on an already-minted state. Signal hookups, intrinsics and
## the backing push stay with the caller — a connection is not state, and the
## caller must connect before the push so its handlers see it.
func ensure_board(template: NodeStatBoard) -> NodeStatBoard:
	if board_ready:
		return board
	var source: NodeStatBoard = board if board != null else template
	board = source.duplicate(true)
	board_ready = true
	return board


## A detached copy at COMBAT depth: [member board] via
## [method StatBoard.clone_live], [member tags] duplicated, everything else
## copied by value or (modifiers, effects, local modifiers, owner identity) by
## reference.
func clone() -> NodeState:
	var c := NodeState.new()
	c.owned_by = owned_by
	c.board = board.clone_live() as NodeStatBoard if board != null else null
	c.board_ready = board_ready and c.board != null
	c.tags = tags.duplicate()
	c.modifiers = modifiers
	c.effects = effects
	c.local_modifiers = local_modifiers
	c.stake_level_backing = stake_level_backing
	c.allocation_level_backing = allocation_level_backing
	c.last_allocation_level = last_allocation_level
	c.regen_stacks = regen_stacks
	c.shots_fired_this_turn = shots_fired_this_turn
	c.damaged_since_upkeep = damaged_since_upkeep
	return c
