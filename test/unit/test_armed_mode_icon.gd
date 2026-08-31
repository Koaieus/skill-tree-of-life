extends GutTest
const _EDGE_SCENE := preload("res://graph/edge.tscn")

## Armed-mode cursor-badge resolution (#664).
##
## The visual half — does a 24px glyph read, does the plate hold contrast over a
## bloomed node — cannot be judged headless
## (`docs/domain/godot-workflow.md`), so the whole point of
## `PlayerInputController.get_armed_icon()` / `get_armed_icon_tint()` being PURE
## functions is that THIS is testable. They are the only things the badge reads.
##
## Two rules under test that a plausible refactor would silently break:
##   - The TOP of the stack decides the badge, while the BASE decides the glow.
##     **Owner call 2026-08-29:** "top first" — for the badge only; the
##     2026-08-21 base-first call stands for the outline. Pinned by
##     `test_clamp_over_melee_badges_the_clamp_while_the_glow_stays_red`.
##   - `armed_icon_changed` dedupes INDEPENDENTLY of `armed_tint_changed`. With
##     opposite walk directions, arming a clamp on an armed melee plan moves the
##     badge and leaves the tint alone — so folding the icon emit under the
##     tint's early return loses exactly the headline case. That is
##     `test_icon_signal_fires_when_the_tint_signal_does_not`, the single most
##     important assertion in this file.
##
## Expected colours come from the shipped sources — `StatDef.tint_color` for the
## attack triple, `ActionPalette` for everything else — never from literals. A
## hardcoded expectation would recreate the second palette
## `.claude/rules/ui-palette.md` forbids, and would keep passing after someone
## retuned the real one.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _PALETTE := preload("res://ui/theme/action_palette.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _battle: BattleSystem
var _tm: TurnManager
var _ctl: PlayerInputController
var _player: Entity
var _nodes: Array[SkillNode]


func before_each() -> void:
	_graph = _GRAPH_SCENE.instantiate()
	_graph.name = "TestGraph"
	add_child_autofree(_graph)

	_nodes = []
	for i in 3:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = "N%d" % i
		_graph.skill_nodes_container.add_child(sn)
		_nodes.append(sn)
	_add_edge(_nodes[0], _nodes[1])
	_add_edge(_nodes[1], _nodes[2])

	_alloc = AllocationSystem.new()
	_alloc.graph = _graph
	add_child_autofree(_alloc)

	_tm = autofree(TurnManager.new())
	add_child(_tm)

	_battle = autofree(BattleSystem.new())
	_battle.graph = _graph
	_battle.turn_manager = _tm
	add_child(_battle)

	_player = autofree(Entity.new())
	_player.display_name = "Player"
	_player.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	_graph.entities_container.add_child(_player)

	await get_tree().process_frame

	_player.core_location = _nodes[0]
	_alloc.force_allocate(_player, _nodes[0])
	_alloc.force_allocate(_player, _nodes[1])

	_tm.start_turn(_player)
	_player.stat_board.skill_points.grant(5)
	_player.stat_board.action_points.restore_to_full()

	_ctl = PlayerInputController.new()
	_ctl.graph = _graph
	_ctl.allocation_system = _alloc
	_ctl.battle_system = _battle
	_ctl.turn_manager = _tm
	_ctl.player = _player
	add_child_autofree(_ctl)


func _add_edge(a: SkillNode, b: SkillNode) -> void:
	var e := _EDGE_SCENE.instantiate() as Edge
	e.from = a
	e.to = b
	_graph.edges_container.add_child(e)


## The attribute identity colour, read the way production reads it — not a
## literal. Unlifted: the emissive tier is ArmedModeIcon's, not the stack's.
func _stat_color(stat_id: StringName) -> Color:
	var def := StatRegistry.get_def(stat_id)
	assert_not_null(def, "StatRegistry has no def for %s" % stat_id)
	return def.tint_color


func _icon(name: String) -> Texture2D:
	return load("res://assets/icons/addons/%s.png" % name)


# --- 1. nothing armed --------------------------------------------------------

func test_nothing_armed_has_no_badge() -> void:
	assert_null(_ctl.get_armed_icon(),
			"an idle board's click is the plain default allocate — no badge")
	assert_eq(_ctl.get_armed_icon_tint().a, 0.0)


