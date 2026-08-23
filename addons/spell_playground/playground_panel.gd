## Bottom-panel preview harness for spells. Holds a small isolated world — a
## caster with a four-node territory wired into a defender's sixteen — plus a
## control strip (Cast + status + read-only spell summary).
##
## The spell itself lives wherever the user is editing it — this panel keeps a
## live reference and re-reads its exports on every Cast, so the inspector is the
## single source of truth.
##
## [b]The cast goes through the real systems (#536/#545).[/b] The panel mounts
## `sandbox_world.gd` — the anti-drift scaffold every played sandbox uses — arms
## a [MagicAttackPlan] with the same two left-clicks the click grammar routes in
## game, and calls [method BattleSystem.launch_attack]. That is what makes the
## preview an execution rather than a lookalike: the compute half resolves on a
## [method CombatWorld.shadow] and captures an [AttackRecord], the apply half
## rebuilds it and lands it on the live world through [OutcomeApplier] on a real
## [BeatClock], and the coordinator that draws it is a pure observer.
##
## It did NOT used to. The panel called [method SpellResolver.resolve] and played
## the coordinator itself, which was correct until "shadow always" landed: that
## call now mints a throwaway shadow, lands the whole cast on it and frees it, so
## the panel spent a release resolving spells perfectly and mutating nothing.
## Reproducing the two halves here would have been a second copy of
## [method BattleSystem.apply_launch_command]; mounting the system that owns them
## is the version that cannot drift.
@tool
extends PanelContainer
## Emitted when the panel wants the host to discard and re-instantiate it
## (#144) — e.g. a stuck `_casting` lock or a launch that never returned, which
## Reset (a board re-arm) can't clear.
signal reload_requested

const _SANDBOX_WORLD: Script = preload("res://scenes/dev/sandbox_world.gd")

const _SELECTED_TINT: Color = Color(1.0, 0.7, 0.7, 1.0)
const _UNSELECTED_TINT: Color = Color(1.0, 1.0, 1.0, 1.0)
## Padding, in authored world units, around the node bounding box the viewport
## fits to.
const _WORLD_PADDING: float = 30.0

## Re-established on every [method _arm_board] so a cast always starts from the
## same board rather than from whatever the last one left behind — the same
## contract `scenes/dev/outcome_playground_world.gd` states for its `arm()`.
## Skill points have to cover all twenty authored claims.
const SKILL_POINTS: float = 60.0
const ACTION_POINTS: float = 6.0
const MANA: float = 20.0

## Flat `spell_range` bonus granted to the cast-from node, in the percent form
## [SpellRangeRules] reads (`1.0 + spell_range / 100`). The playground exists to
## fire a spell at an arbitrary seed, and the real targeting gate is what decides
## whether a seed is legal — so the reach is bought with a stat rather than
## bypassed. 900 % turns Spark's 3 hops into 30, past this graph's diameter, and
## every other targeting rule (hostile-only, min_degree at the source) still
## applies and still reports itself in the status line.
const CASTER_SPELL_RANGE_BONUS: float = 900.0

@onready var cast_button: Button = %CastButton
@onready var reset_button: Button = %ResetButton
@onready var reload_button: Button = %ReloadButton
@onready var status_label: Label = %StatusLabel
@onready var values_label: RichTextLabel = %ValuesLabel
@onready var world: SubViewport = %World
@onready var background: ColorRect = %Background
@onready var graph: Graph = %Graph
@onready var caster_entity: Entity = %CasterEntity
@onready var defender_entity: Entity = %DefenderEntity
## The cast-from node, and the caster's core.
@onready var caster_node: SkillNode = %C_hub
@onready var spell_list: OptionButton = %SpellList
@onready var browse_button: Button = %BrowseButton
@onready var spell_damage_slider: HSlider = %SpellDamageSlider
@onready var spell_damage_label: Label = %SpellDamageLabel
@onready var _world_container: SubViewportContainer = $HBox/WorldContainer

