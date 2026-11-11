class_name BlastVFX
extends Node2D

## The board blast ring, level-wide: on [signal Events.blast_landed] it plays
## one [member visual_scene] at the mark's centre node, sized to the mark, and
## frees it when done. Bus-driven like the pop burst — the cue arrives on the
## mutation clock from [OutcomeApplier], on the authority and peers alike.

## The one-shot per blast.
@export var visual_scene: PackedScene = preload("res://ui/vfx/blast_visual.tscn")
## The layer a rider gets when its aspect authors none ([member Aspect.blast_layer]).
@export var rider_layer_scene: PackedScene = preload("res://ui/vfx/rider_blast_layer.tscn")
## Where a rider identity finds its aspect's bespoke layer; null = the shared roster.
@export var roster: AspectRoster = null
## Silences the ring (a headless harness, a cinematic).
@export var muted: bool = false
## Seconds between a cascade's generations (tentative, #1799): a disc whose
## go-off fired at generation g ([member BlastMark.generation]; ADR 0091 §1)
## plays g × this after its cue, so a chained node's disc fires visibly after
## its parent's. Read off the mark, so an observer replay staggers the same.
@export_range(0.0, 1.0, 0.01, "or_greater", "suffix:s") var generation_stagger: float = 0.12


func _ready() -> void:
	if not Events.blast_landed.is_connected(_on_blast_landed):
		Events.blast_landed.connect(_on_blast_landed)


func _on_blast_landed(mark: BlastMark) -> void:
	if muted:
		return
	var delay := delay_for(mark)
	if delay <= 0.0 or not is_inside_tree():
		spawn(mark)
		return
	get_tree().create_timer(delay, false).timeout.connect(spawn.bind(mark))


## How long after its cue [param mark]'s ring waits: its generation ×
## [member generation_stagger]; 0 at generation 0.
func delay_for(mark: BlastMark) -> float:
	return maxf(0.0, (mark.generation if mark != null else 0) * generation_stagger)


## Play one ring for [param mark] with its rider layers; null when there is
## nothing to centre it on.
func spawn(mark: BlastMark) -> BlastVisual:
	if mark == null or not is_instance_valid(mark.centre) or visual_scene == null:
		return null
	var visual := visual_scene.instantiate() as BlastVisual
	if visual == null:
		return null
	add_child(visual)
	visual.global_position = mark.centre.global_position
	visual.setup(mark)
	visual.companions = layers_for(mark.riders,
			roster if roster != null else AspectRoster.shared(), rider_layer_scene)
	visual.finished.connect(visual.queue_free)
	visual.play()
	return visual


## One layer scene per rider, in order: its aspect's authored
## [member Aspect.blast_layer], else [param generic] (a bare status, or an
## aspect with none).
static func layers_for(riders: Array[Identity], roster: AspectRoster, generic: PackedScene) -> Array[PackedScene]:
	var out: Array[PackedScene] = []
	for identity in riders:
		var aspect := roster.by_id(identity.id) if roster != null and identity != null else null
		var bespoke := aspect.blast_layer if aspect != null else null
		out.append(bespoke if bespoke != null else generic)
	return out