func test_arming_plain_allocate_still_has_no_badge() -> void:
	# Decision 3: badge present ⇔ the click is modal. ALLOCATE is deliberately
	# not an ArmedMode, and that is the whole rule the player learns for free.
	_ctl.arm_manage_verb(PlayerInputController.ManageVerb.ALLOCATE)
	assert_null(_ctl.get_armed_icon(),
			"Allocate must never get a badge — it is the unmodal default")


# --- 2. the attack triple ----------------------------------------------------

func test_melee_badges_the_bare_hilt_in_strength_red_before_a_pivot() -> void:
	# #683: arming Melee is not yet an aimed swing — the badge shows the sword
	# WITHOUT its blade until a pivot is picked. Same STR red either way; the
	# phase is carried by the silhouette, the mode by the colour.
	_ctl.on_attack_mode_requested(BattleSystem.AttackMode.MELEE)
	assert_eq(_ctl.get_armed_icon(), _icon("armed_melee_hilt"))
	assert_eq(_ctl.get_armed_icon_tint(), _stat_color(&"strength"))


func test_ranged_and_magic_badge_their_own_art() -> void:
	_ctl.on_attack_mode_requested(BattleSystem.AttackMode.RANGED)
	assert_eq(_ctl.get_armed_icon(), _icon("armed_ranged"))
	assert_eq(_ctl.get_armed_icon_tint(), _stat_color(&"dexterity"))

	_ctl.on_attack_mode_requested(BattleSystem.AttackMode.MAGIC)
	assert_eq(_ctl.get_armed_icon(), _icon("armed_magic"))
	assert_eq(_ctl.get_armed_icon_tint(), _stat_color(&"intelligence"))


# --- 2b. melee's two phases (#683) -------------------------------------------

## Set the melee pivot the way a player does — through the controller's real
## left-click channel, not by poking `plan.source`. The badge is downstream of
## the signal that click emits, so a hand-set field would test the branch while
## silently skipping the wiring this issue exists to fix.
func _pick_pivot(node: SkillNode) -> MeleeAttackPlan:
	_ctl.route_left_click(node)
	var plan := _ctl._active_attack_plan() as MeleeAttackPlan
	assert_not_null(plan, "fixture check: melee should still be the active plan")
	assert_not_null(plan.source, "fixture check: the left-click should set the pivot")
	return plan


func test_picking_the_pivot_swaps_the_hilt_for_the_blade() -> void:
	_ctl.on_attack_mode_requested(BattleSystem.AttackMode.MELEE)
	assert_eq(_ctl.get_armed_icon(), _icon("armed_melee_hilt"), "unaimed: hilt")

	_pick_pivot(_nodes[0])

	assert_eq(_ctl.get_armed_icon(), _icon("armed_melee"),
			"pivot picked — the blade is on the sword")
	assert_eq(_ctl.get_armed_icon_tint(), _stat_color(&"strength"),
			"both phases burn the SAME red, off the same stack walk")


func test_popping_the_pivot_returns_the_badge_to_the_hilt() -> void:
	_ctl.on_attack_mode_requested(BattleSystem.AttackMode.MELEE)
	var plan := _pick_pivot(_nodes[0])

	assert_true(plan.pop(), "fixture check: the plan pops its pivot before it cancels")
	assert_null(plan.source)
	assert_eq(_ctl.get_armed_icon(), _icon("armed_melee_hilt"),
			"back to no pivot — back to the hilt")


func test_setting_the_pivot_fires_the_icon_signal() -> void:
	# THE regression this issue exists for. `_refresh_armed_state` used to hang
	# off `attack_plan_changed` alone, which is plan LIFECYCLE — setting a pivot
	# is plan STATE and never moved it, so the badge would resolve correctly and
	# nobody would ever ask it to. Guarded the way decision 12 is guarded.
	_ctl.on_attack_mode_requested(BattleSystem.AttackMode.MELEE)

	watch_signals(_ctl)
	_pick_pivot(_nodes[0])

	assert_signal_emit_count(_ctl, "armed_icon_changed", 1,
			"the badge MUST move when the pivot lands")
	assert_signal_emitted_with_parameters(_ctl, "armed_icon_changed",
			[_icon("armed_melee"), _stat_color(&"strength")], 0)
	assert_signal_emit_count(_ctl, "armed_tint_changed", 0,
			"the glow is unchanged — it is the same mode, in its second phase")


