extends GutTest

## The [IdentityRoster] is the runtime door onto every [Identity]; these tests
## are its drift guard (a directory scan, test-only — exporting.md D13), the
## hue contract (distinct within a kind, gold reserved for reward) and the
## wiring contract (every facet of a concept references the concept's `.tres`).

## OKLab dE every same-kind pair must clear — the `test_lobby_roster.gd` bar.
const MIN_SEPARATION := 0.14
## How close a non-reward hue may sit to the XP gold.
const GOLD_EXCLUSION := 0.10
const XP_GOLD := Color(0.8909, 0.7204, 0.2596)
const GOLD_OWNERS: Array[StringName] = [&"xp", &"wisdom"]

const _DEFS_DIR := "res://identity/defs"
const _STAT_DEFS_DIR := "res://stats_system/defs"
const _STATUS_DIR := "res://effects/status"
const _SPELL_DIR := "res://attack/spell/defs"
const _ADDON_DIR := "res://skill_node/addons/defs"
## The per-concept stat suffixes that make a stat a facet of an aspect.
const _ASPECT_SUFFIXES: Array[String] = ["_aspect", "_resistance", "_stacks_per_hit"]


func _identities_on_disk() -> Array[Identity]:
	var out: Array[Identity] = []
	for file in DirAccess.get_files_at(_DEFS_DIR):
		if file.ends_with(".tres"):
			out.append(load("%s/%s" % [_DEFS_DIR, file]) as Identity)
	return out


func test_roster_lists_every_identity_on_disk() -> void:
	var roster := IdentityRoster.shared()
	assert_not_null(roster, "the shared roster loads")
	var on_disk := _identities_on_disk()
	assert_gt(on_disk.size(), 0, "identity/defs/ holds identities")
	for identity in on_disk:
		assert_true(roster.identities.has(identity),
				"%s is on disk but not in the roster" % identity.resource_path)
	assert_eq(roster.identities.size(), on_disk.size(), "and nothing else")


func test_ids_are_unique_and_resolve() -> void:
	var roster := IdentityRoster.shared()
	var seen := {}
	for identity in roster.identities:
		assert_ne(identity.id, &"", "%s has an id" % identity.resource_path)
		assert_false(seen.has(identity.id), "%s is unique" % identity.id)
		seen[identity.id] = true
		assert_eq(roster.by_id(identity.id), identity, "by_id resolves %s" % identity.id)


func test_same_kind_hues_are_separated() -> void:
	var all := IdentityRoster.shared().identities
	for i in all.size():
		for j in range(i + 1, all.size()):
			var a: Identity = all[i]
			var b: Identity = all[j]
			# Spells carry no hue (all NEUTRAL): motion and heat, never hue.
			if a.kind != b.kind or a.kind == Identity.Kind.SPELL:
				continue
			var d := _delta_e_ok(a.tint, b.tint)
			assert_gte(d, MIN_SEPARATION,
					"%s vs %s: dE %.3f under %.2f" % [a.id, b.id, d, MIN_SEPARATION])


func test_gold_is_reserved() -> void:
	for identity in IdentityRoster.shared().identities:
		if identity.id in GOLD_OWNERS:
			continue
		var d := _delta_e_ok(identity.tint, XP_GOLD)
		assert_gte(d, GOLD_EXCLUSION, "%s sits in gold territory (dE %.3f)" % [identity.id, d])


## XP/turn is a facet of the XP concept: one concept, one hue (ADR 0046). The
## other near-gold stat defs (level, bounty, core_kill_xp, ap_transfer_rate)
## are reward/value registers, not concept identities.
func test_xp_per_turn_reads_the_xp_identity() -> void:
	var def := load("%s/xp_per_turn.tres" % _STAT_DEFS_DIR) as StatDef
	assert_not_null(def.identity, "xp_per_turn hand-authors its gold")
	if def.identity != null:
		assert_true(def.identity.id in GOLD_OWNERS, "xp_per_turn's identity is a gold owner")
		assert_eq(def.identity.id, &"xp", "xp_per_turn references xp.tres")


func test_tints_are_unlifted() -> void:
	for identity in IdentityRoster.shared().identities:
		var c := identity.tint
		assert_true(c.r <= 1.0 and c.g <= 1.0 and c.b <= 1.0,
				"%s stores an unlifted hue — tiers are the presenter's" % identity.id)


func test_aspect_stats_reference_their_concept() -> void:
	var checked := 0
	for identity in IdentityRoster.shared().identities:
		if identity.kind != Identity.Kind.ASPECT:
			continue
		for suffix in _ASPECT_SUFFIXES:
			var path := "%s/%s%s.tres" % [_STAT_DEFS_DIR, identity.id, suffix]
			if not ResourceLoader.exists(path):
				continue
			var def := load(path) as StatDef
			assert_not_null(def.identity, "%s has no identity" % def.id)
			if def.identity != null:
				assert_eq(def.identity.id, identity.id, "%s's identity" % def.id)
			checked += 1
	assert_gt(checked, 0, "expected to check some aspect stats")


