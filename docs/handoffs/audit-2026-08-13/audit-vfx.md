# Audit — VFX / effects / theme / overlays slice

Scope read in full: `ui/vfx/**`, `effects/**`, `ui/announcement_layer/**`,
`ui/theme/**`, `ui/floating_number_layer/**`, `ui/aura_overlay/**`,
`ui/fog_overlay/**`, plus every `.gdshader` and composing `.tscn`/`.tres`.
Rules read: `hdr-color`, `rendering-performance`, `spell-vfx`, `scene-composition`,
`skill-node-scale`, `gdscript-pitfalls`, `ui-palette` + their `docs/domain/` targets.

---

## A. HDR / emissive migration inventory (owner's headline concern)

Every glow-ish visual in this slice. "Real" = goes through `Emissive.at()`/`tint()`,
a `Tier*` theme variation, or the shader-side `emissive_at()` twin. "Fake" = a
hand-picked float, a gradient, a shadow, or an extra outline pass standing in for bloom.

| # | Visual | File | Glow authored as | Verdict |
|---|---|---|---|---|
| 1 | Projectile head + halo | `ui/vfx/projectile/visual/glowing_dot.gd:25-26` | `Emissive.at(…, VALUE/LABEL)` | **real** |
| 2 | Crit flash | `glowing_dot.gd:40` | `Emissive.at(…, ALERT)` | **real** |
| 3 | Arrow shaft/head/halo | `light_arrow.gd:82-83` | `Emissive.at(…, VALUE/LABEL)` | **real** |
| 4 | Alloc spike + disk | `allocation_vfx.gd:248,257` | `Emissive.at(WHITE, PEAK)` on `modulate` | **real** |
| 5 | Dealloc lift "holy puff" | `allocation_vfx.gd:301` | tween to raw `Color(1,1,1,1)`; comment claims "the bloom reads" | **fake** (1.0 == threshold, never blooms) |
| 6 | Shatter / pop particle burst | `allocation_vfx.gd:368-373` | raw entity `Color` + SDR `Gradient` ramp | **fake** (the exact `Gradient` case `Emissive`'s own docstring names) |
| 7 | Shatter "glow ramp" | `allocation_vfx.gd:326` | comment only — no glow term exists in the code | **absent** (stale comment) |
| 8 | CANCEL dissipate ring | `cancel_dissipate.gd:11` | `Color(1.0, 0.4, 0.4, 0.85)` hand-picked | **fake** |
| 9 | Strikethrough hot tip + cut line | `strikethrough_toast.gd:46-64` | `Emissive.at(base, ALERT)` pushed to uniforms | **real** |
| 10 | Toast "glow" style | `floater_toast.gd:62-66` | `LabelSettings.shadow_color`, offset 0, size 10 — "a shadow reads as a glow" | **fake** (live path) |
| 11 | Legacy floater "glow" | `floater.gd:84-89` | "Fake a bloom by stamping a wide translucent outline pass" | **fake** (and dead, see F16) |
| 12 | Floater palette (damage/heal/mythic/XP) | `floater_styles.gd:17-23` | hand-picked SDR constants | **fake/absent** |
| 13 | Callout band mode tint | `callout_band.gd:109-112` | hand-picked SDR copies of `StatDef.tint_color` | **fake/absent** |
| 14 | Fused panel edge glow | `fused_panel.gd:42` + `fused_panel.gdshader:emissive_at` | `glow_energy` EV stops, shader-side piecewise twin | **real** |
| 15 | Glass panel inner glow | `glass_panel.gdshader:29-31` | `mix()` toward `glow_color` (SDR) | **fake** |
| 16 | Holo panel rim glow | `holo_panel.gdshader:55-57` | `mix()` toward `glow_color` (SDR) | **fake** |
| 17 | Scanline overlay lines | `holo_scanline_overlay.gdshader:38-40` | additive `line_color × intensity` (SDR) | **fake** |
| 18 | Fog frontier halo | `fog.gdshader:33,88` | `glow_color = vec3(1.0,0.9,0.6)`, `glow_strength ≤ 2` applied to *alpha*, never to a >1.0 colour | **fake** (a halo that cannot bloom) |
| 19 | Aura territory wash | `aura.gdshader` | entity tint × `intensity 0.15` | **n/a** (deliberately sub-threshold wash — correct) |
| 20 | `Emissive.tint_peak` / `tint_damped` | `emissive.gd:116,136` | — | **dead** (self-labelled "CANDIDATE, not yet adopted") |

Score: 6 real, 10 fake/absent, 1 n/a, 1 dead API. **Every real one is in
`ui/vfx/projectile/visual/` or `strikethrough_toast` — the two places touched
after #371 landed.** Everything authored before it (panels, fog halo, floaters,
callouts, allocation particles) is still SDR. The migration stopped at the
projectile layer.

