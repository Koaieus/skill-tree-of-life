@tool
class_name CarveAtlas
extends Resource
## The packed home for every baked CARVE LUT (#247) — one [TextureLayered]
## holding N slices, plus the manifest that says which slice a given baked LUT
## occupies. Generated offline by `tools/bake_carve_atlas.gd` (driven by
## `mise run icons:update`); see docs/domain/emblem-bake.md.
##
## WHY AN ATLAS AND NOT N SAMPLERS. [InnerDisk] renders every node in the level
## through ONE shared [ShaderMaterial], varying per-node only via
## `instance uniform`s — that's what keeps thousands of nodes batching into a
## single draw call. A sampler cannot BE an `instance uniform`, so "one
## sampler2D per baked shape" would either force a per-node duplicate material
## (breaking the batching outright) or burn one plain uniform per shape. Packing
## every LUT into a single [TextureLayered] leaves exactly one plain sampler on
## the shared material, and the only per-node value is a cheap int **index into**
## it — which an `instance uniform` can carry. That's also why this scales past
## the #172 instance-uniform slot ceiling: adding the 50th baked shape adds a
## slice, not a slot.

## Where [method shared] loads the generated manifest from.
const PATH := "res://assets/emblem_luts/carve_atlas.tres"

## The stacked-and-imported slices. Resolved by PATH rather than held as an
## `@export`, so the generator never has to write a resource reference into the
## manifest — a hand-written `ext_resource` uid that doesn't match its target
## resolves to null SILENTLY (see .claude/rules/godot-workflow.md), and it would
## also force the generator into a two-phase bake/reimport/link dance, since the
## imported texture doesn't exist yet on the pass that writes the manifest.
const TEXTURE_PATH := "res://assets/emblem_luts/carve_atlas.png"

## Returned by [method slice_of] for a LUT this atlas doesn't carry.
const NO_SLICE := -1

static var _shared: CarveAtlas
static var _shared_loaded := false

## `res://` path of the baked LUT in each slice, indexed BY slice. This is the
## whole manifest — a [TextureCarveShape]'s slice is looked up from its
## [member TextureCarveShape.baked_lut]'s own `resource_path`, so the generator
## is the single source of truth and no shape carries a hand-authored index
## that could silently drift out of step with the packing.
@export var slice_paths: PackedStringArray


## The project's generated manifest, loaded once. Null when it hasn't been
## generated yet (`mise run icons:update`) — callers fall back to no carve.
static func shared() -> CarveAtlas:
	if not _shared_loaded:
		_shared_loaded = true
		if ResourceLoader.exists(PATH):
			_shared = ResourceLoader.load(PATH) as CarveAtlas
	return _shared


## The packed slice texture, or null if it hasn't been generated. Typed
## [TextureLayered], not [Texture2DArray]: the importer yields a
## [CompressedTexture2DArray], which is a SIBLING of [Texture2DArray] rather
## than a subclass, so the narrower type fails to assign at runtime.
func texture() -> TextureLayered:
	if not ResourceLoader.exists(TEXTURE_PATH):
		return null
	return ResourceLoader.load(TEXTURE_PATH) as TextureLayered


## Which slice carries `lut`, or [constant NO_SLICE] if this atlas doesn't have
## it. An in-memory bake (no `resource_path`) is never in the atlas by
## definition — the atlas packs committed assets.
func slice_of(lut: Texture2D) -> int:
	if lut == null or lut.resource_path.is_empty():
		return NO_SLICE
	return slice_paths.find(lut.resource_path)
