extends GutTest

## Quiver = the `arrows` PoolStat with per-AmmoType bins (#496).
## Pending until the child issue lands; its first commit flips these red.


func test_add_then_stock_of_reports_the_bin() -> void:
	pending("#496 child: Quiver bins")


func test_take_never_returns_more_than_the_bin_holds() -> void:
	pending("#496 child: Quiver bins")


func test_current_equals_sum_of_bins_after_every_transfer() -> void:
	pending("#496 child: Quiver bins")


func test_add_clamps_to_capacity_and_capacity_rise_does_not_gift_arrows() -> void:
	pending("#496 child: Quiver cap policy PIN")


func test_to_dict_round_trips_bins() -> void:
	pending("#496 child: Quiver serialisation")
