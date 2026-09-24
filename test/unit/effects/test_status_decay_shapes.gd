extends GutTest

## The decay SHAPE per authored status family (#1091, hub #1060) — a law over
## `effects/status/*.tres`, pinning FLAT vs FRACTION, never the magnitude
## (`decay_per_tick` is the owner's knob). Why each family has its shape:
## docs/design/damage_over_time.md, "The stat vocabulary and the decay shapes".

const _DIR := "res://effects/status/"

const _SHAPES := {
	&"poison": StatusDef.DecayMode.FRACTION,
	&"corruption": StatusDef.DecayMode.FRACTION,
	&"wither": StatusDef.DecayMode.FRACTION,
	&"blindness": StatusDef.DecayMode.FRACTION,
	&"curse": StatusDef.DecayMode.FLAT,
	&"armor_break": StatusDef.DecayMode.FLAT,
}


func _authored() -> Dictionary:
	var out := {}
	for f in ResourceLoader.list_directory(_DIR):
		if not f.ends_with(".tres"):
			continue
		var def := load(_DIR + f) as StatusDef
		if def != null:
			out[def.id] = def
	return out


func test_every_family_is_authored() -> void:
	var defs := _authored()
	for id in _SHAPES:
		assert_true(defs.has(id), "%s.tres is authored under %s" % [id, _DIR])


func test_each_family_decays_in_its_shape() -> void:
	var defs := _authored()
	for id in _SHAPES:
		if not defs.has(id):
			continue
		var def: StatusDef = defs[id]
		assert_eq(def.decay_mode, _SHAPES[id], "%s decays %s" % [id,
			StatusDef.DecayMode.keys()[_SHAPES[id]]])
		assert_gt(def.decay_per_tick, 0.0, "%s actually decays" % id)
		if def.decay_mode == StatusDef.DecayMode.FRACTION:
			assert_lt(def.decay_per_tick, 1.0, "%s: a fraction below 1 leaves a tail" % id)
