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

## Ranged: dead time before the first arrow leaves the string.
@export var volley_draw_time: float = 0.0
## Ranged: seconds between the nearest leaf's launch and the farthest leaf's,
## the span the volley's metric ramp lerps across.
@export var volley_stagger_span: float = 0.7
## Ranged: constant airtime for every shot. Constant on purpose — the ramp is
## authored from the volley's distance SPAN, never from `distance / speed`.
@export var volley_flight_time: float = 0.8

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
