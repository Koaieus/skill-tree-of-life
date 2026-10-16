extends GutTest

## The native blade solver is mandatory (#816, #847). A checkout without the
## binary must FAIL here, never report PENDING while the suite prints green.

func test_native_blade_solver_is_loaded() -> void:
	assert_eq(BladeSim.backend(), &"native",
			"the native blade solver is loaded — run `mise run native:build` "
			+ "and `mise run refresh`")
