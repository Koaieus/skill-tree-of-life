extends GutTest

## #153: the "preview" band (current -> current + preview_gain, clamped at
## max_value) is a new shader-driven overlay on PoolGauge, mirroring the
## existing drain_from ghost trail but rendered above `current`. Assert
## against shader parameters — that's the gauge's real observable contract,
## same convention as test_overlay_uniform_caps.gd.

const _GAUGE_SCENE := preload("res://ui/gauges/pool_gauge.tscn")
const _CARD_SCENE := preload("res://ui/hud/hero_sigil_card/hero_sigil_card.tscn")


func test_default_preview_gain_is_zero() -> void:
	var gauge: PoolGauge = _GAUGE_SCENE.instantiate()
	add_child(gauge)
	autofree(gauge)
	await get_tree().process_frame
	var mat := gauge.material as ShaderMaterial
	assert_eq(mat.get_shader_parameter(&"preview_gain"), 0.0,
		"resting state: no preview band, existing gauges unaffected")


func test_setting_preview_gain_pushes_to_the_shader() -> void:
	var gauge: PoolGauge = _GAUGE_SCENE.instantiate()
	add_child(gauge)
	autofree(gauge)
	await get_tree().process_frame
	gauge.preview_gain = 2.0
	var mat := gauge.material as ShaderMaterial
	assert_eq(mat.get_shader_parameter(&"preview_gain"), 2.0)


func test_push_all_carries_preview_uniforms_through() -> void:
	# A property added to the setters but forgotten in _push_all() is the
	# classic bug here: it only manifests when a fresh _ready() re-pushes.
	var gauge: PoolGauge = _GAUGE_SCENE.instantiate()
	gauge.preview_gain = 3.0
	gauge.preview_color = Color(0.2, 0.4, 0.6, 0.3)
	add_child(gauge)
	autofree(gauge)
	await get_tree().process_frame
	gauge._push_all()
	var mat := gauge.material as ShaderMaterial
	assert_eq(mat.get_shader_parameter(&"preview_gain"), 3.0)
	assert_eq(mat.get_shader_parameter(&"preview_color"), Color(0.2, 0.4, 0.6, 0.3))


func test_bind_pool_sets_preview_gain_from_per_turn_stat() -> void:
	var card: HeroSigilCard = _CARD_SCENE.instantiate()
	add_child(card)
	autofree(card)
	await get_tree().process_frame

	var pool := PoolStat.new()
	pool.base_value = 5.0
	pool.set_current(3.0)
	var per_turn := ScalarStat.new()
	per_turn.base_value = 5.0

	card._bind_pool(card._mana_gauge, card._mana_caption, pool, per_turn)
	await get_tree().process_frame

	assert_eq(card._mana_gauge.preview_gain, 5.0,
		"_bind_pool must drive gauge.preview_gain from per_turn.value")
	var mat := card._mana_gauge.material as ShaderMaterial
	assert_eq(mat.get_shader_parameter(&"preview_gain"), 5.0)


func test_bind_pool_preview_gain_tracks_per_turn_value_changed() -> void:
	var card: HeroSigilCard = _CARD_SCENE.instantiate()
	add_child(card)
	autofree(card)
	await get_tree().process_frame

	var pool := PoolStat.new()
	pool.base_value = 5.0
	pool.set_current(3.0)
	var per_turn := ScalarStat.new()
	per_turn.base_value = 1.0

	card._bind_pool(card._health_gauge, card._health_caption, pool, per_turn)
	await get_tree().process_frame
	assert_eq(card._health_gauge.preview_gain, 1.0)

	per_turn.base_value = 4.0
	await get_tree().process_frame
	assert_eq(card._health_gauge.preview_gain, 4.0,
		"per_turn.value_changed must re-drive gauge.preview_gain")


func test_bind_pool_leaves_preview_gain_zero_when_per_turn_is_null() -> void:
	# Health has no per-turn stat wired (#153 NOTES); _bind_pool(..., null)
	# must leave the gauge in its resting no-band state.
	var card: HeroSigilCard = _CARD_SCENE.instantiate()
	add_child(card)
	autofree(card)
	await get_tree().process_frame

	var pool := PoolStat.new()
	pool.base_value = 10.0
	pool.set_current(10.0)

	card._bind_pool(card._health_gauge, card._health_caption, pool, null)
	await get_tree().process_frame

	assert_eq(card._health_gauge.preview_gain, 0.0)
