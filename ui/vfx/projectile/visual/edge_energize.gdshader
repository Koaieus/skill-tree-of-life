shader_type canvas_item;
render_mode blend_add;

// #670 P5 — a travelling front of light laid ALONG a real edge, drawn as an
// overlay quad that paints on top of the edge and never touches it.
//
// PAINT-ON-TOP, NOT THE EDGE MULTIMESH (#670, settled). The tempting route —
// stashing energize state in a spare `INSTANCE_CUSTOM` channel of
// `graph/edge_mesh.gdshader` — is not available: all 8 per-instance floats are
// spoken for, and `.a` is a three-digit packed field (vis state + 10*self-loop
// + 100*clamp code) whose constants are mirrored in lockstep across `edge.gd`
// and that shader. Taking it would make the VFX layer a THIRD writer into a
// buffer Graph/Edge own under a two-writer discipline, and would need
// interrupt-restore semantics — a cast cut short by teardown would leave edges
// stuck energized, the exact stuck-state bug class the presentation-clock arc
// spent five issues killing. Paint-on-top is self-cleaning: the overlay frees
// itself and the edge was never touched. Do not "optimize" this into the
// MultiMesh.
//
// ONE MATERIAL FOR EVERY OVERLAY. Every uniform below is shared and static —
// authored on `edge_energize_material.tres`, never written per instance. All
// per-instance animation rides the node TRANSFORM (the ignition front is the
// quad's x-scale) and `modulate`. The moment anyone animates a per-overlay
// uniform, the material duplicates and Resonator's ~60 overlays become 60
// unbatchable draws instead of one batch. That is the single most likely
// mistake in this file.
//
// FOG-OBLIVIOUS, on purpose (owner call 2026-08-30) — matching every existing
// spell visual: `GlowingDot` bolts already fly over `FogOverlay`, and
// `AllocationVFX` z-promotes to `ZLayers.SPELL_VFX` specifically to win over
// it. A fog-aware overlay next to fog-oblivious bolts would read as a bug.
// Fog-awareness is a one-line upgrade whenever fog-gating arrives:
//   #include "res://ui/vision_field.gdshaderinc"
//   ... and multiply ALPHA by vision_field_dim(world_pos)
// which is the reader role #413 designed that file for.

// Stroke width in SCREEN pixels. Pushed once, at load, from
// `graph/edge_mesh_material.tres`'s own `width` by `EdgeEnergize._sync_width()`
// — a shared-material write, not a per-instance one — so there is no CPU
// mirror of the edge's width that can drift out of step with it.
uniform float edge_width : hint_range(0.0, 32.0) = 4.0;

// How much wider than the edge the energized overlay sits. 1.0 = exactly the
// edge's own width; above that the light spills past the stroke it rides.
uniform float width_scale : hint_range(0.5, 4.0) = 1.6;

// The SAME global uniform `graph/edge_mesh.gdshader` reads, pushed by
// `GraphCamera` on every zoom change (`scenes/camera_2d.gd`). Reading it here
// rather than mirroring a width on the CPU is what makes the overlay track the
// edge exactly, with no per-frame sync that can drift. Registered in
// `project.godot`'s `[shader_globals]` — a shader reading it before
// registration silently gets the default, not an error.
global uniform float edge_camera_zoom;

// AA feather across the stroke, in screen pixels — divided by zoom below for
// the same reason `edge_width` is.
uniform float feather_px : hint_range(0.0, 8.0) = 1.5;

// How much of the quad's length the hot leading front occupies, 0..1.
uniform float front_width : hint_range(0.02, 1.0) = 0.28;

// EV STOPS the front is lifted above the body, NOT a raw multiplier. The body
// rides `modulate`, which `EdgeEnergize` authors at `Emissive.VALUE`; one stop
// puts the front at `Emissive.ALERT` — exactly #663 D6's "resting VALUE, only
// the moving front brushes ALERT". A lit edge already carries a baked
// `Emissive.VALUE` lift (`graph/edge.gd`'s `lit_glow_stops` — a MultiMesh
// instance has no `self_modulate`, so it is baked into the pushed colour), and
// additive-on-lifted goes white fast, so the resting tier stays at VALUE and
// the overshoot is the front's alone.
uniform float front_gain_stops : hint_range(0.0, 3.0) = 1.0;

// Body brightness at the tail (the origin end) as a fraction of the front's
// body level. Below 1.0 the overlay reads as light that has already passed
// through and is settling, rather than as a uniformly lit bar.
uniform float tail_level : hint_range(0.0, 1.0) = 0.45;

// The sRGB transfer pair, exactly as `Color.srgb_to_linear` /
// `linear_to_srgb` implement it — so `front_gain_stops` means the same thing
// here that a stop means to `ui/theme/emissive.gd`. Doing the lift in sRGB
// space instead would make "one stop" a different amount of light in the
// shader than in the code, which is precisely the drift the named-tier
// discipline exists to prevent (docs/domain/hdr-color.md).
vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + vec3(0.055)) / 1.055, vec3(2.4)),
			step(vec3(0.04045), c));
}

vec3 linear_to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - vec3(0.055),
			step(vec3(0.0031308), c));
}

void vertex() {
	// Screen-constant stroke width, the same arithmetic the edge itself uses
	// (`graph/edge_mesh.gdshader`'s bar branch): the authored screen-pixel
	// width divided by the current camera zoom is the LOCAL half-width that
	// renders at a constant on-screen size at any zoom. Only the SIGN of
	// VERTEX.y survives from the source quad — the magnitude is entirely
	// zoom-derived and never inherited from the instance's own y-scale, which
	// is what leaves the y axis free and the x axis carrying the front.
	float zoom = max(edge_camera_zoom, 0.0001);
	float half_width_local = (edge_width * 0.5 * width_scale) / zoom;
	float pad_local = feather_px / zoom;
	VERTEX.y = sign(VERTEX.y) * (half_width_local + pad_local);
}

void fragment() {
	// Across the stroke: 0 at the padded edge of the quad, 1 down the spine.
	// `fwidth` gives a screen-space feather, so it stays one pixel wide at
	// every zoom without a second uniform.
	float across = 1.0 - abs(UV.y - 0.5) * 2.0;
	float across_alpha = smoothstep(0.0, max(fwidth(across) * 2.0, 0.001), across);

	// Along the stroke: the front sits at the LEADING end (uv.x == 1), which is
	// where the quad grows to. Behind it the body settles toward `tail_level`.
	float front = smoothstep(1.0 - front_width, 1.0, UV.x);
	float body = mix(tail_level, 1.0, UV.x);

	vec3 lin = srgb_to_linear(COLOR.rgb) * exp2(front_gain_stops * front);
	COLOR.rgb = linear_to_srgb(lin);
	COLOR.a *= across_alpha * body;
}
