extends GutTest

## #586 — a Dormant Core prunes its loot book at spawn, so the same tier
## offers a different slice each run and sometimes offers nothing at all.
## The claimant of a relic picks exactly ONE spell from whatever is offered,
## so "how often is the book empty" is the only lever on how fast spells
## spread; the distribution assertions below are what pins that lever down.

const _BRUISER := preload("res://attack/spell/defs/bruiser.tres")
const _LEAFBLOWER := preload("res://attack/spell/defs/leafblower.tres")
const _RESONATOR := preload("res://attack/spell/defs/resonator.tres")
const _TRAIL_BLAZER := preload("res://attack/spell/defs/trail_blazer.tres")

const _SMALL_BOOK := preload("res://entity/blocker/blocker_spellbook_small.tres")
const _MEDIUM_BOOK := preload("res://entity/blocker/blocker_spellbook_medium.tres")
const _LARGE_BOOK := preload("res://entity/blocker/blocker_spellbook_large.tres")

## Every spell a blocker can ever drop lives in exactly the three books above.
## A spell listed here is deliberately NOT lootable, and the coverage test at
## the bottom is what stops a newly authored spell from silently landing in
## no book at all.
const _NOT_LOOTABLE := ["spark", "lightning_bolt"]

const _SPELL_DEF_DIR := "res://attack/spell/defs"


func _book(spells: Array) -> SpellBook:
	var b := SpellBook.new()
	for s in spells:
		b.spells.append(s)
	return b


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


# ── the prune itself ─────────────────────────────────────────────────────────

func test_prune_never_touches_the_source_book() -> void:
	var src := _book([_BRUISER, _LEAFBLOWER, _RESONATOR, _TRAIL_BLAZER])
	var out := src.duplicate_pruned(_rng(7), 1.0)
	assert_ne(out, src, "a fresh SpellBook, not the source")
	assert_ne(out.spells, src.spells, "and a fresh array, not the source's")
	assert_eq(src.spells.size(), 4, "source book is left whole")


func test_disabled_prune_keeps_the_whole_book() -> void:
	var src := _book([_BRUISER, _LEAFBLOWER])
	assert_eq(src.duplicate_pruned(_rng(1), 0.0).spells.size(), 2, "m == 0 prunes nothing")
	assert_eq(src.duplicate_pruned(null, 1.0).spells.size(), 2, "a null rng prunes nothing")


func test_prune_yields_a_subset_of_the_source() -> void:
	var src := _book([_BRUISER, _LEAFBLOWER, _RESONATOR, _TRAIL_BLAZER])
	for seed_value in 50:
		var out := src.duplicate_pruned(_rng(seed_value), 1.0)
		assert_between(out.spells.size(), 0, 4, "never grows, never goes negative")
		for s in out.spells:
			assert_true(src.spells.has(s), "every survivor came from the source")
		assert_eq(out.spells.size(), _unique(out.spells).size(), "no spell survives twice")


func test_same_seed_reproduces_the_same_book() -> void:
	# The load-bearing one for multiplayer: every peer re-runs the level
	# scene, so the prune is REPRODUCED rather than received. Two peers on
	# the same seed must land on the same book or they disagree about what
	# the relic offers.
	var src := _book([_BRUISER, _LEAFBLOWER, _RESONATOR, _TRAIL_BLAZER])
	for seed_value in 20:
		var a := src.duplicate_pruned(_rng(seed_value), 1.0)
		var b := src.duplicate_pruned(_rng(seed_value), 1.0)
		assert_eq(a.spells, b.spells, "seed %d is reproducible" % seed_value)


func test_m_of_one_is_uniform_over_every_outcome() -> void:
	# P(kept == k) == 1 / (n + 1) for every k in {0..n} — the closed form that
	# makes 1.0 both the maximum-variation setting and the stingiest sane one.
	# 4000 samples: expected 800 per bucket, tolerance ±200 (~7 sigma).
	var src := _book([_BRUISER, _LEAFBLOWER, _RESONATOR, _TRAIL_BLAZER])
	var counts := _sample_counts(src, 1.0, 4000)
	for k in 5:
		assert_between(counts[k], 600, 1000,
				"m=1 n=4: outcome %d should be ~1/5 of 4000, got %d" % [k, counts[k]])


