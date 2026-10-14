extends GutTest

## A charged blade piece looks armed and a spend reads as spending: the two
## [BladeNode] channels [member BladeNode.charges] and
## [member BladeNode.spend_progress] are pure functions of
## ([member SkillBlade.pop_result], t), like `death_progress`
## (`.claude/rules/presentation-clock.md`). The look is judged in the sandbox.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _V := BladePopResolver.Contact.Verdict


func _build_blade(charges: int, spend_window: float = 0.2) -> SkillBlade:
	var graph := _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var pivot := _SKILL_NODE_SCENE.instantiate() as SkillNode
	var member := _SKILL_NODE_SCENE.instantiate() as SkillNode
	graph.skill_nodes_container.add_child(pivot)
	graph.skill_nodes_container.add_child(member)
	member.position = Vector2(80.0, 0.0)
	var blade := SkillBlade.SCENE.instantiate() as SkillBlade
	add_child_autofree(blade)
	var style: BladeStyle = BladeNode.DEFAULT_STYLE.duplicate(true) as BladeStyle
	style.spend_window = spend_window
	blade.style = style
	var nodes: Array[SkillNode] = [pivot, member]
	var fill := BladeVertexFill.new()
	blade.build_from_skill_nodes(nodes, pivot, [[pivot, member]], null, fill)
	# The fixture nodes carry no explosive status; arm the member's piece the
	# way the fill would have, then rebuild the visuals from it.
	blade.state.vertex_charges[1] = charges
	blade._snapshot_build_charges()
	return blade


## One explosive contact on piece 1 at `t`: the striker held `n`, the node `m`
## (resonance 1), so both powers are what the resolver would have recorded.
func _contact(t: float, n: int, m: int, verdict: int) -> BladePopResolver.Contact:
	var row := BladePopResolver.Contact.new(t, null)
	var shared := mini(n, m)
	row.striker_power = n + shared if n > 0 else 0
	row.node_power = m + shared if m > 0 else 0
	row.verdicts[1] = verdict
	return row


func _traj() -> BladeTrajectory:
	var traj := BladeTrajectory.new()
	traj.sample_dt = 0.05
	traj.samples = []
	for i in 30:
		traj.samples.append(PackedVector2Array([Vector2.ZERO, Vector2(80.0, 0.0)]))
	return traj


func test_build_shows_the_pieces_charges() -> void:
	var blade := _build_blade(3)
	assert_eq(blade.get_node_visuals()[1].charges, 3, "an armed piece shows its charges at build")
	assert_eq(blade.get_node_visuals()[0].charges, 0, "an unarmed piece shows none")


func test_three_on_five_spends_all_three_and_the_piece_is_dead_there() -> void:
	var blade := _build_blade(3)
	blade.pop_result = BladePopResolver.Result.new()
	blade.pop_result.contacts.append(_contact(0.5, 3, 5, _V.POPPED))
	blade.pop_result.dead_at[1] = 0.5
	assert_eq(blade._charges_at(1, 0.4), 3, "all three before the contact")
	assert_eq(blade._charges_at(1, 0.5), 0, "none at contact.t")
	assert_true(blade.pop_result.is_dead(1, 0.5), "and the piece is dead there")
	assert_eq(blade._spend_progress_at(1, 0.6), 0.0, "a popped piece shows the pop, not a spend flare")


func test_a_spent_piece_loses_the_shared_count_and_lives() -> void:
	var blade := _build_blade(5)
	blade.pop_result = BladePopResolver.Result.new()
	blade.pop_result.contacts.append(_contact(0.5, 5, 2, _V.SPENT))
	assert_eq(blade._charges_at(1, 0.49), 5, "untouched before the contact")
	assert_eq(blade._charges_at(1, 0.5), 3, "5 on 2 spends min(5, 2) = 2")
	blade.pop_result.contacts.append(_contact(0.8, 3, 0, _V.SPENT))
	assert_eq(blade._charges_at(1, 0.9), 2, "a charge spent into an unarmed node is one")


func test_spend_progress_ramps_over_the_window_from_the_latest_spend() -> void:
	var blade := _build_blade(5, 0.2)
	blade.pop_result = BladePopResolver.Result.new()
	blade.pop_result.contacts.append(_contact(0.5, 5, 2, _V.SPENT))
	assert_eq(blade._spend_progress_at(1, 0.4), 0.0, "0 before the contact")
	assert_eq(blade._spend_progress_at(1, 0.5), 0.0, "the ramp starts at contact.t")
	assert_almost_eq(blade._spend_progress_at(1, 0.6), 0.5, 0.001, "halfway through the window")
	assert_almost_eq(blade._spend_progress_at(1, 0.9), 1.0, 0.0001, "done after the window")
	blade.pop_result.contacts.append(_contact(1.0, 3, 0, _V.SPENT))
	assert_almost_eq(blade._spend_progress_at(1, 1.05), 0.25, 0.001, "the latest spend restarts the ramp")
	assert_eq(blade._spend_progress_at(0, 0.6), 0.0, "a piece with no SPENT verdict stays 0")


func test_playback_drives_both_channels() -> void:
	var blade := _build_blade(5, 0.2)
	blade.pop_result = BladePopResolver.Result.new()
	blade.pop_result.contacts.append(_contact(0.5, 5, 2, _V.SPENT))
	var bn: BladeNode = blade.get_node_visuals()[1]
	blade._apply_playback_frame(0.3, _traj(), [], true)
	assert_eq(bn.charges, 5)
	assert_eq(bn.spend_progress, 0.0)
	blade._apply_playback_frame(0.6, _traj(), [], true)
	assert_eq(bn.charges, 3)
	assert_almost_eq(bn.spend_progress, 0.5, 0.001)


## The 100-on-1 case: the striker spends, the charged piece in the node's reach
## shrugs, the plain one in reach is dead. Only the shrugged piece's sheen ramps.
func test_shrug_progress_ramps_only_for_a_shrugged_piece() -> void:
	var blade := _build_blade(5)
	(blade.style as BladeStyle).shrug_window = 0.2
	blade.pop_result = BladePopResolver.Result.new()
	var row := BladePopResolver.Contact.new(0.5, null)
	row.striker_power = 101
	row.node_power = 2
	row.piece_reach = 120.0
	row.verdicts = {1: _V.SPENT, 2: _V.SHRUGGED, 3: _V.POPPED}
	blade.pop_result.contacts.append(row)
	blade.pop_result.dead_at[3] = 0.5
	assert_eq(blade._shrug_progress_at(2, 0.4), 0.0, "0 before the contact")
	assert_eq(blade._shrug_progress_at(2, 0.5), 0.0, "the ramp starts at contact.t")
	assert_almost_eq(blade._shrug_progress_at(2, 0.6), 0.5, 0.001, "halfway through the window")
	assert_almost_eq(blade._shrug_progress_at(2, 0.9), 1.0, 0.0001, "done after the window")
	assert_eq(blade._shrug_progress_at(1, 0.6), 0.0, "the spending striker never shrugs")
	assert_eq(blade._shrug_progress_at(3, 0.6), 0.0, "the plain piece is dead, not shrugging")
	assert_true(blade.pop_result.is_dead(3, 0.6), "and it is dead there")