var _spell: SpellDef = null
var _selected_target: SkillNode = null
## True from Cast until the launch returns. A re-arm (or a second cast) inside
## that window would interleave with a mutation loop still walking its beats, so
## both buttons are gated on it rather than trying to cancel one in flight.
var _casting: bool = false
## Populated from attack/spell/defs/ — every .tres SpellDef in the directory.
var _listed_spells: Array[SpellDef] = []

## The systems this panel drives, and the pieces of them it talks to.
var _systems: Node = null
var _alloc: AllocationSystem = null
var _battle: BattleSystem = null

## Scene-authored ownership, captured before anything mutates. A cast can now
## really kill a node and cascade its neighbours out of the defender's territory,
## so `owned_by` is no longer readable off the scene once the first spell lands —
## this is what Reset replays.
var _authored_owners: Dictionary[SkillNode, Entity] = {}
var _authored_cores: Dictionary[Entity, SkillNode] = {}
## Bounding box of the authored node positions; the viewport fits to it.
var _content_rect: Rect2 = Rect2()


func _ready() -> void:
	# Bring-up, before anything reads a board or resolves a spell. `Entity._ready`
	# short-circuits under the editor hint, so in the bottom panel this is the
	# only call that ever runs; headless (GUT) the entity already self-initialized
	# and this is the documented no-op.
	caster_entity.initialize()
	defender_entity.initialize()
	_capture_authored_world()
	_build_systems()
	_arm_board()
	_grant_caster_reach()
	cast_button.pressed.connect(_cast)
	reset_button.pressed.connect(_reset_state)
	reload_button.pressed.connect(reload_requested.emit)
	spell_damage_slider.value_changed.connect(_on_spell_damage_changed)
	world.size_changed.connect(_layout_world)
	_populate_spell_list()
	spell_list.item_selected.connect(_on_spell_list_selected)
	browse_button.pressed.connect(_on_browse_pressed)
	# Deliberately OFF, and this is the one wiring a live tab must not do:
	# the panel hand-routes clicks below because Area2D pickup through an
	# editor-hosted SubViewport is unreliable, and enabling both double-routes
	# whichever pick does land. See docs/domain/sandbox-framework.md.
	world.physics_object_picking = false
	_layout_world()
	# Hit-test clicks on the SubViewportContainer rather than through the
	# SubViewport. The container is 1:1 with the viewport (stretch=true, no
	# camera), so `event.position` is viewport space; `graph.to_local` takes it
	# the rest of the way through the fit transform below.
	_world_container.gui_input.connect(_on_world_gui_input)
	# Default seed: the defender's hub. Interior enough that a 3-hop spell fans
	# out through the loop and down the chain, and hostile, so it passes the
	# targeting gate the way a corner of the caster's own territory would not.
	_selected_target = graph.get_node_or_null(^"Nodes/d_hub") as SkillNode
	_refresh_status()


## The world's topology, ownership and shape are SCENE-AUTHORED — this only
## records what the scene said, so Reset can put it back.
##
## The board is a graph, not a grid, on purpose. A 4×4 cardinal mesh made every
## interior node degree-4 and every rule that reads topology answer the same
## thing everywhere; nothing about it resembled a procgen level. What is authored
## now, and what each part is FOR:
##
##   * `d_chain1..4 → d_tip` — four degree-2 nodes in a row. Trail Blazer's whole
##     mechanic is accumulating through a string of them and detonating at the
##     first junction, and the old grid had no string to walk.
##   * `d_gate` — a cut vertex. Killing it islands `d_limb1` + `d_limb2` (they
##     hold each other up and nothing else), which is what makes the forced
##     dealloc cascade visible here at all.
##   * `d_loop_a/b` and `d_loop_c/d` — two disjoint 3-hop paths from `d_hub` that
##     re-converge on `d_join`. Simultaneous arrival at one node is what the
##     [IncidentReducer] exists for (Resonator), and a mesh where every pair of
##     paths converges everywhere cannot isolate it.
##   * `d_hub` carries a self-loop, and degree 5; `d_entry`, `d_core` and `d_tip`
##     are degree-1 leaves. The board spans degrees 1..5 so `min_degree` gating
##     and degree-reading propagation have something to discriminate.
##   * `d_core` sits behind `d_join`, two leaves away from anything — the
##     defender survives ordinary casts, and killing it is a deliberate act.
##
## The caster's own four nodes are not scenery: [method SpellBook.is_castable]
## measures `min_degree` over the caster's OWNED subgraph, and the deepest spell
## in the catalog wants 3. `C_hub` has exactly three owned neighbours.
func _capture_authored_world() -> void:
	for sn in graph.get_skill_nodes():
		if sn.owned_by != null:
			_authored_owners[sn] = sn.owned_by
	for entity in [caster_entity, defender_entity]:
		if entity.core_location != null:
			_authored_cores[entity] = entity.core_location
	_capture_content_rect()


