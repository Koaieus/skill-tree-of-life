// The ignition spark shared by the segmented gauges — pool_gauge.gdshader
// (AP/DP/Move batteries, plus SurplusPoolStat's trailing cells) and
// composite_bar_gauge.gdshader (the Skill Points composition bar). One
// implementation of the band, the geometry and the HDR lift, driven from
// GaugeSpark (ui/gauges/gauge_spark.gd).
//
// A cell that just changed hands burns at `spark_stops` and cools to the
// gauge's resting glow as `spark_energy` runs 1 -> 0. `spark_out` says which
// way it is going; `spark_anchor_right` says which edge of its own slot it
// grows out of and collapses back into.
//
// Param names are underscore-prefixed on purpose: Godot's shader codegen
// rewrites *uniform tokens* even inside included function bodies, so a
// parameter named `cell_gap` would be silently substituted at the call site's
// uniform. Same reason as round_rect.gdshaderinc.

// Band of strip cell indices currently burning, as [spark_lo, spark_hi).
// Indices are into the RENDERED strip, not the model's units — the pool
// battery's strip mixes the cap's cells with SurplusPoolStat's trailing ones,
// and the SP bar's mixes four buckets.
uniform float spark_lo = 0.0;
uniform float spark_hi = 0.0;
uniform float spark_energy = 0.0;
// 1 = the cells are LEAVING (spent, healed away): drawn in spark_color, then
// collapsed. 0 = ARRIVING: grown in hot, then settled into their own colour.
uniform float spark_out = 0.0;
// Which edge of its slot a cell grows out of and collapses back into. 0 = the
// left edge — the fill direction, so the batteries and the blue to-spend run
// both originate from the left. 1 = the right edge, for the trailing
// wounded/staked runs, which originate from the right.
uniform float spark_anchor_right = 0.0;
// The colour of the state on the OTHER side of the change — the bin a leaving
// cell came from, or the one an arriving cell is displacing. The fragment can
// never compute it for itself: by the time it draws, a spent SP cell already
// reads as allocated and an arriving cell already reads as filled.
//
// The slot always draws at full width. The spark only decides which of the two
// states each half of it shows, so the cell a fill is eating into (or the empty
// slot a spend is uncovering) stays on screen the whole time instead of blinking
// out from under the animation.
uniform vec4 spark_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float spark_stops : hint_range(0.0, 3.0, 0.05) = 2.5;

// `_base` lifted to `_stops` EV, normalized by its PEAK channel —
// Emissive.tint_peak(), not .tint(). Luminance normalization would drag a
// saturated red's green/blue to ~1.0 and the result would read white with a
// coloured halo. `source_color` uniforms arrive already linear under HDR 2D, so
// the divide and the lift are the whole conversion — do NOT add an sRGB round
// trip here (docs/domain/hdr-color.md).
vec3 lift_peak(vec3 _base, float _stops) {
	vec3 _c = max(_base, vec3(0.0));
	float _peak = max(_c.r, max(_c.g, _c.b));
	if (_peak < 0.0001) {
		return vec3(0.0);
	}
	return (_c / _peak) * pow(2.0, _stops);
}

bool spark_hits(float _idx) {
	return spark_energy > 0.001 && _idx >= spark_lo - 0.001 && _idx < spark_hi - 0.001;
}

// How much of its slot a burning cell fills, 0..1. A leaving cell holds at full
// for the first breath and then pulls in — a spend should read as "that one
// just went", not as a cell that was already half gone. An arriving one snaps
// open over the first half of the burn and spends the rest just cooling.
float spark_extent() {
	return spark_out > 0.5
			? clamp(spark_energy * 1.4, 0.0, 1.0)
			: clamp((1.0 - spark_energy) * 2.0, 0.0, 1.0);
}

// The [near, far] horizontal window the CHANGING state occupies inside a slot;
// whatever is left of the slot shows the state on the other side of the change.
// `_extent` of 1.0 covers the whole slot, so a gauge can call this
// unconditionally and get its resting appearance back.
vec2 spark_cell_window(float _cell_w, float _gap, float _extent) {
	float _half = _gap * 0.5;
	float _span = max(0.0, _cell_w - _gap) * clamp(_extent, 0.0, 1.0);
	if (spark_anchor_right > 0.5) {
		return vec2(_cell_w - _half - _span, _cell_w - _half);
	}
	return vec2(_half, _half + _span);
}


// Composite one fragment of a burning cell. `_own` is what the gauge computed
// for it — which is the POST-change state, so it is the arriving colour on the
// way in and the vacated slot on the way out. The other side of the change is
// `spark_color`, and the window says which of the two this fragment falls in.
// Only the changing state takes the HDR lift; the state it is displacing sits
// there at its resting value.
vec4 spark_blend(vec4 _own, float _local_x, vec2 _window) {
	bool _leaving = spark_out > 0.5;
	if (_local_x < _window.x || _local_x > _window.y) {
		return _leaving ? _own : spark_color;
	}
	vec4 _hot = _leaving ? spark_color : _own;
	_hot.rgb = mix(_hot.rgb, lift_peak(_hot.rgb, spark_stops), spark_energy);
	return _hot;
}
