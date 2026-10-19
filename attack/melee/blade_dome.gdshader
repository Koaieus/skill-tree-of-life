shader_type canvas_item;

// The steel dome body of one BladeNode (#1692): an opaque lit hemisphere, kin
// to SkillNode's inner disk, with a hard anisotropic specular streak. Every
// blade dome shares ONE ShaderMaterial (BladeDome's static) and varies only
// through `instance uniform`s, so all of them batch into one draw call.
//
// SDR body, HDR hot spot: the body never exceeds base_color (≤ 1.0, capped on
// the CPU by BladeStyle.dome_color), and only the specular term lifts past the
// bloom threshold. No vision fog and no carve, on purpose.
//
// The incoming COLOR is the CanvasItem's modulate × the draw colour
// (BladeStyle.fill_alpha in its alpha): it is multiplied in, never overwritten,
// so SkillBlade's form-in fade on BladeNode.modulate reaches the dome.
#include "res://skill_node/visuals/lighting.gdshaderinc"

instance uniform vec4 base_color : source_color = vec4(0.55, 0.58, 0.62, 1.0);
instance uniform float highlight_intensity : hint_range(0.0, 2.0) = 0.9;
instance uniform float highlight_sharpness : hint_range(4.0, 256.0) = 64.0;
// Anisotropy of the streak (1 = round) and its screen-space axis in radians.
instance uniform float streak_stretch : hint_range(1.0, 6.0) = 2.5;
instance uniform float streak_angle = 0.7853982;
instance uniform vec2 light_dir = vec2(-0.35, -0.35);
// The wind-up's BLING band (SkillBlade owns it): its centre's offset past this
// dome's centre in band widths, and its direction in dome-local unit-disc
// coordinates already scaled by radius / width — so the band coordinate at
// disc point p is glint_offset - dot(p, glint_dir), lit within |1|. Parked
// far off (-1e4) when no sweep runs. glint_color is HDR (BladeStyle.glint_tier).
instance uniform float glint_offset = -10000.0;
instance uniform vec2 glint_dir = vec2(1.0, 0.0);
instance uniform vec4 glint_color : source_color = vec4(1.0);


// The position the SPECULAR normal is read at: squashed along the streak axis
// around the hot spot's own centre, so the highlight stretches along that axis
// without moving. The body's diffuse and silhouette keep the true position.
vec2 blade_streak_pos(vec2 p_pos, vec3 p_light, float p_stretch, float p_angle) {
	vec2 hot = p_light.xy;
	vec2 axis = vec2(cos(p_angle), sin(p_angle));
	vec2 across = vec2(-axis.y, axis.x);
	vec2 d = p_pos - hot;
	return hot + axis * (dot(d, axis) / max(p_stretch, 1.0)) + across * dot(d, across);
}


void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	vec3 l = sn_light_dir(light_dir);
	float diffuse = sn_diffuse(sn_dome_normal(p), l);
	vec3 spec_normal = sn_dome_normal(blade_streak_pos(p, l, streak_stretch, streak_angle));
	float spec = sn_specular_exp(sn_diffuse(spec_normal, l), highlight_intensity, highlight_sharpness);
	vec3 body = base_color.rgb * (0.35 + 0.65 * diffuse);
	float r2 = dot(p, p);
	float edge_alpha = 1.0 - smoothstep(0.96, 1.0, r2);
	// The glint rides the lit side harder, so it reads as light on steel.
	float band = 1.0 - smoothstep(0.0, 1.0, abs(glint_offset - dot(p, glint_dir)));
	vec3 glint = glint_color.rgb * band * (0.3 + 0.7 * diffuse);
	COLOR = vec4((body + vec3(spec) + glint) * COLOR.rgb, COLOR.a * base_color.a * edge_alpha);
}
