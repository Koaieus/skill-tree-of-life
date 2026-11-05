@tool
class_name NodeFeedback
extends Node
## A SkillNode's transient view feedback: the hit flash and the two denial
## registers (#89). A rejected deallocation pulses the nodes it would island
## danger-red ([method blink_blocked]) and gives the node the player tried to
## drop a short "bzzt — no" shake ([method shake_denied]).
##
## The red tint lands on [member node_visuals]
## ([member NodeVisualsComposite.feedback_tint]), NOT on [member visuals]: the
## hover glow is a child of `visuals`, so a `visuals.modulate` tint multiplies
## the glow down to near-black. The shake offsets `visuals.position` (edges
## anchor on the node root, so endpoints don't move); the hover glow is
## counter-translated to stay world-fixed, and addons — siblings of `visuals`,
## not children — are shaken alongside it.
##
## Every trigger kills and resets what is running, so spamming one never
## stacks shakes or leaves a stuck offset or tint. The host's forwarders own
## the `is_node_ready()` guard; this node assumes its refs are wired.

## Also the hit-flash colour — one shared value for every register, since all
## drive [member NodeVisualsComposite.feedback_tint].
const DENY_COLOR := Color(1.0, 0.3, 0.3)
const BLINK_STEP := 0.11
const SHAKE_TIME := 0.30
const SHAKE_AMPLITUDE := 5.0
const HIT_FLASH_TIME := 0.25

## The SkillNode; read for its live addon list ([method SkillNode.get_addons]).
## Typed `Node`: SkillNode preloads its children rather than naming classes.
@export var host: Node
## Shaken body root.
@export var visuals: Node2D
## Counter-translated during a shake so the pointer register holds still.
@export var hover_ring: Node2D
## The NodeVisualsComposite whose `feedback_tint` every register tweens.
@export var node_visuals: Node2D

# Killed and re-created on every hit so back-to-back damage doesn't visually
# merge into one stuck red.
var _hit_flash_tween: Tween
var _feedback_tweens: Array[Tween] = []


## Brief red pulse on the body.
func play_hit_flash() -> void:
	if node_visuals == null:
		return
	if _hit_flash_tween != null:
		_hit_flash_tween.kill()
	node_visuals.feedback_tint = DENY_COLOR
	_hit_flash_tween = create_tween()
	_hit_flash_tween.tween_property(node_visuals, "feedback_tint", Color.WHITE, HIT_FLASH_TIME)


## Danger-red pulse — marks a node that a denied deallocation would island.
func blink_blocked() -> void:
	if node_visuals == null:
		return
	reset()
	var t := create_tween()
	for i in 2:
		t.tween_property(node_visuals, "feedback_tint", DENY_COLOR, BLINK_STEP)
		t.tween_property(node_visuals, "feedback_tint", Color.WHITE, BLINK_STEP)
	_feedback_tweens.append(t)


## Short shake + red tint — the node the player tried but failed to
## deallocate. Horizontal decaying jitter on the body; hover glow held put.
func shake_denied() -> void:
	if visuals == null:
		return
	reset()
	if node_visuals != null:
		node_visuals.feedback_tint = DENY_COLOR
		var tint := create_tween()
		tint.tween_property(node_visuals, "feedback_tint", Color.WHITE, SHAKE_TIME)
		_feedback_tweens.append(tint)
	var addons := _addons()
	var shake := create_tween()
	var amps := [1.0, -0.72, 0.5, -0.32, 0.16, 0.0]
	var step := SHAKE_TIME / float(amps.size())
	for a in amps:
		var off := Vector2(a * SHAKE_AMPLITUDE, 0.0)
		shake.tween_property(visuals, "position", off, step).set_trans(Tween.TRANS_SINE)
		if hover_ring != null:
			shake.parallel().tween_property(hover_ring, "position", -off, step).set_trans(Tween.TRANS_SINE)
		for addon in addons:
			shake.parallel().tween_property(addon, "position", off, step).set_trans(Tween.TRANS_SINE)
	_feedback_tweens.append(shake)


## Kills the denial tweens and puts offsets and tint back to rest.
func reset() -> void:
	for t in _feedback_tweens:
		if t != null and t.is_valid():
			t.kill()
	_feedback_tweens.clear()
	if visuals != null:
		visuals.position = Vector2.ZERO
	if hover_ring != null:
		hover_ring.position = Vector2.ZERO
	for addon in _addons():
		addon.position = Vector2.ZERO
	if node_visuals != null:
		node_visuals.feedback_tint = Color.WHITE


func _addons() -> Array:
	if host == null:
		return []
	return host.get_addons()
