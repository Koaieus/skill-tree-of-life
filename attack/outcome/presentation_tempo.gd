class_name PresentationTempo
extends Resource

## The [b]shape[/b] half of an attack's presentation timing — beat interval,
## flight lead-in, launch stagger, swing length (#543 D3a).
##
## [b]Shape is per-spell identity; RATE is a player setting.[/b] That split is
## the whole reason this resource exists as authored content rather than as a
## project setting: a spell that reads as a slow artillery arc and one that
## reads as a chain of snaps differ in SHAPE, and no accessibility slider
## should be able to turn one into the other. The rate — "fast combat",
## slow-motion — is [member GameSettings.combat_time_scale], one float,
## multiplied in by [method OutcomeSchedule.compile] after every shape term.
##
## Referenced from [member SpellDef.tempo], the same pattern as
## [member SpellDef.vfx_coordinator_scene], with [b]one shared default[/b]
## ([method shared_default]) so eight spells do not mean eight copies of the
## same four numbers. Melee and ranged have no def to hang one off and simply
## take that default.
##
## [b]This is the single home of every constant that used to be duplicated
## across resolve and VFX.[/b] Before #543 the wave interval and the bolt
## lead-in each existed twice — once as a `const` in [SpellResolver] (stamped
## into [member HitInstance.arrival_time]) and once as an `@export` on
## [MagicBounceCoordinator] (driving the picture) — deliberately unwired,
## with a documented "retune either and re-check both" tax. The compiler is
## now the sole reader of these fields and the sole writer of seconds, so the
## two clocks cannot drift: there is one number.

## Shared, immutable-by-convention default. Every mode falls back to this when
## nothing authored a tempo; a spell that wants its own duplicates the `.tres`
## and edits it rather than hand-tuning constants in code.
const DEFAULT_PATH := "res://attack/outcome/default_presentation_tempo.tres"

## Seconds between magic waves — the [b]beat clock[/b]. What matters for
## correctness is only that later beats land strictly later; the absolute
## number is taste.
@export var beat_interval: float = 0.4

## Seconds a magic bolt spends in the air, added ahead of every beat — the
## [b]fourth clock's[/b] offset, and the reason it is authored rather than
## derived.
##
## Magic originally landed hits at `hop_index * beat_interval`, i.e. it omitted
## the flight, so the mutation clock ran a whole bolt-flight ahead of the
## picture: the damage number, HP bar and node tint all moved ~0.35 s BEFORE
## the projectile arrived, most visibly on the seed, which landed at t=0 with
## the bolt still in the air. Keep it. A uniform offset shifts every landing
## equally, so it reorders nothing.
##
## Must be ≤ [member beat_interval] for impact to align with the beat;
## [method OutcomeSchedule.compile] clamps rather than trusting the author.
@export var beat_lead_in: float = 0.35

## Ranged: the wind-up — the arrows animate in, parked at their leaves, before
## the first one leaves the string. An awaited presenter beat (ADR 0027), paid
## once in `_stage_windup`, never a schedule offset. 0.0 = no wind-up.
@export var volley_draw_time: float = 1.5
## Ranged: seconds the camera holds the firing-leaf CENTROID at the player's own
## zoom, at the head of the draw, before it drifts out to take in the target
## (#1048). The drift fills the rest of [member volley_draw_time]. This is the
## beat [method windup_lead] returns for [b]RANGED[/b]; 0.0 = no pivot, the
## drift lands at commit.
@export var volley_windup_pivot_focus: float = 0.25
## Ranged: seconds between one parked arrow's placement and the next during the
## wind-up — "fast": the whole volley is in place well inside the draw time.
@export var volley_place_stagger: float = 0.03
## Ranged: seconds between the nearest leaf's launch and the farthest leaf's,
## the span the volley's metric ramp lerps across.
@export var volley_stagger_span: float = 0.5
## Ranged: constant airtime for every shot. Constant on purpose — the ramp is
## authored from the volley's distance SPAN, never from `distance / speed`.
@export var volley_flight_time: float = 1.0