func test_ranged_and_magic_are_untouched_by_the_pivot_split() -> void:
	# Melee-only, by owner call. Neither of the others has a pivot phase, and
	# neither may pick up the hilt by falling through the new branch.
	for mode in [BattleSystem.AttackMode.RANGED, BattleSystem.AttackMode.MAGIC]:
		_ctl.on_attack_mode_requested(mode)
		assert_ne(_ctl.get_armed_icon(), _icon("armed_melee_hilt"),
				"mode %d must never badge the melee hilt" % mode)
	_ctl.on_attack_mode_requested(BattleSystem.AttackMode.RANGED)
	assert_eq(_ctl.get_armed_icon(), _icon("armed_ranged"))
	_ctl.on_attack_mode_requested(BattleSystem.AttackMode.MAGIC)
	assert_eq(_ctl.get_armed_icon(), _icon("armed_magic"))


# --- 3. the two walks disagree, on purpose -----------------------------------

func test_clamp_over_melee_badges_the_clamp_while_the_glow_stays_red() -> void:
	# The headline case. TempUpgrade is EARLIER in _armed_modes than AttackPlan
	# (it pops first), so the top-first badge walk finds it and the base-first
	# tint walk does not. Both statements are true at once: the border says
	# "you are wielding Melee", the badge says "this click places a clamp".
	_ctl.on_attack_mode_requested(BattleSystem.AttackMode.MELEE)
	_ctl.arm_temp_upgrade(MeleeAttackPlan.TEMP_UPGRADE_CATALOG[0])
	assert_true(_ctl._temp_upgrade_arm != null,
			"fixture check: the temp upgrade should be armed on top")

	assert_eq(_ctl.get_armed_icon(), _icon("addon_clamp"),
			"the badge forwards the addon scene's own authored icon")
	assert_eq(_ctl.get_armed_icon_tint(), _PALETTE.color_for(&"clamp"))
	assert_eq(_ctl.get_armed_tint(), _stat_color(&"strength"),
			"the glow still reads the BASE of the stack — the walks diverge")


func test_the_badge_forwards_the_addon_scenes_own_icon() -> void:
	# Not a second copy of the texture reference: the tray card the player
	# pressed a second earlier renders this exact Texture2D off the same scene.
	var upgrade: Dictionary = MeleeAttackPlan.TEMP_UPGRADE_CATALOG[1]
	_ctl.on_attack_mode_requested(BattleSystem.AttackMode.MELEE)
	_ctl.arm_temp_upgrade(upgrade)

	var probe := (upgrade.scene as PackedScene).instantiate()
	var authored: Texture2D = (probe as SkillNodeAddon).icon
	probe.free()

	assert_eq(_ctl.get_armed_icon(), authored)
	assert_eq(_ctl.get_armed_icon_tint(), _PALETTE.color_for(&"spike_ring"))


# --- 4. the dedup trap -------------------------------------------------------

func test_icon_signal_fires_when_the_tint_signal_does_not() -> void:
	# DECISION 12's regression guard. `_refresh_armed_state` used to early-return
	# on an unchanged tint; anything emitted below that return is swallowed. With
	# base-first tint and top-first icon, arming a clamp over an armed melee plan
	# is exactly that case — the headline scenario of #664 silently breaking.
	_ctl.on_attack_mode_requested(BattleSystem.AttackMode.MELEE)

	watch_signals(_ctl)
	_ctl.arm_temp_upgrade(MeleeAttackPlan.TEMP_UPGRADE_CATALOG[0])

	assert_signal_emit_count(_ctl, "armed_tint_changed", 0,
			"the glow is unchanged — the base of the stack is still the plan")
	assert_signal_emit_count(_ctl, "armed_icon_changed", 1,
			"the badge MUST still fire; each channel dedupes against its own cache")
	assert_signal_emitted_with_parameters(_ctl, "armed_icon_changed",
			[_icon("addon_clamp"), _PALETTE.color_for(&"clamp")], 0)


func test_a_refresh_that_changed_nothing_does_not_re_fire() -> void:
	_ctl.on_attack_mode_requested(BattleSystem.AttackMode.MELEE)
	watch_signals(_ctl)
	_ctl._refresh_armed_state()
	assert_signal_emit_count(_ctl, "armed_icon_changed", 0)


# --- 5. popping restores the level beneath -----------------------------------

