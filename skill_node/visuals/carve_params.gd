class_name CarveParams
extends RefCounted
## The carve an InnerDisk renders, as one typed value: the 7-tuple its shader
## reads, resolved from InnerDisk's `effective_*` getters (never read back from
## instance uniforms — a hidden disk never pushed them). It is the union over
## `InnerDisk.CarveKind { NONE, POLYGON, GEM, TEXTURE }`: POLYGON reads
## sides/squish/radius, GEM the shared `gem_lut`, TEXTURE the shared
## `carve_atlas` at layer [member carve_slice] (+ [member carve_slice_b] for a
## spell-tie crossfade); [member well_depth] applies to every kind.
##
## Owns the tuple's texel layout too ([method to_texels]), so the live disk's
## uniform push and ShatterField's per-slot data texture share one definition.
## Layout, two RGBAF texels (32-bit floats, so every integer is exact):
##   texel 0 = (carve_kind, carve_sides, carve_squish, carve_radius)
##   texel 1 = (well_depth, carve_slice, carve_slice_b, 0)
## Must match `inner_disk_shatter.gdshader`'s `vertex()` read.

const TEXELS: int = 2
## `InnerDisk.CarveKind.NONE`; InnerDisk carries no `class_name` to name it by.
const KIND_NONE: int = 0
const NO_SLICE: int = -1

var carve_kind: int = KIND_NONE
var carve_sides: int = 3
var carve_squish: float = 1.0
var carve_radius: float = 0.75
var well_depth: float = 0.35
var carve_slice: int = NO_SLICE
var carve_slice_b: int = NO_SLICE


## The empty dome: what a caller with no carve to hand writes.
static func none() -> CarveParams:
	return CarveParams.new()


func to_texels() -> PackedColorArray:
	return PackedColorArray([
		Color(float(carve_kind), float(carve_sides), carve_squish, carve_radius),
		Color(well_depth, float(carve_slice), float(carve_slice_b), 0.0),
	])


## Inverse of [method to_texels] — for reading a slot back out of the texture.
static func from_texels(a: Color, b: Color) -> CarveParams:
	var p := CarveParams.new()
	p.carve_kind = roundi(a.r)
	p.carve_sides = roundi(a.g)
	p.carve_squish = a.b
	p.carve_radius = a.a
	p.well_depth = b.r
	p.carve_slice = roundi(b.g)
	p.carve_slice_b = roundi(b.b)
	return p


## The live disk's instance-uniform names mapped to this tuple — one loop in
## `InnerDisk._sync_material` instead of seven hand-written pushes.
func uniforms() -> Dictionary[StringName, Variant]:
	return {
		&"carve_kind": carve_kind,
		&"carve_sides": float(carve_sides),
		&"carve_squish": carve_squish,
		&"carve_radius": carve_radius,
		&"well_depth": well_depth,
		&"carve_slice": carve_slice,
		&"carve_slice_b": carve_slice_b,
	}


func equals(other: CarveParams) -> bool:
	return other != null and to_texels() == other.to_texels()


func _to_string() -> String:
	return "CarveParams(kind=%d sides=%d squish=%s radius=%s well=%s slice=%d/%d)" % [
		carve_kind, carve_sides, carve_squish, carve_radius, well_depth, carve_slice, carve_slice_b]
