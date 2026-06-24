@tool
class_name AddonPoolEntry
extends Resource

## One pick option in an [AddonPool]. Like [ModifierPoolEntry] but mints a
## [SkillNodeAddon] instance from a PackedScene, optionally overriding fields
## via `params`. `cost` is spent from the per-node addon budget; `weight` is
## the base sampling weight (modulated by addon-pass weight profiles).

@export var id: StringName = &""
## The addon scene to instantiate. Root must extend [SkillNodeAddon].
@export var addon_scene: PackedScene
## Dictionary[StringName, Variant] of fields to set on the instance after
## instantiation but before parenting. Inspector-edited; keys are field names.
@export var params: Dictionary = {}
@export var cost: int = 1
@export var weight: float = 1.0
@export var tags: Array[StringName] = []


## Instantiates the addon scene and applies `params`. Returns null on failure.
## `rng` is unused at present; future entries may roll per-param ranges.
func mint(_rng: RandomNumberGenerator) -> SkillNodeAddon:
	if addon_scene == null:
		return null
	var instance := addon_scene.instantiate()
	if instance == null:
		return null
	if not instance is SkillNodeAddon:
		instance.queue_free()
		push_warning("AddonPoolEntry %s: scene root is not a SkillNodeAddon" % String(id))
		return null
	for key in params.keys():
		instance.set(StringName(key), params[key])
	return instance


func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	if id == &"":
		out.append("id should be set.")
	if addon_scene == null:
		out.append("addon_scene is null — entry will mint nothing.")
	if cost < 1:
		out.append("cost should be ≥ 1.")
	var registry := TagRegistry.canonical()
	if registry != null:
		var unknown := registry.unknown_tags(tags)
		for t in unknown:
			out.append("unknown tag: %s" % String(t))
	return out
