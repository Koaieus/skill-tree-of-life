extends GutTest

## The decay SHAPE per authored status family (#1091, hub #1060) — a law over
## `effects/status/*.tres`, pinning the [member StatusDef.decay] member —
## [FlatDecay] vs [FractionDecay] — never the magnitude (its knob is the
## owner's). Why each family has its shape:
## docs/domain/effect-system.md, "Status effects — the DoT model".

const _DIR := "res://effects/status/"

const _SHAPES := {
	&"poison": FractionDecay,
	&"corruption": FractionDecay,
	&"wither": FractionDecay,
	&"blindness": FractionDecay,
	&"curse": FlatDecay,
	&"armor_break": FlatDecay,
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
		assert_true(is_instance_of(def.decay, _SHAPES[id]), "%s decays %s" % [id,
			_SHAPES[id].get_global_name()])
		var rate: float = (def.decay as FractionDecay).fraction if def.decay is FractionDecay \
			else (def.decay as FlatDecay).per_tick if def.decay is FlatDecay else 0.0
		assert_gt(rate, 0.0, "%s actually decays" % id)
		if def.decay is FractionDecay:
			assert_lt(rate, 1.0, "%s: a fraction below 1 leaves a tail" % id)
