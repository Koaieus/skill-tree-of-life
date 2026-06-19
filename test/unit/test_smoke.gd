extends GutTest


func test_gut_is_alive() -> void:
	assert_eq(1 + 1, 2)


func test_stat_registry_loads() -> void:
	assert_not_null(StatRegistry, "StatRegistry autoload should be present")
