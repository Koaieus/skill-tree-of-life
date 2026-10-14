class_name BlastVFX
extends Node2D

## The board blast ring, level-wide: on [signal Events.blast_landed] it plays
## one [member visual_scene] at the mark's centre node, sized to the mark, and
## frees it when done. Bus-driven like the pop burst — the cue arrives on the
## mutation clock from [OutcomeApplier], on the authority and peers alike.

## The one-shot per blast.
@export var visual_scene: PackedScene = preload("res://ui/vfx/blast_visual.tscn")
## Silences the ring (a headless harness, a cinematic).
@export var muted: bool = false


func _ready() -> void:
	if not Events.blast_landed.is_connected(_on_blast_landed):
		Events.blast_landed.connect(_on_blast_landed)


func _on_blast_landed(mark: BlastMark) -> void:
	if muted or mark == null or not is_instance_valid(mark.centre) or visual_scene == null:
		return
	var visual := visual_scene.instantiate() as BlastVisual
	if visual == null:
		return
	add_child(visual)
	visual.global_position = mark.centre.global_position
	visual.setup(mark)
	visual.finished.connect(visual.queue_free)
	visual.play()
