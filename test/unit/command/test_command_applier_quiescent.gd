extends GutTest

## [method CommandApplier.is_quiescent] collapses the three "world in motion"
## flags into the one question a save gate asks: quiescent iff nothing is
## applying, nothing awaits confirmation, and no relic claim chain is open.

var _applier: CommandApplier


func before_each() -> void:
	_applier = CommandApplier.new()
	add_child_autofree(_applier)


func test_an_idle_applier_is_quiescent() -> void:
	assert_true(_applier.is_quiescent())


func test_applying_is_not_quiescent() -> void:
	_applier.is_applying = true
	assert_false(_applier.is_quiescent(), "a mutation under way is not at rest")


func test_awaiting_confirmation_is_not_quiescent() -> void:
	_applier.is_awaiting_confirmation = true
	assert_false(_applier.is_quiescent(), "a submitted command is not at rest")


func test_outstanding_loot_is_not_quiescent_until_it_closes() -> void:
	_applier.notify_loot_round_opened()
	assert_false(_applier.is_quiescent(), "an open loot pick is not at rest")
	_applier.notify_loot_round_closed()
	assert_true(_applier.is_quiescent(), "the closed pick returns it to rest")