func test_popping_the_clamp_restores_the_melee_badge() -> void:
	_ctl.on_attack_mode_requested(BattleSystem.AttackMode.MELEE)
	_ctl.arm_temp_upgrade(MeleeAttackPlan.TEMP_UPGRADE_CATALOG[0])

	watch_signals(_ctl)
	assert_true(_ctl._pop_armed_mode(), "the temp upgrade is the top level")

	assert_eq(_ctl.get_armed_icon(), _icon("armed_melee_hilt"),
			"a level with no icon falls through — it never blanks the badge")
	assert_eq(_ctl.get_armed_icon_tint(), _stat_color(&"strength"))
	assert_signal_emit_count(_ctl, "armed_icon_changed", 1)


# --- 6. the Manage verbs -----------------------------------------------------

func test_each_manage_verb_badges_its_own_icon_and_colour() -> void:
	var expected := {
		PlayerInputController.ManageVerb.DEALLOCATE:
				[_icon("armed_deallocate"), _PALETTE.color_for(&"deallocate")],
		PlayerInputController.ManageVerb.STAKE:
				[_icon("armed_stake"), _PALETTE.color_for(&"stake")],
		PlayerInputController.ManageVerb.EXTRACT:
				[_icon("armed_extract"), _PALETTE.color_for(&"extract")],
	}
	for verb in expected:
		_ctl.arm_manage_verb(verb)
		assert_true(_ctl._has_armed_mode(),
				"fixture check: verb %s should actually be armed" % verb)
		assert_eq(_ctl.get_armed_icon(), expected[verb][0], "icon for verb %s" % verb)
		assert_eq(_ctl.get_armed_icon_tint(), expected[verb][1], "tint for verb %s" % verb)
		_ctl.arm_manage_verb(PlayerInputController.ManageVerb.NONE)

	assert_null(_ctl.get_armed_icon(), "NONE leaves nothing armed and no badge")


func test_stake_and_extract_are_mirrored_art_told_apart_by_colour() -> void:
	# One SVG and its baked vertical flip (`mapping.txt`'s optional flip_v
	# column), so the colour is doing the discriminating work. Both halves have
	# to hold or the pair becomes ambiguous.
	assert_ne(_icon("armed_stake"), _icon("armed_extract"))
	assert_ne(_PALETTE.color_for(&"stake"), _PALETTE.color_for(&"extract"))


# --- 7. core move ------------------------------------------------------------

func test_core_move_targeting_badges_the_move_icon() -> void:
	_ctl.enter_core_move_targeting()
	assert_true(_ctl._has_armed_mode(), "fixture check: core-move should be armed")
	assert_eq(_ctl.get_armed_icon(), _icon("armed_move_core"))
	assert_eq(_ctl.get_armed_icon_tint(), _PALETTE.color_for(&"move_core"))
	assert_eq(_ctl.get_armed_tint().a, 0.0,
			"core-move still contributes no GLOW — only the badge is new")


# --- 8. mass action ----------------------------------------------------------

func test_a_pending_mass_action_has_no_badge() -> void:
	# Decision 11: a confirm modal is up and the controller is frozen (#486), so
	# there is no next click for a badge to describe.
	var cascade: Array[SkillNode] = [_nodes[1]]
	var request := MassActionRequest.new(
			_player, MassActionRequest.Verb.DEALLOCATE, cascade)
	_ctl._mass_action_request = request
	assert_true(_ctl.pending_mass_action() != null, "fixture check")
	assert_null(_ctl.get_armed_icon())
	_ctl._mass_action_request = null


# --- 9. the structural guard -------------------------------------------------

