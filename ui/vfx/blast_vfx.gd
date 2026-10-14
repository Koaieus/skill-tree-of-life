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


func _ready() -> void:
	if not Events.blast_landed.is_connected(_on_blast_landed):
		Events.blast_landed.connect(_on_blast_landed)


func _on_blast_landed(mark: BlastMark) -> void:
	if muted:
		return
	spawn(mark)


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
