extends GutTest

## ReloadCommand: 1 AP, yield = Σ node-local arrows_per_reload over the
## turn-start leaf set ∪ core, specials flat (#496).


func test_reload_costs_one_ap_and_adds_arrows_per_reload_per_turn_start_leaf() -> void:
	pending("#496 child: reload command")


func test_leaves_allocated_this_turn_do_not_count_toward_the_reload() -> void:
	pending("#496 child: reload command — pump closed")


func test_special_arrows_are_flat_never_times_leaves() -> void:
	pending("#496 child: reload command")


func test_reload_replays_identically_on_a_mirror() -> void:
	pending("#496 child: reload command — wire")
