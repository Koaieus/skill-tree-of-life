extends GutTest

## An [IdentityBadge] frames its identity in the kind's polygon and draws the
## icon or the noun's letter inside; [method IdentityBadge.composite] bakes the
## same silhouette in white, once per (id, size). Fixtures are built inline —
## the identity roster is not this unit's data.

const _BADGE_SCENE := preload("res://ui/identity_badge/identity_badge.tscn")
const _FRAMES: BadgeFrames = preload("res://ui/identity_badge/badge_frames.tres")

## Opaque/transparent thresholds: the stroke is anti-aliased, never exact 0/1.
const _OPAQUE := 0.5
const _CLEAR := 0.1


func before_each() -> void:
	IdentityBadge.clear_cache()


## An icon-less ASPECT whose capital covers the centre ("T"-ish noun).
func _identity(id: StringName, kind: Identity.Kind, noun := "Toxin", icon: Texture2D = null) -> Identity:
	var identity := Identity.new()
	identity.id = id
	identity.noun = noun
	identity.kind = kind
	identity.tint = Color(0.45, 0.85, 0.3)
	identity.icon = icon
	return identity


func _white_icon() -> Texture2D:
	var image := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)


func _alpha(image: Image, at: Vector2) -> float:
	var px := Vector2i(clampi(int(at.x), 0, image.get_width() - 1), clampi(int(at.y), 0, image.get_height() - 1))
	return image.get_pixelv(px).a


## Circumradius the composite strokes at, mirroring its own geometry.
func _radius(size_px: int) -> float:
	return size_px * 0.5 - _FRAMES.stroke_px * 0.5


func test_composite_is_a_cached_square_texture_of_the_requested_size() -> void:
	var poison := _identity(&"test_poison", Identity.Kind.ASPECT)
	var texture := IdentityBadge.composite(poison, 24)
	assert_not_null(texture, "composite returns a texture")
	if texture == null:
		return
	assert_eq(texture.get_size(), Vector2(24, 24), "24 px request → 24×24")
	assert_same(IdentityBadge.composite(poison, 24), texture, "the second call is the cached object")
	assert_ne(IdentityBadge.composite(poison, 48), texture, "another size is another entry")


func test_composite_of_a_hexagon_is_opaque_at_its_vertices_and_clear_outside() -> void:
	var poison := _identity(&"test_poison", Identity.Kind.ASPECT)
	var texture := IdentityBadge.composite(poison, 24)
	if texture == null:
		fail_test("no composite")
		return
	var image := texture.get_image()
	var center := Vector2(12, 12)
	var frame := _FRAMES.frame_for(Identity.Kind.ASPECT)
	assert_eq(frame.sides, 6, "ASPECT is a hexagon")
	for vertex in frame.vertices(center, _radius(24)):
		assert_gt(_alpha(image, vertex), _OPAQUE, "hexagon vertex %s is opaque" % vertex)
	assert_gt(_alpha(image, center), _OPAQUE, "the letter covers the centre of an icon-less identity")
	# Flat top: straight above the centre, the hexagon ends at its apothem.
	assert_lt(_alpha(image, Vector2(12, 0)), _CLEAR, "a pixel just outside the flat top is transparent")
	assert_lt(_alpha(image, Vector2(0, 0)), _CLEAR, "the corner is transparent")


func test_composite_is_a_white_silhouette() -> void:
	var texture := IdentityBadge.composite(_identity(&"test_white", Identity.Kind.ASPECT), 24)
	if texture == null:
		fail_test("no composite")
		return
	var px := texture.get_image().get_pixel(12, 12)
	assert_almost_eq(Vector3(px.r, px.g, px.b), Vector3.ONE, Vector3.ONE * 0.01, "the hue is the caller's, not baked in")


func test_an_icon_fills_the_inset_box() -> void:
	var texture := IdentityBadge.composite(_identity(&"test_icon", Identity.Kind.ASPECT, "Toxin", _white_icon()), 48)
	if texture == null:
		fail_test("no composite")
		return
	var image := texture.get_image()
	var inset := 48 * _FRAMES.icon_inset
	assert_gt(_alpha(image, Vector2(inset + 1, inset + 1)), _OPAQUE, "the icon reaches the inset box corner")
	assert_gt(_alpha(image, Vector2(24, 24)), _OPAQUE, "the icon covers the centre")


func test_each_kind_composites_its_own_polygon() -> void:
	var size_px := 64
	var center := Vector2(size_px, size_px) * 0.5
	var radius := _radius(size_px)
	for kind: Identity.Kind in Identity.Kind.values():
		var name: String = Identity.Kind.keys()[kind]
		var texture := IdentityBadge.composite(_identity(StringName("test_kind_%s" % name), kind), size_px)
		if texture == null:
			fail_test("no composite for %s" % name)
			continue
		var image := texture.get_image()
		var frame := _FRAMES.frame_for(kind)
		var vertices := frame.vertices(center, radius)
		assert_eq(vertices.size(), frame.sides, "%s has its kind's vertex count" % name)
		for vertex in vertices:
			assert_gt(_alpha(image, vertex), _OPAQUE, "%s vertex %s is on the stroke" % [name, vertex])
		if frame.sides <= 6:
			var mid_angle := (vertices[0] - center).angle() + PI / frame.sides
			var between := center + Vector2.from_angle(mid_angle) * radius
			assert_lt(_alpha(image, between), _CLEAR, "%s is clear midway between vertices at the circumradius" % name)


func test_a_badge_without_an_identity_draws_nothing() -> void:
	var badge: IdentityBadge = _BADGE_SCENE.instantiate()
	add_child_autofree(badge)
	await get_tree().process_frame
	assert_eq(badge.last_draw_color, Color.TRANSPARENT, "nothing was drawn")
	assert_eq(badge.get_minimum_size(), Vector2(24, 24), "the badge still reserves its size")


func test_setting_an_identity_redraws_in_its_tier_lifted_tint() -> void:
	var badge: IdentityBadge = _BADGE_SCENE.instantiate()
	add_child_autofree(badge)
	await get_tree().process_frame
	var poison := _identity(&"test_poison", Identity.Kind.ASPECT)
	badge.emissive_tier = Emissive.Tier.VALUE
	badge.identity = poison
	await get_tree().process_frame
	assert_eq(badge.last_draw_color, Emissive.at(poison.tint, Emissive.VALUE), "drawn in Emissive.at(tint, tier)")
	badge.emissive_tier = Emissive.Tier.ALERT
	await get_tree().process_frame
	assert_eq(badge.last_draw_color, Emissive.at(poison.tint, Emissive.ALERT), "a tier change redraws")
