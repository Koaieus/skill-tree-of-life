shader_type canvas_item;
render_mode blend_premul_alpha;

#include "res://ui/vision_field.gdshaderinc"

// GimbalWorld's front composite, fogged per pixel. The back half sits under
// FogOverlay and is darkened by it; the front half draws OVER the fog, so it
// must erase itself by the same field or a rig at the vision edge shows its
// near rings over black. Content that erases itself: gate with
// `mix(1.0, lit, active)`, never `* active` (see vision_field.gdshaderinc).
// Not modelled: FogOverlay's frontier-halo lift and its `intensity` knob.

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float lit = 1.0 - vision_field_darkness(world_pos);
	float keep = mix(1.0, lit, vision_field_enabled ? 1.0 : 0.0);
	// Premultiplied: scale colour and alpha together.
	COLOR = texture(TEXTURE, UV) * keep;
}
