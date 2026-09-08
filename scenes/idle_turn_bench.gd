extends "res://scenes/procgen_play_sandbox.gd"

## [b]#763's instrument:[/b] a stationary-turn idle bench. This is
## [code]scenes/level.tscn[/code] plus a fixed-seed [RunBootstrap] plus the
## [IdleTurnProbe] measurement child — i.e. a REAL run (lobby-shaped roster,
## procgen, fog, HUD composed, first turn open) that then parks on the player's
## turn and measures the frame, which is the only honest answer to "what does
## nothing cost?" ([code]test/perf/bench_*.gd[/code] measure systems in
## isolation; this measures the composed game).
##
## The scene carries no authored config of its own beyond the fixed seed —
## every knob arrives on the command line so one scene serves the whole
## [code]mise run perf:idle[/code] matrix:
## [codeblock]
## godot --path . scenes/idle_turn_bench.tscn -- --nodes=2000 --seconds=3
## [/codeblock]
## Node count is applied in [method _setup_level] BEFORE
## [method procgen_play_sandbox._setup_level] reads it — not in [method _init],
## because scene-stored properties are applied after [method _init] and would
## clobber anything set there (level.tscn stores [code]node_count_override = 0[/code]).

## Seconds after reveal to let the fade-in, turn-start announcements and any
## residual tweens finish before sampling. Also covers the fog circle
## settle-animation VisionSystem runs at turn open.
@export var settle_seconds: float = 2.0
## Per-segment discarded time before sampling (driver + shader variant settle).
@export var warmup_seconds: float = 0.5
## Per-segment sampled time. Longer is calmer; the p95 column is the honest one.
@export var sample_seconds: float = 2.0
## Attribution toggles to sweep, in order, each restored before the next:
## [code]baseline[/code] (authored state), [code]gimbals-off[/code] (the #763
## prime suspect), [code]fog-pass-off[/code] (FogOverlay's fullscreen rect —
## node/edge self-shading stays on), [code]glow-off[/code] (WorldEnvironment
## injection; cross-checked by the launch-time env patch in the driver, which
## is the authoritative number).
@export var segments: Array[String] = ["baseline", "gimbals-off", "fog-pass-off", "glow-off"]


## Cmdline overrides land here, not in [method _init] — see the class docstring
## for why. Everything after the bare [code]--[/code] is ours; the engine never
## sees it.
func _setup_level() -> void:
	_apply_cmdline_overrides()
	await super()


func _apply_cmdline_overrides() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"nodes":
				node_count_override = maxi(0, int(parts[1]))
			"settle":
				settle_seconds = maxf(0.0, float(parts[1]))
			"warmup":
				warmup_seconds = maxf(0.0, float(parts[1]))
			"seconds":
				sample_seconds = maxf(0.1, float(parts[1]))
			"segments":
				var parsed: Array[String] = []
				for tok in parts[1].split(",", false):
					parsed.append(tok.strip_edges())
				if not parsed.is_empty():
					segments = parsed
			"auto-turn":
				# Off = measure the pre-turn state (no turn open). The default
				# (on) is the state #763 actually asks about.
				auto_start_turn = parts[1].to_lower() != "false"
