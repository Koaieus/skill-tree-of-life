extends GutTest

## Every aspect, attribute and vital [Identity] carries a baked game-icons glyph
## from its kind's folder, and every such glyph is imported with mipmaps — they
## ship at ~24 px, where an unmipped minification shimmers (icon-assets rule).


func _identities_of(kinds: Array[Identity.Kind]) -> Array[Identity]:
	var out: Array[Identity] = []
	for identity in IdentityRoster.shared().identities:
		if identity.kind in kinds:
			out.append(identity)
	return out


func _assert_glyphs(kinds: Array[Identity.Kind], folder: String) -> void:
	var identities := _identities_of(kinds)
	assert_gt(identities.size(), 0, "the roster holds identities of this kind")
	for identity in identities:
		assert_not_null(identity.icon, "%s has an icon" % identity.id)
		if identity.icon == null:
			continue
		var path := identity.icon.resource_path
		assert_true(path.begins_with(folder),
				"%s's icon %s lives under %s" % [identity.id, path, folder])
		var import_text := FileAccess.get_file_as_string(path + ".import")
		assert_string_contains(import_text, "mipmaps/generate=true",
				"%s.import generates mipmaps" % path)


func test_every_aspect_has_a_glyph_from_aspects_folder() -> void:
	_assert_glyphs([Identity.Kind.ASPECT], "res://assets/icons/aspects/")