## [b]One shape, shared by every melee commit — seated, AI and remote alike.[/b]
## The owner refused a second seated set of numbers (2026-09-14, #865): *"AI/
## remote seated attacks should at best last more less the same, or just
## slightly faster. but the same would be fine too (more legible about what's
## coming in)"*. So there is exactly one wind-up below, and the seat predicate
## no longer reaches these values at all.
##
## Melee: seconds the camera holds the PIVOT alone, before the blade starts to
## form (#559). This is the beat the pan lives in — [CameraDirector] raises a
## point focus on the pivot at commit and widens to the attack's full span only
## after it, because the swept span IS the trajectory and exists only once the
## record does, while the pivot exists before it. #866's tracking shot consumes
## it unchanged as its pivot-lead pan.
@export var melee_windup_pivot_focus: float = 0.25

## Melee: seconds across which the blade's vertices animate in, staggered by
## HOP DISTANCE from the pivot — the nearest hop lands at 0, the farthest at
## this. Hop distance is measured inside [member BladeState.edges], the phantom
## blade's own induced subgraph (`.claude/rules/degree.md`).
##
## Retuned 2026-09-14 (#865) from 0.25 to 1.0 — with the seated path now staging
## the real sequence, the form beat is the moment the swing reads as *yours*, and
## the owner sized the whole form side at ~1.5 s: *"1s topology (or 1.5?), .5s
## upgrades, .5s glow up idk, flare .1s can tweak later"*. Provisional; the owner
## tunes these by look.
@export var melee_windup_form_span: float = 1.0

## Melee: seconds the applied addons take to "stamp" onto their vertices, after
## the form. [b]Zero-length when the blade carries no addons[/b] — an unadorned
## swing simply does not pay this beat.
@export var melee_windup_stamp_time: float = 0.5

## Melee: seconds the formed blade spends ramping from under-lit to its
## authored glow. The vertices spawn dimmed (a value dimmer, never a re-picked
## emissive float — `.claude/rules/hdr-color.md`) and come up together.
@export var melee_windup_glow_ramp: float = 0.5

## Melee: the ignition flare that marks the replay start — a momentary
## overshoot to [constant Emissive.PEAK] relaxing back down, exactly what that
## tier exists for. The last beat before the swing.
@export var melee_windup_flare: float = 0.1

## [b]Magic wind-up: caster hold → neighbour streaks → flare[/b], the same
## clamp-at-zero and all-zero escape hatch as the melee trio (ADR 0027).
## Magic: the camera's hold on the caster before the draw starts — the pivot
## beat [method windup_lead] returns for [b]MAGIC[/b].
@export var magic_windup_pivot_focus: float = 0.25
## Magic: the span across which every territory neighbour streaks its power
## into the caster (stagger = span / neighbour count) and the caster ramps.
@export var magic_windup_draw_span: float = 0.6
## Magic: the ignition flare to [constant Emissive.PEAK] before the first bolt.
@export var magic_windup_flare: float = 0.1


## Melee: seconds the whole swing occupies on screen. The blade sim's own
## duration is a SIM constant ([constant MeleeAttackPlan.SWING_DURATION]); this
## is the presentation length the normalized swing position scales into, which
## is what lets a slow-motion replay stretch the picture without re-simulating.
@export var swing_duration: float = 1.2


## The one shared instance. Loaded lazily and cached, so a headless test that
## never touches presentation pays nothing, and every caller that omits a
## tempo gets the SAME object rather than a fresh copy per attack.
static func shared_default() -> PresentationTempo:
	var res: Resource = load(DEFAULT_PATH) if ResourceLoader.exists(DEFAULT_PATH) else null
	var tempo := res as PresentationTempo
	if tempo != null:
		return tempo
	# A missing/replaced `.tres` must not take combat with it: the exported
	# defaults above are the same numbers, so this degrades to identical
	# timing rather than to zeros.
	return PresentationTempo.new()