---

## B. Findings

### 1. LARGE | ui/theme/glass_panel.gd:52 | Two live panel systems, migration stalled
**Defect:** `FusedPanel` (#391: one static shared `ShaderMaterial` + instance uniforms + `emissive_at`) is used by `ui/tooltip_fan/**` only, while every HUD scene — action_cluster, attributes_panel, all five combat cards, command_tray, hero_sigil_card, node_inspector_card, turn_resources_panel, xp_track, initiative_bar, end_turn_button — still instantiates `GlassPanel`, which `preload(...).duplicate()`s a material per instance and has no HDR path at all.
**Breaks:** The HUD can never bloom its panel borders while the tooltip fan does, so the two halves of the same "Arcane Terminal" look drift visibly; and every panel-shader tuning decision now has to be made twice, in a shared material and in 15 scene-local duplicates.
**Fix:** Finish #345 — reparent `GlassPanel` onto `fused_panel.gdshader` (its uniform set is a strict superset: gradient, border, corner, glow) and delete `glass_panel.gd`/`.gdshader`/`_material.tres`, keeping `glow_strength` as an instance uniform.

### 2. LARGE | effects/tag_aura_effect.gd:84 | Three parallel aura mechanisms
**Defect:** `AuraEffect` and `TagAuraEffect` are ~70 lines of verbatim duplication (`_mirror`, `_distances`, `_bound`, the four `_on_*` hooks, the `recompute` skeleton, the origin-rule comment) differing only in `ctx.grant_scaled(m, s, node)` vs `ctx.grant_tag(tag, node)`; `CoreAura`/`HealAura` is then a *third* aura path with its own hardcoded hop-linear falloff, its own `HopRangeFinder` BFS and its own `base`/`range` knobs, dispatched from `Entity._on_turn_started` instead of the effect hooks.
**Breaks:** A fix to the reach/metric/scale semantics (or the freed-node guard) has to be made in three places and will silently be made in one; `CoreAura` cannot compose with the `reach`/`metric`/`distance_scale` vocabulary the design doc built for exactly this.
**Fix:** Extract a `RadiatingEffect` base owning `scope`/`reach`/`metric`/`distance_scale` + `recompute`, with one abstract `_apply_at(ctx, node, scale)`; re-express `HealAura` as a `RadiatingEffect` whose `_apply_at` calls `node.heal_damage`, and delete `CoreAura`'s parallel BFS.

### 3. LARGE | ui/vfx/coordinator/magic_bounce_coordinator.gd:103 | Drain loop can end before later beats fire
**Defect:** `play()` starts `_play_three_clocks()` **without awaiting it** and then waits on `while pending[0] > 0`, so `play()` returns as soon as the currently-in-flight projectiles drain — not when the timeline is exhausted; with `launch_to_impact` well under `beat_interval` (legal per the export doc: only `≤` is required) wave N's projectiles die during the `interval - flight` gap, `pending` hits 0, and `AttackVFX.play` `queue_free`s the coordinator mid-sequence.
**Breaks:** Remaining beats — and the `take_damage`/`heal_damage` lambdas hanging off their `arrived` signals — never run; the same truncation happens on the first frame if every event in beat 0 has a null `origin`/`target` (each `_play_projectile` returns before incrementing `pending`), which a cascade-freed node produces.
**Fix:** `await _play_three_clocks(...)` before the drain loop, and seed `pending` with the total event count up front rather than incrementing per successful spawn.

### 4. LARGE | effects/effect_context.gd:12 | Verdict on the "review all these splits" TODO
**Defect:** The three-way split is right in principle (shared stateless `Effect` definition / per-grant `EffectInstance` ledger / per-grant `EffectContext` façade) but the seam is in the wrong place: `EffectInstance` owns `_grants` yet exposes it as untyped `Array[Dictionary]` rows carrying a `&"kind"` string, and `EffectContext` re-does the polymorphism by hand — the identical `if row.get(&"kind") == &"tag": _apply_tag(...) else: _detach(...)` switch appears in both `revoke()` (`:106`) and `revoke_all()` (`:119`).
**Breaks:** Every new grant channel (an added tag-like resource, a spell grant, a timed buff) means a third copy of that switch plus a new dictionary key nobody type-checks; `EffectContext` is also not a context — it holds no state beyond `(entity, instance)` and every property is a forwarding getter, so "where does a grant live" has no single answer.
**Fix:** Give `EffectInstance` typed rows — a `Grant` base with `ModifierGrant`/`TagGrant` subclasses each owning `apply(entity)`/`revert(entity)` — so `revoke`/`revoke_all` become `row.revert(entity)`, and let `EffectContext` shrink to the read-only view (`source_node`/`navigator`/`core_location`/`graph`) it actually is.

### 5. MEDIUM | ui/vfx/coordinator/magic_bounce_coordinator.gd:81 | `Beat` class declared, never instantiated
**Defect:** The `Beat` inner class (with `wave`/`events` fields) is dead — nothing ever constructs it — while the real data is three parallel untyped structures (`waves: Dictionary`, `beats: Array`, `pending: Array[int]`) threaded through four methods, with `int(beats[i])` re-casts and double dictionary lookups at `:114-124`.
**Breaks:** The wave/beat/pending trio has no type checking anywhere, and the `Array[int]` is a boxed-int hack purely to fake pass-by-reference into `_play_event`.
**Fix (the decomposition the TODO asks for):** (a) make `Beat` real — `static func Beat.group(timeline) -> Array[Beat]` returning `index`-sorted beats, collapsing `waves`+`beats` into one typed ordered list; (b) delete `pending: Array[int]` — the coordinator is a per-action node freed right after `play()`, so a plain `var _pending: int` member plus a `_drain()` coroutine is safe and typed; (c) see finding 6 for the third structure.

### 6. MEDIUM | ui/vfx/coordinator/magic_bounce_coordinator.gd:206 | Verb→asset mapping is 8 exports and 2 match ladders
**Defect:** Six per-verb `@export`s plus two legacy fallbacks feed two near-identical `match` ladders (`_resolved_path` `:206`, `_resolved_visual` `:228`) and a third one-line accessor (`_resolved_cancel_visual`).
**Breaks:** Adding a `PropagationEvent.Verb` means two new exports and edits in two ladders, and nothing makes the path/visual pair cohere — an asset set is spread across six inspector slots that can be filled inconsistently.
**Fix:** `@export var verb_bindings: Array[VerbBinding]` (`verb`, `path`, `visual`) — the exact pattern `AnnouncementVariantBinding` already uses in this slice — with one `Dictionary[Verb, VerbBinding]` built at `play()`.

### 7. MEDIUM | ui/theme/glass_panel.gdshader:29 | Panel glow terms are SDR-only
**Defect:** `glass_panel`, `holo_panel` and `holo_scanline_overlay` all mix/add their `glow_color`/`line_color` at SDR magnitude; only `fused_panel.gdshader` carries the `emissive_at()` twin of `Emissive.at()`.
**Breaks:** Per `.claude/rules/hdr-color.md` a thing glows iff it exceeds 1.0 linear, so every HUD panel's "glow" and every scanline is a highlight the bloom pass never sees — the Arcane Terminal's signature edge light is missing on the whole HUD.
**Fix:** Fold these into `fused_panel.gdshader` (finding 1); if `holo_panel` must survive for the fan-trace sandbox, give it the same `glow_energy` instance uniform and `emissive_at()` include.

### 8. MEDIUM | ui/fog_overlay/fog.gdshader:88 | The frontier "halo glow" cannot glow
**Defect:** `halo` is applied only to *alpha* (`halo_alpha = halo * 0.6`) and to `color = glow_color * halo` where `glow_color` is a `source_color` capped at `vec3(1.0, 0.9, 0.6)` — a value that by construction sits at or below the bloom threshold.
**Breaks:** The vision frontier — the one place the fog is supposed to feel lit — renders as a flat cream band; and per `Emissive`'s own house rule ("alpha is the fade channel, colour value is the dimmer") driving the effect through alpha guarantees it emits *less*, not more.
**Fix:** Author `glow_color` as an `Emissive.at(base, ALERT)` value (or add the shader's `emissive_at()` and a `glow_energy` uniform), and keep `halo` on the colour term rather than the alpha term.

### 9. MEDIUM | ui/floating_number_layer/floater_toast.gd:62 | Live toast glow is a text shadow
**Defect:** `_apply_style` implements `FloaterStyle.glow` as `settings.shadow_color = style.glow_color; shadow_size = 10; shadow_offset = ZERO` — the comment even says "an offset-less shadow in the glow colour reads as a glow" — and `floater_styles.gd`'s whole palette (`COLOR_MYTHIC`, `COLOR_XP`, …) is hand-picked SDR.
**Breaks:** This is the glow on the *mythic/build-defining* modifier toast and every XP toast — the loudest moments in the floater vocabulary read flatter than a projectile trail, which does bloom.
**Fix:** Drop the shadow trick; set `settings.font_color = Emissive.at(style.fill_color, Emissive.VALUE)` (and `ALERT` for the mythic/core variant), letting the real bloom pass do the halo.

### 10. MEDIUM | ui/announcement_layer/callout_band.gd:111 | Answer: `StatDef` is the right home; this is a copy of it
**Defect:** The three mode colours are byte-identical copies of `strength.tres` / `dexterity.tres` / `intelligence.tres`'s `tint_color` (`Color(0.9451, 0.2689, 0.2453)` etc.), pasted into a `match`; a fourth copy of the STR red is also baked into `callout_band.tscn`'s `theme_override_colors/font_color`, which `_apply_style` then overwrites at runtime.
**Breaks:** `.claude/rules/ui-palette.md` names `StatDef.tint_color` the single source of truth precisely so a palette retune propagates; today a retune leaves the combat callouts on the old hue, and the scene-authored override makes the editor preview lie about which colour ships.
**Fix:** `StatRegistry.get_def(&"strength").tint_color` wrapped in `Emissive.at(..., Emissive.VALUE)` — `StatDef` for identity, `Emissive` for the tier; not a new theme table, and drop the `.tscn` colour override.

### 11. MEDIUM | ui/aura_overlay/aura_overlay.gd:88 | Full territory rebuild per allocation signal
**Defect:** `_refresh` is wired to `allocated` / `deallocated` / `force_deallocated` and each call walks **every** `SkillNode` in the graph, re-buckets by owner, repacks the circle array, rebuilds `OverlayFieldTileIndex` and re-uploads three data textures.
**Breaks:** At the documented 500–2500-node scale a forced-dealloc cascade of K nodes emits K signals and pays K full O(N) rebuilds plus K texture uploads — quadratic work at the exact moment the game is also running the shatter VFX; nothing coalesces the burst.
**Fix:** Make `_on_ownership_changed` set a dirty flag and `call_deferred` a single `_refresh` per frame (the pattern `AnnouncementLayer.enqueue` already uses for its same-frame bursts).

### 12. MEDIUM | ui/fog_overlay/fog_overlay.gd:159 | #413's self-shading migration covers edges only
**Defect:** `_apply_per_element_dimming` still walks every `SkillNode` every refresh — writing `modulate.a`, `z_as_relative` and `z_index` per node — while regular edges were moved to per-fragment self-shading against the `vision_field` globals; `fog.gdshader`'s own header calls the SkillNode half "pending their own #413-style follow-up".
**Breaks:** `_refresh` is connected to `vision_render_tick`, i.e. per frame while circles animate, so the per-node CPU pass (the thing `VisionSourceIndex` exists to make survivable) runs at frame rate over the whole board and the two halves of fog rendering use two different, hand-synced darkness computations.
**Fix:** Finish the migration — give `SkillNode`'s visuals the same `vision_field.gdshaderinc` self-shading term edges got, leaving only the visible/sensed classification on the CPU.

### 13. MEDIUM | ui/floating_number_layer/strikethrough_toast/strikethrough_toast.tscn:9 | Animated uniform state baked into the scene
**Defect:** The scene's `ShaderMat_svc` carries `gray_amount = 1.0` and `strike_x = 0.558` — mid-animation values serialized back into the authored resource — while `_run_strike` only starts tweening from 0.0 after `fade_in_duration`.
**Breaks:** Every removed-modifier toast renders fully desaturated with the cut already half-drawn for its first `fade_in_duration` (0.2 s authored), then snaps back to colour when the tween starts — the animation reads backwards.
**Fix:** Reset both uniforms to 0.0 in the `.tscn`, and set them explicitly in `_ready` so an editor resave can't reintroduce the drift (`.claude/rules/gdscript-pitfalls.md`, "never write a derived value back into an `@export`" — same failure mode, one layer down).

### 14. MEDIUM | ui/floating_number_layer/strikethrough_toast/strikethrough_toast.gd:7 | #393: today's structure cannot express a laser cutter
**Defect:** The tip glow's *alpha* is gated by glyph or line coverage — in the transparent-gap arm the shader writes `line_a = on_line * struck * gray_amount * base_col.a` and only uses `heat_norm` for the RGB mix (`strikethrough.gdshader:~105`), so off the cut line and off the glyphs the tip contributes zero alpha; the material is also on the `Label`, whose rect is exactly the text bounds, so nothing can bleed past the text.
**Breaks:** A "blooming laser cutter" needs a round emissive blob that exists where there is no ink and that over-travels the label edge; both are structurally impossible today, which is why the current result reads as a static line no matter how the tiers are retuned. (The docstrings claim a `SubViewportContainer` renders the label — there is no `SubViewport` in the scene at all; the material sits on the `Label`.)
**Fix:** Add `heat_norm` to the alpha term in the gap arm, host the material on a padded parent `Control` (or a real SubViewportContainer, as the docstring already assumes) so the halo has margin to bloom into, and correct the two stale docstrings.

### 15. MEDIUM | ui/vfx/allocation_vfx.gd:241 | Five VFX trees code-composed instead of scenes
**Defect:** `_spawn_alloc_spike`, `_spawn_lift`, `_spawn_shatter`, `_spawn_pop_burst` and `_emit_burst` build `Node2D` / `Polygon2D` / `CPUParticles2D` / a private `_SnapshotDisk` by hand with ~25 property assignments each, plus 20 tuning constants at the top of a 430-line file.
**Breaks:** Directly against `.claude/rules/scene-composition.md` — none of these five effects can be previewed, tuned in the inspector, or reused, and every tuning change is a code edit; it is also why they were all missed by the HDR migration (rows 5–7 of the inventory).
**Fix:** One `.tscn` per effect (`alloc_spike`, `dealloc_lift`, `shatter`, `pop_burst`) with the constants as `@export`s, instantiated by a slim `AllocationVFX` that keeps only the signal wiring and cascade stagger.

### 16. MEDIUM | ui/floating_number_layer/floater.gd:2 | Dead legacy floater path
**Defect:** `Floater` + `floater.tscn` have zero references anywhere (the pipeline is `FloaterDirector → FloaterToasterManager → FloaterToaster → FloaterToast` since #81); `FloaterStyle.float_distance` and `max_angle` are documented as "not consumed by the current pipeline"; `FloaterToasterManager.spawn_simple`, `AnnouncementLayer.enqueue_now` and `AnnouncementLayer.clear` have no callers.
**Breaks:** 92 lines of a second, differently-shaped floater (drift + wiggle + fake bloom) sit next to the real one, and two `FloaterStyle` fields invite a caller to set knobs that do nothing.
**Fix:** Delete `floater.gd`/`.tscn` (sweep the `.uid`s per `.claude/rules/godot-workflow.md`) and the two dead style fields; keep `enqueue_now`/`clear` only if a caller is imminent.

### 17. MEDIUM | ui/aura_overlay/aura_overlay.tscn:8 | Dead pre-#177 uniform arrays in both overlay scenes
**Defect:** `aura_overlay.tscn` and `fog_overlay.tscn` each still serialize a 256-entry `shader_parameter/circles = [Vector4…]` array for a uniform neither shader declares any more (#177 moved circles to data textures); `aura_overlay.tscn` additionally writes `shader_parameter/intensity` **twice** (0.6 then 0.15).
**Breaks:** Two scene files are dominated by dead data — the aura scene is one 8 KB line — so any real diff to them is unreviewable, and the duplicated key means the file no longer states unambiguously what the material is set to.
**Fix:** Strip both `circles` arrays and the duplicate `intensity`, then `mise run refresh` and commit the churn once.

### 18. MEDIUM | ui/vfx/allocation_vfx.gd:326 | Shatter builds ~48 chained tween steps per node
**Defect:** The vibrate phase creates `int(0.8 * 60) = 48` sequential `tween_property` steps per shattered node, each a separate tweener object, to hand-keyframe a sine wiggle.
**Breaks:** A cascade shattering K nodes allocates ~48 K tweeners in one frame at the same moment finding 11's O(K·N) aura rebuild is running — both on the CPU, both avoidable.
**Fix:** One `tween_method` over `0→1` computing the sine offset in the callback (or a `_process` on the effect scene from finding 15), which is one tweener instead of 48.

### 19. MEDIUM | ui/announcement_layer/callout_band.gd:114 | Style re-applied per play, duplicating the scene
**Defect:** `_apply_style` constructs a fresh `StyleBoxFlat` and re-pushes `outline_size`, `font_outline_color` and both alignments on every `play()` — all four already authored in `callout_band.tscn`, and the `StyleBoxFlat` there is identical to the one built in code.
**Breaks:** Two sources of truth for the band's chrome: editing the scene has no effect at runtime, and a `StyleBoxFlat` is allocated per announcement.
**Fix:** Keep the scene's stylebox and constants; let `_apply_style` write only the one thing that varies — the font colour.

### 20. NIT | ui/theme/emissive.gd:116 | Two unadopted tier variants shipped as API
**Defect:** `tint_peak` and `tint_damped` are both labelled "CANDIDATE, not yet adopted anywhere" and carry 20 lines of docs each; only `at()` (18 call sites) and `tint()` (1, `slab_panel.gd`) are used.
**Breaks:** The class doc says the tier vocabulary is the discipline, but a reader now has four near-identical entry points with no rule for choosing between them.
**Fix:** Move the two candidates into `docs/domain/hdr-color.md` as prose + the bloom-sandbox comparison, and delete them from the shipped class until one wins.

### 21. NIT | effects/core_aura.gd:27 | `range` shadows GDScript's built-in
**Defect:** `@export var range: float` makes the global `range()` function unreachable inside `CoreAura` and every subclass.
**Breaks:** `HealAura` or a future subclass cannot write `for i in range(n)` — a silent-until-you-hit-it trap; `DistanceScale`'s own docstring calls out exactly this class of shadowing (of `Gradient`) as a footgun worth avoiding.
**Fix:** Rename to `hop_range` (it is documented as a hop distance anyway).

### 22. NIT | ui/vfx/coordinator/magic_bounce_coordinator.gd:189 | CANCEL visual assumed to be `Node2D`
**Defect:** `_play_cancel` instantiates an untyped `Node` from the `cancel_visual` export and immediately writes `node.global_position`.
**Breaks:** A `Control`-rooted or plain-`Node`-rooted override scene crashes at runtime instead of being rejected at bind time — the export's type says only `PackedScene`.
**Fix:** `var node := scene.instantiate() as Node2D` with a `push_warning` + early return on null, mirroring `AttackVFX.play`'s coordinator cast.

### 23. NIT | ui/announcement_layer/announcement_layer.gd:26 | Three parallel untyped dictionaries keyed by Kind
**Defect:** `_bands`, `_queue_by_kind` and `_current_by_kind` are bare `Dictionary` with the key type only in a trailing comment, and must be kept in lockstep by hand across `_ready`, `enqueue`, `enqueue_now`, `_pump` and `_on_band_finished`. The same untyped-collection pattern recurs at `magic_bounce_coordinator.gd:135` (`_group_by_beat`), `floater_toaster_manager.gd:29` (`_toasters`) and `aura_overlay.gd:152` / `fog_overlay.gd:98` (`Array` of untyped circle/source dicts).
**Breaks:** Adding a `Kind` means remembering three initializations in `_ready`; a missed one surfaces as `push_error("no band bound")` at runtime rather than a parse error.
**Fix:** One `Dictionary[Kind, BandSlot]` where `BandSlot` holds `band`/`queue`/`current` — one initialization site, one typed lookup.

### 24. NIT | ui/vfx/projectile/visual/glowing_dot.gd:63 | Trail sampled on the render clock, filtered every frame
**Defect:** `_on_progress` appends a `Vector3` per frame with no distance or rate gate, and `_process` compacts the whole `PackedVector3Array` every frame, then `_draw` walks it again with a `draw_circle` per segment.
**Breaks:** At 144 fps a 0.45 s trail is ~65 segments = 65 draw calls per projectile, and a branchy spell stacks projectiles by design (the clock contract's whole point) — the per-frame cost scales with refresh rate rather than with the authored look.
**Fix:** Gate appends on a minimum world-space step, and draw the trail as one `draw_polyline_colors` instead of N circles.

### 25. NIT | ui/theme/scanline_overlay.gd:43 | Third `_push`-to-shader clone with one user
**Defect:** `ScanlineOverlay`, `GlassPanel` and `HoloPanel` each reimplement the identical `_ready` → `duplicate()` material → `resized.connect(_push_size)` → `_push(param, value)` boilerplate; `ScanlineOverlay` is referenced by nothing but its own scene and one test.
**Breaks:** Three copies of a pattern `FusedPanel` has already replaced with instance uniforms — and one of them is scaffolding no scene uses.
**Fix:** Fold into finding 1's migration; if the overlay is still wanted, it is a `FusedPanel` with fill alpha 0.

---

## Verdict

The projectile/path/visual layer is genuinely well modelled — `Projectile` +
`ProjectilePath` + duck-typed visual is a clean three-axis composition, and it is
also the only part of the slice that finished the HDR migration. Everything
around it shows the same shape of debt twice over: a newer, better mechanism was
built beside an older one and the old one was never retired — `FusedPanel` beside
`GlassPanel`, self-shading edges beside CPU-dimmed nodes, `AuraEffect` beside
`CoreAura`, `FloaterToast` beside `Floater` — so this slice currently carries four
parallel systems, and the "bloom is under-applied" symptom is mostly just the old
half of each pair still being visible. `MagicBounceCoordinator`'s self-flagged TODO
is real and hides an actual truncation bug (finding 3), not merely untidy state.
The `effects/` composition vocabulary (reach × metric × scale) is the best-designed
thing here and deserves to absorb `CoreAura` rather than coexist with it.
