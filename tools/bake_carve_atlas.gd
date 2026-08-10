extends SceneTree
## Packs every mapped icon's pre-baked CARVE LUT into the [CarveAtlas] the
## live shader samples (#247). The LUTs themselves are baked upstream by
## `tools/bake_svg_sdf.py` (SVG -> msdfgen true SDF -> numpy post-process),
## not by this script — see docs/domain/emblem-bake.md. Driven by
## `mise run icons:update` as the last stage of the spell-icon lifecycle:
##
##     godot --headless --script res://tools/bake_carve_atlas.gd
##
## Emits three things, all committed:
##   - `assets/emblem_luts/carve_atlas.png` (+ `.import`) — the per-icon LUTs
##     stacked vertically, imported as a [CompressedTexture2DArray].
##   - `assets/emblem_luts/carve_atlas.tres` — the [CarveAtlas] manifest binding
##     each slice index to its LUT's `res://` path.
##   - (the per-icon LUT PNGs under `assets/emblem_luts/` are written by
##     `bake_svg_sdf.py`, not here)
##
## The stacked PNG goes through Godot's `2d_array_texture` importer rather than
## `ResourceSaver.save()` on a [Texture2DArray] — the latter writes a file that
## reloads with ZERO layers (verified empirically on 4.7; its images don't
## survive serialization). The importer is also the reason the payload stays
## intact: unlike the plain `texture` importer it exposes no `fix_alpha_border`
## (which would rewrite the RGB of transparent texels — and here RGB IS the
## height+gradient payload, alpha is only the mask), and `compress/mode=0`
## keeps it lossless RGBA8.

const TextureCarveShape = preload("res://skill_node/visuals/emblem/texture_carve_shape.gd")
const CarveAtlas = preload("res://skill_node/visuals/emblem/carve_atlas.gd")

const MAPPING := "res://assets/icons/spells/mapping.txt"
const LUT_DIR := "res://assets/emblem_luts/"
const ATLAS_PNG := LUT_DIR + "carve_atlas.png"


func _initialize() -> void:
	var names := _mapped_icon_names()
	if names.is_empty():
		printerr("bake_carve_atlas: no icons in ", MAPPING)
		quit(1)
		return

	var size := TextureCarveShape.LUT_SIZE
	var stacked := Image.create(size, size * names.size(), false, Image.FORMAT_RGBA8)
	var slice_paths := PackedStringArray()

	for i in names.size():
		var name: String = names[i]
		var lut_path := LUT_DIR + name + ".png"
		# load() (imported Texture2D) rather than Image.load_from_file() — the
		# latter pushes a "will not work on export" warning per slice.
		var source: Texture2D = load(lut_path)
		if source == null:
			printerr("bake_carve_atlas: missing LUT ", lut_path, " — run `mise run icons:update` first")
			quit(1)
			return
		var lut := source.get_image()
		lut.convert(Image.FORMAT_RGBA8)
		# blit_rect copies the base mip only — exactly what we want stacked; the
		# importer regenerates the array's own mip chain per slice.
		stacked.blit_rect(lut, Rect2i(0, 0, size, size), Vector2i(0, size * i))
		slice_paths.append(lut_path)
		print("  ✓ ", name, "  → slice ", i)

	stacked.save_png(ATLAS_PNG)
	_write_atlas_import(names.size())

	var atlas := CarveAtlas.new()
	atlas.slice_paths = slice_paths
	var err := ResourceSaver.save(atlas, CarveAtlas.PATH)
	if err != OK:
		printerr("bake_carve_atlas: failed to save manifest: ", err)
		quit(1)
		return

	print("✓ packed ", names.size(), " LUT slices → ", ATLAS_PNG)
	quit()


## Icon names from the shared `mapping.txt` — the same file `icons:update`
## rasterizes from, so the atlas roster and the icon roster can't diverge.
func _mapped_icon_names() -> PackedStringArray:
	var names := PackedStringArray()
	var f := FileAccess.open(MAPPING, FileAccess.READ)
	if f == null:
		return names
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var parts := line.split("\t", false)
		if parts.size() >= 1 and not parts[0].is_empty():
			names.append(parts[0])
	return names


## Writes the `.import` that makes the stacked PNG a Texture2DArray. Only the
## params that carry meaning here are pinned; Godot fills the rest with its own
## defaults on reimport. `slices/vertical` must track the slice count, which is
## precisely why this is generated rather than hand-maintained.
func _write_atlas_import(slice_count: int) -> void:
	var f := FileAccess.open(ATLAS_PNG + ".import", FileAccess.WRITE)
	f.store_string("""[remap]

importer="2d_array_texture"
type="CompressedTexture2DArray"

[deps]

source_file="%s"

[params]

compress/mode=0
mipmaps/generate=true
slices/horizontal=1
slices/vertical=%d
""" % [ATLAS_PNG, slice_count])
