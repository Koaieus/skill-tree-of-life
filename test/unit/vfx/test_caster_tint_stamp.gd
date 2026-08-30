extends GutTest

## #663 D4 — a spell body renders in the CASTER's identity colour, and the
## coordinator is what stamps it.
##
## This was absent on the magic path until #671/#672 authored the first spell
## bodies that actually read `tint`: `ArrowVolleyCoordinator` had stamped since
## #507, `MagicBounceCoordinator` never did, and
## `docs/domain/spell-vfx-kit.md` described the stamp as though it were already
## there. Every spell therefore rendered neutral-white. The gap survived because
## nothing asserted the colour ARRIVES — only that the visual spawned.
##
## Two halves, and both have to hold or the tint is silently dropped:
##   1. the coordinator resolves the caster and stamps the projectile's visual;
##   2. `ComposedProjectileVisual` forwards that stamp DOWN to its body — it
##      sits between the projectile and the body, so a stamp that stops at the
##      wrapper is invisible in exactly the composed case every spell uses.

const _COMPOSED := preload("res://ui/vfx/projectile/visual/composed_projectile_visual.gd")
const _BOLT_SMALL := preload("res://ui/vfx/projectile/visual/bolt_small.tscn")


func test_wrapper_forwards_tint_down_to_its_body() -> void:
	var w: ComposedProjectileVisual = _COMPOSED.new()
	w.body_scene = _BOLT_SMALL
	add_child_autofree(w)

	var caster := Color(0.2, 0.8, 0.4, 1.0)
	w.tint = caster

	var body: Node = w.get_child(0)
	assert_true("tint" in body, "the composed body exposes a tint field to stamp")
	assert_eq(body.get("tint"), caster,
			"the caster colour reaches the BODY, not just the wrapper — a stamp "
			+ "that stops at the wrapper renders neutral-white (#663 D4)")


## The stamp can legally arrive before `_ready` has built the body (an authored
## value on the scene, or a coordinator that beats instantiation). The setter
## must not drop it on the floor in that ordering.
func test_tint_set_before_body_exists_is_applied_on_ready() -> void:
	var w: ComposedProjectileVisual = _COMPOSED.new()
	w.body_scene = _BOLT_SMALL
	var caster := Color(0.9, 0.1, 0.1, 1.0)
	w.tint = caster          # before _ready: there is no body yet
	add_child_autofree(w)    # _ready builds it

	assert_eq(w.get_child(0).get("tint"), caster,
			"a tint stamped before the body existed is still applied once it does")


## Identity is the flying body's; the ImpactRing is crit-grammar punctuation
## and owns its own tier colour. Tinting the ring with the caster colour would
## make "where it fired" read as identity rather than as placement (#663 D3).
func test_tint_is_not_forwarded_to_arrival_companions() -> void:
	var w: ComposedProjectileVisual = _COMPOSED.new()
	w.body_scene = _BOLT_SMALL
	w.arrival_companions = [preload("res://ui/vfx/projectile/visual/impact_ring.tscn")]
	add_child_autofree(w)
	w.tint = Color(0.2, 0.8, 0.4, 1.0)

	w._on_arrival()

	for child in w.get_children():
		if child == w.get_child(0):
			continue
		if "tint" in child:
			assert_ne(child.get("tint"), Color(0.2, 0.8, 0.4, 1.0),
					"the crit-grammar ring keeps its own colour, not the caster's")
