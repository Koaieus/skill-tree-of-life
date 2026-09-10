class_name GameSettings
extends Resource

## Every player-facing setting, as real typed @exports — deliberately NOT a
## StringName registry (stats earn one because stat identity is genuinely
## runtime-dynamic; every settings read site knows the name at author time).
## Retiring a setting here means every call site fails to compile, loud and
## exhaustive, instead of a registry lookup silently returning null forever.
##
## get_property_list() walk (@export_group -> sections, hint/hint_string ->
## widget) drives both the reflected settings menu and ConfigFile
## persistence — one source of truth, written once.

enum WindowMode { WINDOWED, FULLSCREEN, BORDERLESS }

## #796: a spectating peer's melee blade resim is draw-only (ADR 0002) — every
## hit, pop and damage number it shows already comes off the confirmed
## [AttackRecord], so this trades solve cost for visual smoothness with zero
## correctness consequence. LOW is `substeps = 1`, length scaling off, roughly
## pre-#790 cost; HIGH matches what the authority itself solves.
enum PeerSimFidelity { LOW, HIGH }

## Indexed by the `resolution` export below; keep the two in lockstep.
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

@export_group("Audio")
@export_range(0.0, 1.0) var master_volume: float = 0.8

@export_group("Gameplay")
@export var confirm_islanding_dealloc: bool = true
@export_range(0.0, 2.0) var ai_turn_delay: float = 0.4
## Skip presentation-layer transitions and land on their end state in one
## frame — the frontmatter's camera move and grow-in (#570), and anything that
## follows it. An accessibility setting, sitting beside `ai_turn_delay` because
## both are about how much motion the player sits through rather than about a
## rule. Every animated unit honours it by jumping to `set_progress(1.0)`; none
## of them branch further than that.
@export var reduce_motion: bool = false
## Seconds-per-second of combat presentation — the RATE half of #543's tempo
## split, folded in by [method OutcomeSchedule.compile] after every authored
## shape term. 1.0 is the authored speed; 0.5 plays combat at double speed
## ("fast combat"), 2.0 is a slow-motion replay.
##
## [b]Safe to differ between machines.[/b] Landing order and the crit stream key
## off [member ScheduleEntry.index], never off seconds
## (`.claude/rules/multiplayer-sync.md`, #543 D2/D4) — so one player can run
## combat at double speed and still end in a bit-identical world.
@export_range(0.25, 3.0, 0.05) var combat_time_scale: float = 1.0

@export_group("Player")
## #741 LAN QoL: the name a fresh lobby seeds a local human seat with, kept
## in step by [method LobbyScreen._maybe_save_default_name] whenever a commit
## is unambiguously this machine's own identity to record. Per-machine, not
## a profile — there is no login, so "whoever last typed a name here" is the
## whole model, and [LobbyScreen]'s Name field is still the final word: this
## only saves a re-type next time.
@export var player_name: String = ""

@export_group("Display")
@export_enum("Windowed", "Fullscreen", "Borderless") var window_mode: int = WindowMode.WINDOWED
@export_enum("1280x720", "1600x900", "1920x1080", "2560x1440", "3840x2160") var resolution: int = 2
@export_enum("Disabled", "Enabled", "Adaptive") var vsync_mode: int = DisplayServer.VSYNC_ENABLED
## 0 = uncapped.
@export_range(0, 300, 1) var max_fps: int = 0
## A spectating peer's blade resim is draw-only (ADR 0002), so this is a pure
## graphics knob — every hit, pop and damage number comes off the [AttackRecord]
## regardless. LOW is substeps 1 + no length scaling.
##
## [b]Defaults HIGH[/b] — owner call 2026-09-10, against measurement. LOW is a
## much weaker lever than it looks: #790 pinned trajectory sampling to 1/120
## [i]independent[/i] of the substep rate precisely so hit-scan would not inflate
## with it, so substeps divide only the solver half. A measured k=51 resolve near
## 100 defenders (native, Tier H) is 65 ms whole; LOW takes that to ~40 ms, a
## 1.6x saving, not the 4x the substep ratio suggests.
##
## What actually keeps a peer honest is [member MeleePreview.replay_slice_steps],
## not this: the minimum viable slice is 120/fps and its cost is ~5.4% of a frame
## at HIGH regardless of fps, so the "can I sim a frame's worth within a frame"
## bar is met at either fidelity. At the shipped slice of 12 the resim completes
## in 12 of the swing's 72 frames and then costs nothing — a front-loaded burst,
## not a sustained tax. This stays as the escape hatch for a machine that cannot
## hold even that.
@export_enum("Low", "High") var melee_peer_sim_fidelity: int = PeerSimFidelity.HIGH