## Total wind-up length for one committed melee swing (#559), in seconds:
## pivot focus + form + stamp + glow ramp + flare. [param has_addons] is what
## makes the stamp beat zero-length for an unadorned blade — the caller knows
## the blade, this resource only knows the shape.
##
## Every term is clamped at 0 so a negative authored value cannot run the
## sequence backwards; authoring every one of them to 0.0 reproduces
## pre-#559 behaviour exactly, which is the regression escape hatch.
func melee_windup_seconds(has_addons: bool) -> float:
	# 1 = BattleSystem.AttackMode.MELEE — see [method windup_lead] for why a literal.
	return windup_lead(1) \
			+ maxf(0.0, melee_windup_form_span) \
			+ (maxf(0.0, melee_windup_stamp_time) if has_addons else 0.0) \
			+ maxf(0.0, melee_windup_glow_ramp) \
			+ maxf(0.0, melee_windup_flare)


## Total wind-up length for one committed spell (#1043), in seconds: pivot
## focus + draw span + flare. Same clamp-at-zero per term and the same all-zero
## escape hatch as [method melee_windup_seconds]; the caster's territory degree
## only sets the stagger INSIDE the draw span, never its length, so this
## resource needs nothing from the plan.
func magic_windup_seconds() -> float:
	# 3 = BattleSystem.AttackMode.MAGIC — see [method windup_lead] for why a literal.
	return windup_lead(3) \
			+ maxf(0.0, magic_windup_draw_span) \
			+ maxf(0.0, magic_windup_flare)


## The beat BEFORE the presenter starts forming its picture — the camera's
## pivot hold, per mode (ADR 0027). Split out because two surfaces need the
## same number: [BattleSystem] delays the form by it, and [CameraDirector]
## holds the pivot focus for it before widening to the span. One reader would
## have been a constant; two is a method.
##
## One explicit arm per mode, so a mode authoring its own lead edits its own
## line: every mode's is its pivot focus (ranged's is the firing-centroid hold
## at the head of the draw, #1048; [method windup_drift] is the rest). Ranged's
## has one reader, [CameraDirector] — [BattleSystem] sizes the ranged wind-up
## off the presenter's own return, not off this.
##
## [param mode] is a [enum BattleSystem.AttackMode] value, typed [int] and
## matched on literals ON PURPOSE: this is a [Resource] script inside the
## authored `.tres` graph ([SpellDef] exports a tempo), and naming
## `BattleSystem` from here makes every script that preloads a spell or ammo
## `.tres` fail to compile with "Cannot assign a value of type Resource to
## constant" — the resource's script chain reaches BattleSystem while it is
## still mid-parse. `test_melee_staging.gd` pins the literals to the enum.
## The beat AFTER the pivot in which the camera drifts, un-followed, out to the
## span (#1048) — ranged only: nothing moves during its draw, so there is
## nothing to follow and the pan is a one-shot filling the rest of the draw.
## Zero for a mode whose wind-up is followed from commit (melee, magic): its
## widen retargets the zoom only and has no pan of its own to time.
func windup_drift(mode: int) -> float:
	match mode:
		2:  # BattleSystem.AttackMode.RANGED
			return maxf(0.0, volley_draw_time - windup_lead(2))
		_:
			return 0.0


func windup_lead(mode: int) -> float:
	match mode:
		1:  # BattleSystem.AttackMode.MELEE
			return maxf(0.0, melee_windup_pivot_focus)
		2:  # BattleSystem.AttackMode.RANGED
			return maxf(0.0, volley_windup_pivot_focus)
		3:  # BattleSystem.AttackMode.MAGIC
			return maxf(0.0, magic_windup_pivot_focus)
		_:
			return 0.0
