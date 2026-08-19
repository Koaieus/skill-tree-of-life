@tool
extends GutTest

## Tag grant channel (#267): a refcounted, ledgered second grant target
## alongside StatModifier, sharing EffectInstance's grant ledger so
## revoke_all() sweeps both channels uniformly. See docs/design/status-tags.md.

const _BOARD := preload("res://entity/default_entity_board.tres")
const _NODE_SCENE := preload("res://skill_node/skill_node.tscn")


## Implements nothing — a bare carrier for manual ctx.grant/grant_tag calls.
class InertEffect extends Effect:
	pass


func _make_entity() -> Entity:
	var ent := autofree(Entity.new()) as Entity
	ent.display_name = "T"
	ent.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	return ent


func _make_node() -> SkillNode:
	var n: SkillNode = _NODE_SCENE.instantiate()
	autofree(n)
	return n


func _mod(stat_id: StringName, value: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = value
	return m


# ── Mixed-channel revoke_all ────────────────────────────────────────────────

func test_revoke_all_clears_both_a_modifier_grant_and_a_tag_grant() -> void:
	var ent := _make_entity()
	var node := _make_node()
	add_child(ent)
	add_child(node)
	await get_tree().process_frame
	node.owned_by = ent

	var inst := ent.grant_effect(InertEffect.new(), node)
	inst.context.grant(_mod(&"armor", 5.0), node)
	inst.context.grant_tag(&"marked", node)

	assert_eq(float(node.get_local_value(&"armor")), ent.stat_board.armor.value + 5.0)
	assert_true(node.has_tag(&"marked"))

	inst.context.revoke_all()

	assert_eq(float(node.get_local_value(&"armor")), ent.stat_board.armor.value,
		"modifier grant reverted")
	assert_false(node.has_tag(&"marked"), "tag grant reverted")


func test_revoke_all_clears_entity_wide_tag_alongside_a_board_modifier() -> void:
	var ent := _make_entity()
	add_child(ent)
	await get_tree().process_frame

	var inst := ent.grant_effect(InertEffect.new())
	inst.context.grant(_mod(&"strength", 3.0))
	inst.context.grant_tag(&"poisoned")

	assert_true(ent.has_tag(&"poisoned"))
	inst.context.revoke_all()
	assert_false(ent.has_tag(&"poisoned"))


# ── Refcount ─────────────────────────────────────────────────────────────────

func test_two_sources_granting_the_same_tag_need_both_revoked() -> void:
	var ent := _make_entity()
	var node := _make_node()
	add_child(ent)
	add_child(node)
	await get_tree().process_frame
	node.owned_by = ent

	var a := ent.grant_effect(InertEffect.new(), node)
	var b := ent.grant_effect(InertEffect.new(), node)
	a.context.grant_tag(&"lifeline", node)
	b.context.grant_tag(&"lifeline", node)

	assert_true(node.has_tag(&"lifeline"))
	ent.revoke_effect(a)
	assert_true(node.has_tag(&"lifeline"), "second source still holds it")
	ent.revoke_effect(b)
	assert_false(node.has_tag(&"lifeline"), "last source revoked — tag clears")


## Revoking a single token from one instance's own duplicate grant only drops
## its own refcount contribution.
func test_revoking_one_of_two_tokens_from_the_same_instance_leaves_the_other() -> void:
	var ent := _make_entity()
	var node := _make_node()
	add_child(ent)
	add_child(node)
	await get_tree().process_frame
	node.owned_by = ent

	var inst := ent.grant_effect(InertEffect.new(), node)
	# `grant_tag` returns Variant, so `:=` would INFER Variant — which GUT's
	# custom warning settings treat as a parse error and then silently skips
	# the whole file. Annotate explicitly. See .claude/rules/testing.md.
	var t1: Variant = inst.context.grant_tag(&"x", node)
	var _t2: Variant = inst.context.grant_tag(&"x", node)

	assert_true(node.has_tag(&"x"))
	inst.context.revoke(t1)
	assert_true(node.has_tag(&"x"), "one grant remains")
	inst.context.revoke_all()
	assert_false(node.has_tag(&"x"))


# ── get_active_tags ──────────────────────────────────────────────────────────

func test_get_active_tags_reports_the_live_set() -> void:
	var ent := _make_entity()
	var node := _make_node()
	add_child(ent)
	add_child(node)
	await get_tree().process_frame
	node.owned_by = ent

	var inst := ent.grant_effect(InertEffect.new(), node)
	inst.context.grant_tag(&"a", node)
	var token_b: Variant = inst.context.grant_tag(&"b", node)

	var active := node.get_active_tags()
	assert_true(active.has(&"a"))
	assert_true(active.has(&"b"))
	assert_eq(active.size(), 2)

	inst.context.revoke(token_b)
	active = node.get_active_tags()
	assert_true(active.has(&"a"))
	assert_false(active.has(&"b"))
	assert_eq(active.size(), 1)


func test_entity_get_active_tags_mirrors_node_shape() -> void:
	var ent := _make_entity()
	add_child(ent)
	await get_tree().process_frame

	assert_eq(ent.get_active_tags().size(), 0)
	var inst := ent.grant_effect(InertEffect.new())
	inst.context.grant_tag(&"stunned")
	assert_eq(ent.get_active_tags(), [&"stunned"] as Array[StringName])


# ── has_tag on an untouched carrier ──────────────────────────────────────────

func test_has_tag_false_when_never_granted() -> void:
	var node := _make_node()
	add_child(node)
	await get_tree().process_frame
	assert_false(node.has_tag(&"anything"))
