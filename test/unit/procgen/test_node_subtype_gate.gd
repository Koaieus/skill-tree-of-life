extends GutTest
## The subtype axis: a second key on the per-node pool filter, orthogonal to
## archetype. Every test here is `pending()` until the mechanism lands — the
## stub on master carries the signatures only, so trunk stays green.
##
## See docs/design/node_subtypes.md for the model and the decisions.

const _SET := preload("res://procgen/pools/specimen_pool_set.tres")


## The gate. A pool naming only `bless` must be invisible to a regular node,
## and visible to a blessed one. This is decision 12 — the set IS the give-up,
## so this test also covers "blighted DEX cannot draw the crit pool".
func test_a_pool_gated_to_a_subtype_is_absent_from_another_subtypes_flatten() -> void:
	pending("subtype gate unbuilt — StatPool.subtypes is authored but not read")


## Inertness. With no subtypes authored, every pool's `subtypes` is empty, so
## the two-key filter selects exactly what the one-key filter selects — and
## `to_entries` appends no id segment, so entry ids stay byte-identical.
func test_an_empty_subtype_set_selects_exactly_what_the_archetype_gate_selects() -> void:
	pending("subtype gate unbuilt")


## Two pools for the same (stat, op, archetype) gated to different subtypes
## must mint DIFFERENT entry ids, or weight profiles target the wrong one.
## The segment appears ONLY when `subtypes` is non-empty, so no existing id moves.
func test_subtype_gated_pools_do_not_collide_on_entry_id() -> void:
	pending("id segment unbuilt")


## The structural fallback (decision 13). A subtype with `base_chance = 1.0`
## and zero pools naming it must leave every node on the default subtype —
## a node must never look like something it does not play.
func test_a_subtype_with_no_drawable_content_demotes_to_the_default() -> void:
	pending("placement roll unbuilt")


## The salt trap. Generating with `subtypes = []` and with a subtype authored
## must leave every node that ends up regular with IDENTICAL modifiers. This is
## the test that goes RED if the subtype roll comes off the main rng stream.
func test_the_subtype_roll_does_not_shift_the_main_rng_stream() -> void:
	pending("placement roll unbuilt")