## Mount the real systems. `attack_vfx` is what makes a spell DRAW — without one
## [method BattleSystem._commit]'s magic branch has nothing to hand the
## coordinator to, and the panel would apply a correct cast invisibly. The
## turn manager is required rather than optional: [method
## BattleSystem.build_launch_command] refuses outright with no `current_entity`.
##
## No `commands` opt. [method BattleSystem.launch_attack] names the editor as a
## first-class no-applier caller and runs the applier's own two halves in the
## applier's own order; the command queue itself has its own harness in the
## Outcome playground tab (#539).
func _build_systems() -> void:
	_systems = _SANDBOX_WORLD.new()
	_systems.name = "Systems"
	add_child(_systems)
	_systems.build(graph, {turn_manager = true, attack_vfx = true})
	_alloc = _systems.allocation_system
	_battle = _systems.battle_system


## Restore the authored starting state through the REAL primitives: strip every
## claim, refill, reset both boards, re-allocate what the scene authored, re-seat
## both cores. Idempotent and total — it is the Reset button and it is also
## bring-up, so there is one answer to "what does this board look like".
##
## [method AllocationSystem.register_scene_authored_ownership] is deliberately
## NOT the call here even though the ownership IS scene-authored: it reads
## `owned_by` off the nodes, and after the first cascade the nodes no longer
## carry it. `force_allocate` from the captured map does the same work
## (SP claim, entity modifiers, node effects, the fill) and survives a kill.
##
## [member AllocationVFX.muted] wraps it: the strips below are genuine
## `force_deallocate` calls and would otherwise shatter the whole board on every
## Reset.
func _arm_board() -> void:
	var vfx: AllocationVFX = _systems.allocation_vfx
	if vfx != null:
		vfx.muted = true
	for sn in graph.get_skill_nodes():
		if sn.owned_by != null:
			_alloc.force_deallocate(sn)
		sn.refill(true)
	for entity in [caster_entity, defender_entity]:
		entity.is_dead = false
		entity.core_location = null
		_reset_board(entity)
	for sn in _authored_owners:
		_alloc.force_allocate(_authored_owners[sn], sn)
	for entity in _authored_cores:
		entity.core_location = _authored_cores[entity]
	if vfx != null:
		vfx.muted = false
	# Whose turn it is is part of the pre-state, not a per-cast step: the plan
	# builder reads it. Never TICKED — writing the plain var IS the whole of "it
	# is the caster's turn" (the standing sandbox rule).
	if _systems.turn_manager != null:
		_systems.turn_manager.current_entity = caster_entity


func _reset_board(entity: Entity) -> void:
	var board: EntityStatBoard = entity.stat_board
	if board == null:
		return
	if board.skill_points != null:
		board.skill_points.wounded = 0
		board.skill_points.staked = 0
		board.skill_points.base_value = SKILL_POINTS
		board.skill_points.set_current(SKILL_POINTS)
	if board.action_points != null:
		board.action_points.set_base_ratcheted(ACTION_POINTS)
		board.action_points.current = ACTION_POINTS
	if board.mana != null:
		board.mana.set_base_ratcheted(MANA)
		board.mana.current = MANA
	for pool in [board.health, board.deallocation_points]:
		if pool != null:
			pool.restore_to_full()
	if board.spell_damage != null:
		board.spell_damage.base_value = spell_damage_slider.value


