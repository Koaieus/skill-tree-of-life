extends GutTest

## [HarnessFlags] — the multiplayer harness's argv vocabulary (#754).
##
## The property under test is mostly a NEGATIVE one: every reader must answer
## "absent" for anything it was not asked about, because this same scan runs in
## [MetaRoot] and [GameRoot] on every ordinary launch, every export and every
## test in this suite. A parser that guessed would change the game's behaviour
## for someone who typed nothing.

const _RUNG4: PackedStringArray = [
	"--lobby=host", "--port=9300", "--autoplay", "--max-turns=80",
]


func test_pair_flag_reads_its_value() -> void:
	assert_eq(HarnessFlags.value(HarnessFlags.LOBBY, "", _RUNG4), "host")


func test_bare_flag_is_present_with_an_empty_value() -> void:
	assert_true(HarnessFlags.has(HarnessFlags.AUTOPLAY, _RUNG4))
	assert_eq(HarnessFlags.value(HarnessFlags.AUTOPLAY, "fallback", _RUNG4), "")


## The whole contract in one assertion: an ordinary launch has no user args, so
## every reader falls back and nothing the harness adds can fire.
func test_an_ordinary_launch_reads_nothing() -> void:
	var none: PackedStringArray = []
	assert_eq(HarnessFlags.value(HarnessFlags.LOBBY, "", none), "")
	assert_false(HarnessFlags.has(HarnessFlags.AUTOPLAY, none))
	assert_eq(HarnessFlags.number(HarnessFlags.MAX_TURNS, 400, none), 400)


func test_unrelated_arguments_are_skipped_not_rejected() -> void:
	var mixed: PackedStringArray = ["--probe", "res://scenes/level.tscn", "--autoplay"]
	assert_true(HarnessFlags.has(HarnessFlags.AUTOPLAY, mixed))
	assert_false(HarnessFlags.has(HarnessFlags.LOBBY, mixed))


## A prefix must not match a longer flag: `--port` and `--portal` are two
## different words, and a `begins_with("port")` scan would read the second as
## the first with a value of `al=…`.
func test_a_longer_flag_is_not_a_prefix_match() -> void:
	var args: PackedStringArray = ["--portal=9300"]
	assert_false(HarnessFlags.has(HarnessFlags.PORT, args))


func test_number_falls_back_on_a_non_number() -> void:
	var args: PackedStringArray = ["--max-turns=soon"]
	assert_eq(HarnessFlags.number(HarnessFlags.MAX_TURNS, 400, args), 400)


## `--max-turns` with nothing after it is a typo, and a silent 0 would end the
## run before it began.
func test_number_falls_back_on_a_valueless_flag() -> void:
	var args: PackedStringArray = ["--max-turns"]
	assert_eq(HarnessFlags.number(HarnessFlags.MAX_TURNS, 400, args), 400)


func test_last_occurrence_wins() -> void:
	var args: PackedStringArray = ["--lobby=host", "--lobby=client"]
	assert_eq(HarnessFlags.value(HarnessFlags.LOBBY, "", args), "client")
