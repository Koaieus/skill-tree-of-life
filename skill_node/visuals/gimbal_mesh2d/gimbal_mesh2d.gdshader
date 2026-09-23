shader_type canvas_item;
render_mode blend_mix, unshaded;

#include "res://ui/vision_field.gdshaderinc"

// Shape-B gimbal (#1075): the whole quaternion chain of `gimbal_3d.gd`
// (AXES RIGHT/UP alternating, RATE_BASE, standing tilts, chain index 0 =
// outermost) evaluated per vertex from TIME, then orthographically projected
// onto the canvas. Two passes over ONE MultiMesh: `front_pass` 0 keeps the
// half behind the disk (z < 0), 1 keeps the half in front (z >= 0).
//
//   CUSTOM0 = (cos a, sin a, radial 0/1, ring index)   CUSTOM1 = (axial ±1, is_rim, n sign, -)
//   INSTANCE_CUSTOM = (phase, spin_speed, ring_count, style 1 glass / 2 glyph)
//   COLOR = HDR tint (Emissive tier, written by GimbalBatch)
// Ring radius depends on ring_count (depth = ring_count-1-index), so it is
// computed here, not baked. z is +toward the viewer.

uniform float front_pass = 1.0;
uniform float band_width = 0.22;
uniform float thickness = 0.06;
uniform float radius_step = 0.22;
uniform sampler2D glyphs : source_color, filter_linear, repeat_enable;
uniform float glyph_tiles = 7.0;
uniform float glyph_margin = 0.12;
// Centre light (owner direction on #804): a point light at the ring centre
// lights faces whose normal points back at it — the inner walls — with a
// soft falloff by ring radius; `ambient` is the base floor every face gets.
uniform float light_energy = 1.4;
uniform float ambient = 0.3;

const float RATE_BASE = 0.35;

varying vec3 v_pos;
varying vec3 v_nrm;
varying vec2 v_world;
varying float v_style;

vec4 q_axis(vec3 axis, float ang) {
	return vec4(axis * sin(ang * 0.5), cos(ang * 0.5));
}

vec4 q_mul(vec4 a, vec4 b) {
	return vec4(a.w * b.xyz + b.w * a.xyz + cross(a.xyz, b.xyz), a.w * b.w - dot(a.xyz, b.xyz));
}

vec3 q_rot(vec4 q, vec3 v) {
	vec3 t = 2.0 * cross(q.xyz, v);
	return v + q.w * t + cross(q.xyz, t);
}

void vertex() {
	float phase = INSTANCE_CUSTOM.x;
	float spin = INSTANCE_CUSTOM.y;
	float ring_count = INSTANCE_CUSTOM.z;
	v_style = INSTANCE_CUSTOM.w;
	float ring = CUSTOM0.w;
	if (ring > ring_count - 0.5) {
		// Not a ring of this instance: collapse to a point, nothing rasterises.
		VERTEX = vec2(0.0);
		v_pos = vec3(0.0);
		v_nrm = vec3(0.0, 0.0, 1.0);
	} else {
		float t = TIME * spin + phase;
		vec4 chain = vec4(0.0, 0.0, 0.0, 1.0);
		for (int i = 0; i < 5; i++) {
			if (float(i) > ring + 0.5) {
				break;
			}
			vec3 axis = (i % 2 == 0) ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
			float base_tilt = PI * float(i) / ring_count;
			float rate = RATE_BASE * (1.0 + float(i) * 0.55);
			chain = q_mul(chain, q_axis(axis, base_tilt + t * rate));
		}
		float depth = ring_count - 1.0 - ring;
		float ring_r = 1.0 + depth * radius_step;
		float r = ring_r * (1.0 - CUSTOM0.z * thickness);
		float hy = ring_r * band_width * 0.5;
		vec3 p = vec3(CUSTOM0.xy * r, CUSTOM1.x * hy);
		vec3 n = (CUSTOM1.y > 0.5) ? vec3(0.0, 0.0, CUSTOM1.z) : vec3(CUSTOM0.xy * CUSTOM1.z, 0.0);
		v_pos = q_rot(chain, p);
		v_nrm = q_rot(chain, n);
		VERTEX = v_pos.xy;
	}
	v_world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	if (front_pass > 0.5) {
		if (v_pos.z < 0.0) {
			discard;
		}
	} else if (v_pos.z >= 0.0) {
		discard;
	}
	vec3 n = normalize(v_nrm);
	// View is +z: fresnel on how edge-on the surface is.
	float fres = pow(1.0 - abs(n.z), 2.5);
	// Centre light: lit where the face looks back at the ring origin (inner
	// walls ~1, outer walls and rims 0), fading with the ring's radius.
	float d2 = max(dot(v_pos, v_pos), 0.25);
	float lit = max(dot(n, -v_pos * inversesqrt(d2)), 0.0) * light_energy / (0.5 + 0.5 * d2);
	vec3 rgb;
	float alpha;
	if (v_style > 1.5) {
		// SOLID_GLYPH: emulate cull_back — faces pointing away are dropped, so
		// the FAR inner face reads through the near gap like the 3D rig.
		if (n.z < 0.0) {
			discard;
		}
		float v = UV.y;
		float band = smoothstep(glyph_margin, glyph_margin + 0.05, v)
				* (1.0 - smoothstep(1.0 - glyph_margin - 0.05, 1.0 - glyph_margin, v));
		float vv = clamp((v - glyph_margin) / max(1.0 - 2.0 * glyph_margin, 0.0001), 0.0, 1.0);
		float g = texture(glyphs, vec2(UV.x * glyph_tiles + TIME * 0.04, vv)).r;
		// Metal base lit from the centre (inner faces bright, outer faces at
		// the ambient floor); runes glow at the tier's full value on top.
		rgb = COLOR.rgb * (0.22 * (ambient + lit) + g * band);
		alpha = 1.0;
	} else {
		// HOLO_GLASS: semitransparent body, fresnel-lit rim (gimbal_glass.gdshader).
		// Body gets a little of the centre light; the fresnel rim stays the
		// bright part so the tier does not blow out.
		rgb = COLOR.rgb * (0.25 + 0.25 * lit + fres);
		alpha = 0.07 + 0.12 * lit + fres * 0.9;
	}
	COLOR = vec4(rgb, alpha * COLOR.a * vision_field_dim(v_world));
}