func test_every_level_with_an_icon_also_names_a_colour() -> void:
	# A loop over `_armed_modes` rather than a list of today's nine states, so a
	# future TENTH armed mode cannot ship a white-modulated badge by omission.
	# Each level is armed in turn via its own real entry point.
	var arms: Array[Callable] = [
		func() -> void: _ctl.on_attack_mode_requested(BattleSystem.AttackMode.MELEE),
		func() -> void: _ctl.on_attack_mode_requested(BattleSystem.AttackMode.RANGED),
		func() -> void: _ctl.on_attack_mode_requested(BattleSystem.AttackMode.MAGIC),
		func() -> void:
			_ctl.on_attack_mode_requested(BattleSystem.AttackMode.MELEE)
			_ctl.arm_temp_upgrade(MeleeAttackPlan.TEMP_UPGRADE_CATALOG[0]),
		func() -> void:
			_ctl.on_attack_mode_requested(BattleSystem.AttackMode.MELEE)
			_ctl.arm_temp_upgrade(MeleeAttackPlan.TEMP_UPGRADE_CATALOG[1]),
		func() -> void: _ctl.arm_manage_verb(PlayerInputController.ManageVerb.DEALLOCATE),
		func() -> void: _ctl.arm_manage_verb(PlayerInputController.ManageVerb.STAKE),
		func() -> void: _ctl.arm_manage_verb(PlayerInputController.ManageVerb.EXTRACT),
		func() -> void: _ctl.enter_core_move_targeting(),
	]
	for arm in arms:
		_ctl.clear_transient_state()
		_battle.cancel_attack()
		arm.call()
		for mode in _ctl._armed_modes:
			if not mode.is_armed() or mode.icon() == null:
				continue
			assert_gt(mode.icon_tint().a, 0.0,
					"%s returns an icon but no colour — it would modulate white"
					% mode.get_script().resource_path)


# --- the presentation half: ArmedModeIcon owns the emissive tier -------------

const _ICON_SCENE := preload("res://ui/hud/armed_mode_icon/armed_mode_icon.tscn")


func test_the_badge_lifts_the_identity_colour_to_its_own_tier() -> void:
	var badge: ArmedModeIcon = _ICON_SCENE.instantiate()
	add_child_autofree(badge)
	await get_tree().process_frame

	var art := _icon("armed_melee")
	var red := _stat_color(&"strength")
	badge._on_armed_icon_changed(art, red)

	var rect: TextureRect = badge.get_node("%IconTexture")
	assert_eq(rect.texture, art)
	assert_eq(rect.modulate, Emissive.tint_peak(red, badge.glow_stops),
			"the badge, not the armed stack, applies the tier")
	assert_true(badge.get_node("%Badge").visible)

	# A transparent tint is "this level named no colour", NOT "blank it".
	badge._on_armed_icon_changed(art, Color.TRANSPARENT)
	assert_eq(rect.modulate, Color.WHITE)

	badge._on_armed_icon_changed(null, Color.TRANSPARENT)
	assert_false(badge.get_node("%Badge").visible,
			"no icon means the badge is not in the frame at all")


func test_the_badge_stays_near_inert_so_it_cannot_bloom_into_mush() -> void:
	# A bloom halo on a 24px glyph destroys exactly the legibility the badge
	# exists for. In-viewport rendering buys the colour language, not glow.
	var badge: ArmedModeIcon = _ICON_SCENE.instantiate()
	add_child_autofree(badge)
	assert_lte(badge.glow_stops, Emissive.LABEL,
			"the shipped tier must stay at or below LABEL — never VALUE")
	assert_eq(badge.layer, ZLayers.ARMED_MODE_ICON)


const ZLayers = preload("res://ui/z_layers.gd")


func test_the_badge_draws_above_the_hud_unlike_the_glow() -> void:
	# Inverted on purpose: the glow frames the play area and the tray draws over
	# it; a cursor badge must never be occluded by anything.
	assert_gt(ZLayers.ARMED_MODE_ICON, ArmedModeGlow.LAYER)
	assert_lt(ZLayers.ARMED_MODE_ICON, 100,
			"above 100 it drops out of `background_canvas_max_layer` and stops glowing")


# --- the palette is one source, not a second copy ----------------------------

func test_the_palette_does_not_restate_the_attribute_colours() -> void:
	# `.claude/rules/ui-palette.md`: StatDef.tint_color is the single source of
	# truth for attribute colours. ActionPalette covers the actions that have no
	# attribute behind them, and must never grow a copy of the attack triple.
	for stat_id in [&"strength", &"dexterity", &"intelligence"]:
		var attr := _stat_color(stat_id)
		for key in [&"allocate", &"move_core", &"deallocate", &"stake",
				&"extract", &"clamp", &"spike_ring"]:
			assert_ne(_PALETTE.color_for(key), attr,
					"%s duplicates the %s identity colour" % [key, stat_id])


func test_an_unmapped_palette_key_falls_through_rather_than_blanking() -> void:
	assert_eq(_PALETTE.color_for(&"no_such_action"), Color.TRANSPARENT)
