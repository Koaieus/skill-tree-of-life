extends GutTest

## NodeState (#1130 child 0) — the silent storage bag a SkillNode composes.
## Pending until the drone lands the extraction; flips RED on its first commit.

const _PENDING := "#1130: NodeState extraction not landed yet"


func test_clone_is_detached_at_combat_depth() -> void:
	pending(_PENDING)
	# A clone's board is a clone_live copy: writing HP on it leaves the
	# original untouched; tags are a separate dictionary; owned_by is the same
	# Entity (identity); modifiers is the same array (reference).


func test_skill_node_forwards_owned_by_into_state_and_emits() -> void:
	pending(_PENDING)
	# node.owned_by = e  →  node.state.owned_by == e and owner_changed fired once;
	# node.state.owned_by = null  →  node.owned_by reads null, no signal.


func test_board_identity_survives_the_move() -> void:
	pending(_PENDING)
	# node.node_board is node.state.board, same instance before and after a
	# stat mint (VisionSystem binds stat_created on it).
