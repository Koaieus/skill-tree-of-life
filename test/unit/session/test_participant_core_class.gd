extends GutTest

## #618 — a lobby slot picks a [CoreClass], the sigil rides along on it, and
## the core itself declares which slots may pick it.
##
## Three seams, all reachable without booting a level: the wire form
## ([method Participant.to_dict]), the pickability mask
## ([method CoreClass.pickable_for]) and the spawn-site resolution
## ([method ProcgenPlaySandbox.resolve_spawn_core]). Same reasoning as
## `test/unit/test_procgen_spawn_colors.gd` for not booting the real level: the
## spawn loop consults exactly one function for the class, on all three of its
## arms, and a full [GraphProcgen] run would re-derive the same three-line
## answer in seconds instead of milliseconds.

const _SANDBOX := preload("res://scenes/procgen_play_sandbox.gd")
const _BALANCED := preload("res://entity/core/balanced_core.tres")
const _BASIC_ENEMY := preload("res://entity/core/basic_enemy_core.tres")
const _NINJA := preload("res://entity/core/ninja_core.tres")
const _PACIFIST := preload("res://entity/core/pacifist_core.tres")
const _SERPENT := preload("res://entity/core/serpent_core.tres")
const _CAMP_1 := preload("res://entity/factions/camp_1.tres")
const _NPC := preload("res://entity/factions/npc.tres")


func _participant(id: int, kind: Participant.Kind, core: CoreClass) -> Participant:
	var p := Participant.new()
	p.id = id
	p.kind = kind
	p.camp = _NPC if kind == Participant.Kind.AI else _CAMP_1
	p.core_class = core
	return p


func _resolve(p: Participant) -> CoreClass:
	return _SANDBOX.resolve_spawn_core(p, _BALANCED, _BASIC_ENEMY)


# --- Acceptance 1: the pick crosses the wire -------------------------------

func test_a_core_class_survives_the_roster_round_trip() -> void:
	var p := _participant(1, Participant.Kind.HUMAN, _NINJA)
	var wire := p.to_dict()

	assert_true(wire["core_class"] is String,
			"#618 D2: a resource PATH crosses, never a resource reference")

	var back := Participant.from_dict(wire)
	assert_eq(back.core_class, _NINJA, "and each peer loads its own instance back")
	assert_eq(back.core_class.sigil, _NINJA.sigil,
			"D1: the sigil rides along on the class, it is not a second field")


func test_a_participant_without_a_core_round_trips_as_null() -> void:
	var p := _participant(1, Participant.Kind.HUMAN, null)
	assert_eq(p.to_dict()["core_class"], "")
	assert_null(Participant.from_dict(p.to_dict()).core_class)


# --- Acceptance 2: the spawn site reads the roster -------------------------

func test_two_slots_with_different_cores_spawn_on_their_own_pick() -> void:
	var ninja := _participant(1, Participant.Kind.HUMAN, _NINJA)
	var serpent := _participant(2, Participant.Kind.HUMAN, _SERPENT)

	assert_eq(_resolve(ninja), _NINJA)
	assert_eq(_resolve(serpent), _SERPENT)
	assert_ne(_resolve(ninja), _resolve(serpent))
	assert_ne(_resolve(ninja), _BALANCED,
			"#618 D3: the level default must not win over the roster")


func test_an_ai_slot_pick_beats_the_enemy_core_export_too() -> void:
	# D5: "the enemies would receive default enemy core by default but should
	# also be pickable" (owner, 2026-08-26) — one mechanism, two defaults.
	assert_eq(_resolve(_participant(3, Participant.Kind.AI, _SERPENT)), _SERPENT)


# --- Acceptance 5: the two defaults, when nobody picked --------------------

func test_a_core_less_roster_falls_back_to_the_levels_two_exports() -> void:
	assert_eq(_resolve(_participant(1, Participant.Kind.HUMAN, null)), _BALANCED)
	assert_eq(_resolve(_participant(2, Participant.Kind.AI, null)), _BASIC_ENEMY)


func test_the_lobby_seats_every_slot_on_a_default_core() -> void:
	var parts := LobbyScreen.build_participants(RunConfig.Mode.COOP_HOTSEAT, null, 2)
	for p in parts:
		assert_not_null(p.core_class, "%s must reach the level with a class" % p.display_name)
		if p.kind == Participant.Kind.AI:
			assert_eq(p.core_class, _BASIC_ENEMY)
		else:
			assert_eq(p.core_class, _BALANCED)


## A default the picker will not list is a state the player could never get back
## to — so both defaults must themselves pass their own slot's mask.
func test_both_lobby_defaults_are_pickable_in_their_own_slot_kind() -> void:
	assert_true(_BALANCED.is_pickable_in(CoreClass.PICKABLE_PLAYER))
	assert_true(_BASIC_ENEMY.is_pickable_in(CoreClass.PICKABLE_AI))


# --- Acceptance 4: the pickability mask (D6) -------------------------------

func test_pickable_in_defaults_to_neither_on_an_unauthored_core() -> void:
	# The deliberate default: a core added for a boss, a test or an unfinished
	# experiment must not leak into a lobby picker by merely existing.
	var fresh := CoreClass.new()
	assert_eq(fresh.pickable_in, 0)
	assert_false(fresh.is_pickable_in(CoreClass.PICKABLE_PLAYER))
	assert_false(fresh.is_pickable_in(CoreClass.PICKABLE_AI))
	assert_false(CoreClass.pickable_for(CoreClass.PICKABLE_PLAYER).has(fresh),
			"and it is in no slot's dropdown")


func test_a_player_only_core_appears_only_in_human_slots() -> void:
	# balanced_core is authored player-side (owner call, 2026-08-26).
	assert_true(CoreClass.pickable_for(CoreClass.PICKABLE_PLAYER).has(_BALANCED))
	assert_false(CoreClass.pickable_for(CoreClass.PICKABLE_AI).has(_BALANCED))


func test_an_ai_only_core_appears_only_in_ai_slots() -> void:
	assert_true(CoreClass.pickable_for(CoreClass.PICKABLE_AI).has(_BASIC_ENEMY))
	assert_false(CoreClass.pickable_for(CoreClass.PICKABLE_PLAYER).has(_BASIC_ENEMY))


func test_the_three_shared_cores_appear_on_both_sides() -> void:
	var for_player := CoreClass.pickable_for(CoreClass.PICKABLE_PLAYER)
	var for_ai := CoreClass.pickable_for(CoreClass.PICKABLE_AI)
	for core in [_NINJA, _PACIFIST, _SERPENT]:
		assert_true(for_player.has(core), "%s is pickable player-side" % core.display_name)
		assert_true(for_ai.has(core), "%s is pickable AI-side" % core.display_name)


func test_the_lobby_maps_a_slot_kind_to_the_matching_mask_bit() -> void:
	assert_eq(LobbyScreen.slot_bit_for(Participant.Kind.HUMAN), CoreClass.PICKABLE_PLAYER)
	assert_eq(LobbyScreen.slot_bit_for(Participant.Kind.AI), CoreClass.PICKABLE_AI)