## Node-local, and applied once — `force_deallocate` revokes granted effects and
## swapped effect-sets, but never a hand-added local modifier, so this survives
## every Reset.
func _grant_caster_reach() -> void:
	var mod := StatModifier.new()
	mod.stat_id = &"spell_range"
	mod.operation = StatModifier.Operation.ADD_BASE
	mod.value = CASTER_SPELL_RANGE_BONUS
	caster_node.add_local_modifier(mod)


## Called by the EditorPlugin whenever a SpellDef becomes the inspected
## object. Tolerates null (e.g. selecting something that isn't a SpellDef
## via something other than the inspector) and rapid re-fires.
func load_spell(spell: SpellDef) -> void:
	if spell == _spell:
		_refresh_status()
		return
	_spell = spell
	_sync_spell_list_selection()
	_refresh_status()


## Scans attack/spell/defs/ and adds every SpellDef .tres to the dropdown.
## Kept separate from the caster's spellbook: the dropdown is for preview
## selection and should show ALL spells, not just the caster's equipped set.
## The two never disagree at the gate — [method SpellBook.is_castable] asks about
## the SOURCE node's degree, not about membership.
func _populate_spell_list() -> void:
	_listed_spells.clear()
	spell_list.clear()
	spell_list.add_item("Pick a spell…")
	spell_list.set_item_disabled(0, true)
	var dir := DirAccess.open("res://attack/spell/defs/")
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var res := load("res://attack/spell/defs/" + file_name) as SpellDef
			if res != null:
				_listed_spells.append(res)
		file_name = dir.get_next()
	dir.list_dir_end()
	_listed_spells.sort_custom(func(a: SpellDef, b: SpellDef): return a.name < b.name)
	for spell in _listed_spells:
		spell_list.add_item(spell.name if spell.name != "" else spell.resource_path.get_file())
	spell_list.select(0)


func _on_spell_list_selected(index: int) -> void:
	var spell_index := index - 1  # slot 0 is the disabled placeholder
	if spell_index < 0 or spell_index >= _listed_spells.size():
		return
	load_spell(_listed_spells[spell_index])


## Keeps the dropdown showing whichever spell is actually loaded, including
## when it arrived via the Inspector "Open Spell Playground" sync rather than
## a dropdown pick.
func _sync_spell_list_selection() -> void:
	var idx := _listed_spells.find(_spell)
	spell_list.select(idx + 1 if idx >= 0 else 0)


## Reveals attack/spell/defs/ in the editor's FileSystem dock — a shortcut to
## authoring a new SpellDef .tres alongside the existing eight.
func _on_browse_pressed() -> void:
	if not Engine.is_editor_hint():
		return
	var dock := EditorInterface.get_file_system_dock()
	if dock == null:
		return
	var target := "res://attack/spell/defs/"
	if not _listed_spells.is_empty() and _listed_spells[0].resource_path != "":
		target = _listed_spells[0].resource_path
	dock.navigate_to_path(target)


## Called by the EditorPlugin on `property_edited` — the spell reference
## hasn't changed but one of its exports has. Re-render the readout so
## live edits show up without re-clicking the inspector button.
func refresh_from_spell() -> void:
	_refresh_status()


func _on_target_clicked(node: SkillNode) -> void:
	# No targeting gate HERE — the selection is just a seed pick. The real gate
	# is the plan's, at Cast, and it reports its refusal in the status line
	# instead of the click silently doing nothing.
	if node == null:
		return
	_selected_target = node
	_refresh_status()


func _on_world_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var hit := _pick_node_at(mb.position)
	if hit != null:
		_on_target_clicked(hit)
		# Container handles the click; don't let it leak back into the editor.
		_world_container.accept_event()


## Find the topmost skill node whose disc covers `viewport_pos`. The graph is
## SCALED to fit the panel (see [method _layout_world]), so the position has to
## come back through its transform before it can be compared against a radius
## authored in world units.
func _pick_node_at(viewport_pos: Vector2) -> SkillNode:
	var local := graph.to_local(viewport_pos)
	var best: SkillNode = null
	var best_d2: float = INF
	for sn in graph.get_skill_nodes():
		if sn == null:
			continue
		var d2 := local.distance_squared_to(sn.position)
		var r := sn.radius
		if d2 <= r * r and d2 < best_d2:
			best = sn
			best_d2 = d2
	return best