func test_named_stats_reference_their_concept() -> void:
	for identity in IdentityRoster.shared().identities:
		if identity.kind == Identity.Kind.ASPECT:
			continue
		var path := "%s/%s.tres" % [_STAT_DEFS_DIR, identity.id]
		if not ResourceLoader.exists(path):
			continue
		var def := load(path) as StatDef
		assert_not_null(def.identity, "%s has no identity" % def.id)
		if def.identity != null:
			assert_eq(def.identity.id, identity.id, "%s's identity" % def.id)


func test_every_status_def_references_its_concept() -> void:
	var checked := 0
	for file in DirAccess.get_files_at(_STATUS_DIR):
		if not file.ends_with(".tres"):
			continue
		var def := load("%s/%s" % [_STATUS_DIR, file]) as StatusDef
		if def == null:
			continue
		assert_not_null(def.identity, "%s has no identity" % file)
		if def.identity != null:
			assert_eq(def.identity.id, def.id, "%s's identity" % file)
		checked += 1
	assert_gt(checked, 0, "expected to check some StatusDefs")


func test_every_spell_def_references_a_spell_identity() -> void:
	var roster := IdentityRoster.shared()
	var checked := 0
	for file in DirAccess.get_files_at(_SPELL_DIR):
		if not file.ends_with(".tres"):
			continue
		var def := load("%s/%s" % [_SPELL_DIR, file]) as SpellDef
		if def == null:
			continue
		checked += 1
		assert_not_null(def.identity, "%s has no identity" % file)
		if def.identity == null:
			continue
		assert_eq(def.identity.kind, Identity.Kind.SPELL, "%s's identity kind" % file)
		assert_true(roster.identities.has(def.identity), "%s's identity is rostered" % file)
		assert_eq(def.icon, def.identity.icon, "%s reads its icon through the identity" % file)
	assert_gt(checked, 0, "expected to check some SpellDefs")


func test_every_addon_scene_references_an_identity() -> void:
	var roster := IdentityRoster.shared()
	var checked := 0
	for addon in _addon_roots():
		checked += 1
		assert_not_null(addon.identity, "%s has no identity" % addon.scene_file_path)
		if addon.identity == null:
			continue
		assert_true(roster.identities.has(addon.identity),
				"%s's identity is rostered" % addon.scene_file_path)
		assert_eq(addon.icon, addon.identity.icon, "%s icon via identity" % addon.scene_file_path)
		assert_eq(addon.tint, addon.identity.tint, "%s tint via identity" % addon.scene_file_path)
	assert_gt(checked, 0, "expected to check some addon scenes")


func test_an_on_hit_addon_shares_its_status_identity() -> void:
	var checked := 0
	for addon in _addon_roots():
		var dot := addon
		if dot.on_hit_effects.is_empty():
			continue
		for effect in dot.on_hit_effects:
			var status := effect as ApplyStatusEffect
			if status == null or status.def == null:
				continue
			assert_not_null(dot.identity, "%s has no identity" % dot.scene_file_path)
			assert_eq(dot.identity, status.def.identity,
					"%s shares %s's identity" % [dot.scene_file_path, status.def.id])
			checked += 1
	assert_gt(checked, 0, "expected to check some on-hit addons")


func _addon_roots() -> Array[SkillNodeAddon]:
	var out: Array[SkillNodeAddon] = []
	for file in DirAccess.get_files_at(_ADDON_DIR):
		if not file.ends_with(".tscn"):
			continue
		var addon := (load("%s/%s" % [_ADDON_DIR, file]) as PackedScene).instantiate() as SkillNodeAddon
		if addon == null:
			continue
		autofree(addon)
		out.append(addon)
	return out


# Copied from test/unit/session/test_lobby_roster.gd.
static func _oklab(c: Color) -> Vector3:
	var lin := c.srgb_to_linear()
	var l := 0.4122214708 * lin.r + 0.5363325363 * lin.g + 0.0514459929 * lin.b
	var m := 0.2119034982 * lin.r + 0.6806995451 * lin.g + 0.1073969566 * lin.b
	var s := 0.0883024619 * lin.r + 0.2817188376 * lin.g + 0.6299787005 * lin.b
	var l_ := pow(maxf(l, 0.0), 1.0 / 3.0)
	var m_ := pow(maxf(m, 0.0), 1.0 / 3.0)
	var s_ := pow(maxf(s, 0.0), 1.0 / 3.0)
	return Vector3(
			0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
			1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
			0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)


static func _delta_e_ok(a: Color, b: Color) -> float:
	return (_oklab(a) - _oklab(b)).length()
