// The segment sweep shared by the segmented gauges — pool_gauge.gdshader
// (AP/DP/Move batteries, plus SurplusPoolStat's trailing cells) and
// composite_bar_gauge.gdshader (the Skill Points composition bar). One
// implementation of the partial cell, the crossing-cell lift and the HDR
// math, driven from GaugeSpark (ui/gauges/gauge_spark.gd).
//
// A gauge's displayed value tweens toward the model at a constant per-cell
// step (#882). Nothing here knows about time: every boundary the gauge draws
// is a continuous position IN CELLS, and each fragment classifies itself by
// its own continuous position along the strip (`strip_pos`), so the cell a
// boundary is passing through is drawn as a partial cell for free — anchored
// at the fill origin, slanted like its neighbours, with the slot's resting
// state showing behind the receding edge. While a sweep runs the strip is hot
// (`spark_energy` 1.0) and the cell the moving boundary is crossing burns at
// `spark_stops`; once it lands the lift cools to the gauge's resting glow.
//
// Param names are underscore-prefixed on purpose: Godot's shader codegen
// rewrites *uniform tokens* even inside included function bodies, so a
// parameter named `cell_gap` would be silently substituted at the call site's
// uniform. Same reason as round_rect.gdshaderinc.

// 1.0 for the whole of a sweep, cooling to 0.0 after the last one lands.
uniform float spark_energy = 0.0;
// Which of the gauge's boundaries is (or was last) sweeping — a per-shader
// enumeration (the pool battery: 0 = the fill edge, 1 = the surplus edge; the
// SP bar: 0..3 = its four run boundaries). Only that boundary's crossing cell
// lifts; a boundary that happens to sit at rest inside a cell does not.
uniform float spark_edge = 0.0;
// 1 = that boundary's run is LEAVING (a spend, a heal): only the receding
// partial cell burns, and there is nothing left to cool on once it is gone.
// 0 = ARRIVING: the growing partial cell burns and, once it lands, the cell it
// just completed cools — the "it arrived" beat.
uniform float spark_out = 0.0;
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

// This fragment's continuous position along the strip, in cells: its slot
// index plus how far it sits across the slot's INNER span (the gap halves
// excluded, so a boundary at an integer lands exactly on a slot edge and a
// boundary at k.5 splits the visible cell in half, not the slot-plus-gap).
float strip_pos(float _idx, float _local_x, float _cell_w, float _gap) {
	float _half = _gap * 0.5;
	float _inner = max(0.001, _cell_w - _gap);
	return _idx + clamp((_local_x - _half) / _inner, 0.0, 1.0);
}

// Whether the slot at `_idx` is the one a boundary at `_edge` (in cells) is
// crossing — the cell the edge is strictly inside — or, for an arriving run
// that has come to rest on the slot's far side, the last cell it filled, so
// the cooling after a fill has a cell to cool on. A leaving run gets no such
// tail: the cell beside the one that just went is not the story. Whole-cell so
// the lift reads as "this segment". Only meaningful while hot.
bool spark_hits(float _idx, float _edge) {
	if (spark_energy <= 0.001 || _edge <= _idx + 0.001) {
		return false;
	}
	return spark_out > 0.5 ? _edge < _idx + 0.999 : _edge <= _idx + 1.001;
}

// Whether a boundary at `_edge` is strictly inside the slot at `_idx` right
// now — a partial cell, whichever direction it is going and whether or not it
// is the named `spark_edge`. A gauge with several boundaries moving at once (a
// SP transfer walks two) lights every partial cell with this and keeps
// spark_hits for the named edge's cool tail.
bool spark_crossing(float _idx, float _edge) {
	return spark_energy > 0.001 && _edge > _idx + 0.001 && _edge < _idx + 0.999;
}

// The crossing cell's own colour, lifted to `spark_stops` by the current heat —
// a spent Move cell ignites in the Move tint, a surplus cell in gold.
vec3 spark_lift(vec3 _own) {
	return mix(_own, lift_peak(_own, spark_stops), spark_energy);
}