func _refresh_status() -> void:
	for sn in graph.get_skill_nodes():
		sn.modulate = _SELECTED_TINT if sn == _selected_target else _UNSELECTED_TINT
	if not is_instance_valid(_spell):
		_spell = null
		status_label.text = "No spell loaded — select a SpellDef in the inspector to sync it here."
		values_label.text = ""
		cast_button.disabled = true
		return
	var target_name: String = _selected_target.name if _selected_target != null else "—"
	status_label.text = "%s · seed → %s" % [_spell.name, target_name]
	cast_button.disabled = (_selected_target == null) or _casting
	values_label.text = _build_values_text(_spell)


func _build_values_text(spell: SpellDef) -> String:
	var lines: PackedStringArray = []
	for p in spell.get_property_list():
		var usage: int = p.usage
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		if (usage & PROPERTY_USAGE_EDITOR) == 0:
			continue
		if (usage & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP)) != 0:
			continue
		var prop_name: String = p.name
		lines.append("[b]%s[/b] = %s" % [prop_name, _format_value(spell.get(prop_name))])
	if lines.is_empty():
		return "[i]<no exports>[/i]"
	return "\n".join(lines)


func _format_value(v: Variant) -> String:
	if v == null:
		return "[i]<null>[/i]"
	if v is bool:
		return "true" if v else "false"
	if v is float:
		# `%.3s` (what this was) is a STRING precision spec — it stringifies the
		# float and truncates to 3 characters, so 12.5 printed as "12.".
		# `%.3g` (what the vfx playground's copy uses) is worse: GDScript's `%`
		# has no `g` conversion at all, so it pushes "unsupported format
		# character" errors every call. `String.num` is the one that works, and
		# it trims trailing zeros — 12.5 -> "12.5", 3.14159 -> "3.142".
		return String.num(v, 3)
	if v is int:
		return str(v)
	if v is String:
		var s: String = v
		return "\"%s\"" % (s if s.length() < 40 else s.substr(0, 37) + "…")
	if v is Array:
		return "[%d item(s)]" % (v as Array).size()
	if v is PackedScene:
		var ps: PackedScene = v
		return ps.resource_path if ps.resource_path != "" else "<inline PackedScene>"
	if v is Resource:
		var r: Resource = v
		var path: String = r.resource_path
		if path != "":
			return "%s (%s)" % [path.get_file(), r.get_class()]
		return "<inline %s>" % str(r.get_class())
	return str(v)


## The authored node positions, as a box. Computed once: nothing moves a node
## after `_ready` any more (see [method _layout_world]).
func _capture_content_rect() -> void:
	var first := true
	for sn in graph.get_skill_nodes():
		var r := maxf(sn.radius, 1.0)
		var box := Rect2(sn.position - Vector2(r, r), Vector2(r, r) * 2.0)
		_content_rect = box if first else _content_rect.merge(box)
		first = false
	_content_rect = _content_rect.grow(_WORLD_PADDING)


## Fit the authored world into the current viewport by SCALING the Graph, not by
## moving its nodes.
##
## This used to overwrite every authored position with a generated 4×4 grid at
## `_ready`, which is why the scene's shape was a lie and why edges had to be
## refreshed behind it. Scaling the Graph instead keeps the authored layout
## intact and — the part that matters beyond tidiness — scales everything
## parented under it by the same factor, VFX included. A [MagicBounceCoordinator]
## arc is authored for a full-screen battlefield (apex 420 px); in a ~340 px
## panel the projectile used to leave the top of the viewport for most of its
## flight, read as "no projectile, damage just appeared", and the panel patched
## the coordinator's `apex_height` by hand to hide it. Under one shared transform
## there is nothing to patch: the arc is as tall relative to the board as it is
## in game.
func _layout_world() -> void:
	if world == null or background == null:
		return
	if _content_rect.size.x <= 0.0 or _content_rect.size.y <= 0.0:
		return
	var size := Vector2(world.size)
	if size.x <= 0.0 or size.y <= 0.0:
		return
	background.size = size
	var fit := minf(size.x / _content_rect.size.x, size.y / _content_rect.size.y)
	graph.scale = Vector2(fit, fit)
	graph.position = size * 0.5 - _content_rect.get_center() * fit


