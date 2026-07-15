shader_type canvas_item;

// Samples a pre-generated noise texture (NoiseTexture2D with seamless=true) and
// applies nebula colour processing — threshold, colour mixing, strength. The
// noise generation (scale, detail, tiling) lives on the NoiseTexture2D/FastNoiseLite
// resources; this shader only processes the values.

uniform vec4 color_a : source_color = vec4(0.13, 0.05, 0.30, 1.0);
uniform vec4 color_b : source_color = vec4(0.02, 0.11, 0.22, 1.0);
uniform float strength : hint_range(0.0, 1.5) = 0.65;
uniform float threshold : hint_range(0.0, 1.0) = 0.34;

void fragment() {
	float n = texture(TEXTURE, UV).r;
	float mask = smoothstep(threshold, threshold + 0.28, n);
	vec3 tint = mix(color_a.rgb, color_b.rgb, n);
	float a = clamp(mask * strength, 0.0, 1.0);
	COLOR = vec4(tint, a);
}