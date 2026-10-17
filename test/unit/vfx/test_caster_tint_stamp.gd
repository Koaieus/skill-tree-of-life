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
##   2. `ComposedProjectileVisual` forwards that stamp DOWN to its body and its
##      arrival companions — it sits between the projectile and them, so a
##      stamp that stops at the wrapper is invisible in exactly the composed
##      case every spell uses.

const _COMPOSED := preload("res://ui/vfx/projectile/visual/composed_projectile_visual.gd")
const _BOLT_SMALL := preload("res://ui/vfx/projectile/visual/bolt_small.tscn")
const _BOLT_SOFT := preload("res://ui/vfx/projectile/visual/bolt_soft.tscn")
const _IMPACT_RING := preload("res://ui/vfx/projectile/visual/impact_ring.tscn")


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


## Identity rides the arrival companions too: every companion exposing a `tint`
## field carries the caster colour, so each spell's rings read in caster colour
## under their own tier ladder (a crit's `crit_color` still takes over there).
## A stamp that lands AFTER arrival must reach the already-spawned companions.
func test_tint_is_forwarded_to_arrival_companions() -> void:
    var w: ComposedProjectileVisual = _COMPOSED.new()
    w.body_scene = _BOLT_SMALL
    w.arrival_companions = [_IMPACT_RING, _IMPACT_RING]
    add_child_autofree(w)
    var caster := Color(0.2, 0.8, 0.4, 1.0)
    w.tint = caster

    w._on_arrival()

    var companions := _companions(w)
    assert_eq(companions.size(), 2, "both arrival companions spawned and expose tint")
    for c in companions:
        assert_eq(c.get("tint"), caster, "a companion carries the caster colour stamped before arrival")

    var later := Color(0.9, 0.3, 0.1, 1.0)
    w.tint = later
    for c in companions:
        assert_eq(c.get("tint"), later, "a stamp landing after arrival reaches the live companions")


## `tint_strength` moves the BODY's colour from its authored colour toward
## `tint`, keeping the body's authored alpha. Swept, never one magic number.
func test_tint_strength_lerps_body_rgb_and_keeps_authored_alpha() -> void:
    var caster := Color(0.2, 0.7, 0.3, 1.0)
    for s in [0.0, 0.5, 1.0]:
        var w: ComposedProjectileVisual = _COMPOSED.new()
        w.body_scene = _BOLT_SOFT
        w.set("tint_strength", s)
        add_child_autofree(w)
        var authored: Color = autofree(_BOLT_SOFT.instantiate()).get("tint")
        w.tint = caster

        var body_tint: Color = w.get_child(0).get("tint")
        var want := authored.lerp(caster, s)
        assert_almost_eq(body_tint.r, want.r, 0.001, "red lerped at s=%s" % s)
        assert_almost_eq(body_tint.g, want.g, 0.001, "green lerped at s=%s" % s)
        assert_almost_eq(body_tint.b, want.b, 0.001, "blue lerped at s=%s" % s)
        assert_almost_eq(body_tint.a, authored.a, 0.001,
                "the body's authored alpha is kept at s=%s, never the stamp's" % s)


func _companions(w: Node) -> Array:
    var out := []
    for child in w.get_children():
        if child != w.get_child(0) and "tint" in child:
            out.append(child)
    return out