## Restore the authored board. Casts deliberately do NOT auto-reset: damage (and
## ownership) accumulate across casts, so a node no single spell can kill still
## dies to three of them — which is most of what this harness is for.
func _reset_state() -> void:
	if _casting:
		return
	_arm_board()
	_refresh_status()


func _on_spell_damage_changed(value: float) -> void:
	spell_damage_label.text = "Spell DMG: %.1f" % value
	if caster_entity != null and caster_entity.stat_board != null \
			and caster_entity.stat_board.spell_damage != null:
		caster_entity.stat_board.spell_damage.base_value = value


## Gate Cast + Reset for the duration of a launch — its mutation loop walks the
## beat clock across several frames, and both buttons would otherwise interleave
## with hits still in the air.
func _set_casting(value: bool) -> void:
	_casting = value
	reset_button.disabled = value
	_refresh_status()


## Arm the plan the way the click grammar does — cast-from node first, then the
## target — and launch it. Going through [MagicAttackPlan] rather than straight
## to [SpellResolver] is what buys the whole production path: affordability, the
## seeded crit stream, the record round trip, the beat clock and the coordinator.
##
## It also means a seed can be REFUSED (a friendly node, a source whose owned
## degree is under the spell's `min_degree`). That is not a regression from the
## old gate-free panel — a refusal a spell author would hit in game is worth
## seeing here, so it is reported rather than swallowed.
func _cast() -> void:
	if _casting or _battle == null:
		return
	if not is_instance_valid(_spell) or _selected_target == null:
		return
	# The harness must never run dry: a spell costs mana and AP, and there is no
	# turn loop here to give either back.
	_replenish_caster()
	_battle.selected_spell = _spell
	if _battle.attack_mode != BattleSystem.AttackMode.MAGIC:
		_battle.request_attack_mode(BattleSystem.AttackMode.MAGIC)
	var plan := _battle.attack_plan as MagicAttackPlan
	if plan == null:
		push_warning("Spell Playground: no magic plan to arm")
		return
	plan.reset()
	plan._on_node_left_clicked(caster_node)
	plan._on_node_left_clicked(_selected_target)
	var errors := plan.validate()
	if not errors.is_empty():
		status_label.text = "%s · %s → refused: %s" \
				% [_spell.name, _selected_target.name, ", ".join(errors)]
		return
	_set_casting(true)
	@warning_ignore("redundant_await")
	await _battle.launch_attack()
	# The panel can be torn down mid-launch (plugin disabled, tab rebuilt); its
	# buttons are gone by then and re-enabling them would crash.
	if not is_inside_tree():
		return
	# `launch_attack` is `-> void` and its two remaining refusals — the plan going
	# invalid in the queue, and the affordability gate reading the REAL board —
	# only `push_warning`. Left alone, `_set_casting(false)` below rewrites the
	# status line with the ordinary "spell · seed →" text, and a refused cast
	# becomes byte-identical to a cast that legitimately changed nothing (a heal
	# on a full node). That is the exact shape of silence this panel just spent a
	# release in. [method BattleSystem._commit] clears the plan on its way out, so
	# a plan still armed here means nothing launched.
	var launched := not _battle.is_attacking
	_set_casting(false)
	if not launched:
		status_label.text = "%s · %s → refused: unaffordable, or the plan went invalid" \
				% [_spell.name, _selected_target.name]


func _replenish_caster() -> void:
	var board: EntityStatBoard = caster_entity.stat_board
	if board == null:
		return
	if board.action_points != null:
		board.action_points.restore_to_full()
	if board.mana != null:
		board.mana.restore_to_full()