func test_raising_m_makes_an_empty_book_rarer() -> void:
	# The direction that matters and is easy to get backwards: a HIGHER m
	# keeps more spells, so kills offer nothing less often and spells spread
	# FASTER. Turn m down to be stingier. n=4: ~41% at 0.5, 20% at 1.0,
	# ~2.9% at 3.0.
	var src := _book([_BRUISER, _LEAFBLOWER, _RESONATOR, _TRAIL_BLAZER])
	var stingy := _sample_counts(src, 0.5, 4000)[0]
	var uniform := _sample_counts(src, 1.0, 4000)[0]
	var generous := _sample_counts(src, 3.0, 4000)[0]
	assert_gt(stingy, uniform, "m=0.5 offers nothing more often than m=1")
	assert_gt(uniform, generous, "m=1 offers nothing more often than m=3")
	assert_between(stingy, 1450, 1800, "m=0.5 n=4 → ~40.6% empty")
	assert_between(generous, 60, 180, "m=3 n=4 → ~2.9% empty")


func test_mean_kept_matches_the_closed_form() -> void:
	# E[kept] == n * m / (m + 1). n=4: 1.33 at m=0.5, 2.0 at m=1, 3.0 at m=3.
	var src := _book([_BRUISER, _LEAFBLOWER, _RESONATOR, _TRAIL_BLAZER])
	for row in [[0.5, 1.33], [1.0, 2.0], [3.0, 3.0]]:
		var m: float = row[0]
		var expected: float = row[1]
		var counts := _sample_counts(src, m, 4000)
		var total := 0
		for k in counts.size():
			total += k * counts[k]
		var mean := float(total) / 4000.0
		assert_almost_eq(mean, expected, 0.15,
				"m=%s → E[kept] ~= %s, got %s" % [m, expected, mean])


# ── the authored books ───────────────────────────────────────────────────────

func test_blocker_books_climb_with_tier() -> void:
	# Book size IS the whiff dial at m=1 (P(empty) == 1/(n+1)), so the tier
	# ladder lives in these three counts. Large is deliberately the thinnest
	# and stingiest — one rare spell, offered ~50% of the time.
	assert_eq(_SMALL_BOOK.spells.size(), 2, "small: 2 spells → 33% whiff")
	assert_eq(_MEDIUM_BOOK.spells.size(), 3, "medium: 3 spells → 25% whiff")
	assert_eq(_LARGE_BOOK.spells.size(), 1, "large: 1 rare spell → 50% whiff")


func test_every_spell_is_lootable_or_explicitly_excluded() -> void:
	# The guard that makes three hand-authored books safe: a spell added to
	# the game must land in a blocker book or be named in _NOT_LOOTABLE.
	# Without this, a new spell is simply never obtainable and nothing says so.
	var lootable := {}
	for book in [_SMALL_BOOK, _MEDIUM_BOOK, _LARGE_BOOK]:
		for s in book.spells:
			assert_not_null(s, "no null entries in an authored blocker book")
			lootable[s.resource_path.get_file().get_basename()] = true
	for spell_name in _all_spell_def_names():
		assert_true(lootable.has(spell_name) or spell_name in _NOT_LOOTABLE,
				"spell '%s' is in no blocker book and not in _NOT_LOOTABLE — it can never be looted"
						% spell_name)


func test_default_known_spells_are_kept_out_of_the_loot_books() -> void:
	# Anything in spellbook_default.tres is innate for every entity, and
	# SkillDustAddon._exclude_permanently_known drops innate spells from the
	# offer. Listing one in a blocker book would be a dead entry that still
	# inflates the book size — and book size is the whiff dial.
	var default_book: SpellBook = load("res://entity/spellbook_default.tres")
	for book in [_SMALL_BOOK, _MEDIUM_BOOK, _LARGE_BOOK]:
		for s in book.spells:
			assert_false(default_book.spells.has(s),
					"'%s' is known by default, so it can never be offered as loot"
							% s.resource_path.get_file())


# ── helpers ──────────────────────────────────────────────────────────────────

## Kept-count histogram over `samples` prunes of `src`, indexed by how many
## spells survived (so `[0]` is "offered nothing").
func _sample_counts(src: SpellBook, m: float, samples: int) -> Array[int]:
	var counts: Array[int] = []
	counts.resize(src.spells.size() + 1)
	counts.fill(0)
	var rng := _rng(20260826)
	for _i in samples:
		counts[src.duplicate_pruned(rng, m).spells.size()] += 1
	return counts


func _unique(arr: Array) -> Array:
	var seen := []
	for a in arr:
		if not seen.has(a):
			seen.append(a)
	return seen


func _all_spell_def_names() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(_SPELL_DEF_DIR)
	assert_not_null(dir, "spell def directory is readable: %s" % _SPELL_DEF_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		# Exported builds rename .tres to .remap; strip either suffix.
		if f.ends_with(".tres") or f.ends_with(".tres.remap"):
			out.append(f.get_basename().get_basename())
	assert_gt(out.size(), 0, "found spell defs to check")
	return out
