class_name BlastVFX
extends Node2D

## The board blast ring, level-wide: on [signal Events.blast_landed] it plays
## one [member visual_scene] at the mark's centre node, sized to the mark, and
## frees it when done. Bus-driven like the pop burst — the cue arrives on the
## mutation clock from [OutcomeApplier], on the authority and peers alike.

## The disc fill default, shared with the sandbox blast tab.
const DEFAULT_DISC_FILL := 0.22

## The one-shot per blast.
@export var visual_scene: PackedScene = preload("res://ui/vfx/blast_visual.tscn")
## The layer a rider gets when its aspect authors none ([member Aspect.blast_layer]).
@export var rider_layer_scene: PackedScene = preload("res://ui/vfx/rider_blast_layer.tscn")
## Where a rider identity finds its aspect's bespoke layer; null = the shared roster.
@export var roster: AspectRoster = null
## Where a go-off's band finds its element; null = the shared [ElementRoster].
@export var element_roster: ElementRoster = null
## How opaque the filled disc under an element's blast ring is (Burning's disc
## reads as a disc, go-off zero's as a bare ring). Tentative, easy to change.
@export_range(0.0, 1.0, 0.01) var element_disc_fill: float = DEFAULT_DISC_FILL
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
	get_tree().create_timer(delay, false).timeout.connect(_on_stagger_elapsed.bind(mark))


## A staggered ring's cue at its time: none if muted or out of the tree since.
func _on_stagger_elapsed(mark: BlastMark) -> void:
	if not muted and is_inside_tree():
		spawn(mark)


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
	apply_look(visual, mark.go_off,
			element_roster if element_roster != null else ElementRoster.shared(), element_disc_fill)
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


## The element identity whose band holds [param go_off] (Fire for Burning), so
## a disc plays in its element's colour; null for go-off zero's Explosive, a
## null go-off or a band no element holds: the visual keeps its scene default.
static func look_for(go_off: Identity, elements: ElementRoster) -> Identity:
	if go_off == null or elements == null:
		return null
	for element in elements.elements:
		if element == null:
			continue
		for band in element.bands:
			if band != null and band.identity != null and band.identity.id == go_off.id:
				return element.identity
	return null


## Restyle [param visual] by the [GoOff] identity its mark names: the element's
## colour and a filled disc of [param fill] opacity, or the plain ring.
## The sandbox blast tab calls this too.
static func apply_look(visual: BlastVisual, go_off: Identity, elements: ElementRoster, fill: float) -> void:
	var look := look_for(go_off, elements)
	if look == null:
		return
	visual.identity = look
	visual.disc_fill = fill
