// The gimbal spin chain, run per vertex off TIME (Gimbal3D never ticks).
//
// Chain index 0 is the OUTERMOST ring (the base/parent); each inner ring
// composes its own spin ONTO the accumulated outer rotation, so an outer ring
// bodily carries every ring inside it (see skill-node-visuals.md). Outer rings
// spin slowest — the rate grows with depth — so inner rings whirl fast inside
// the slowly-reorienting frame of the outer ones.
//
// Contract with gimbal_3d.gd: each ring is a MeshInstance3D holding the shared
// UNIT band mesh (axis = local Z), scaled by its Basis, with the per-ring
// instance uniform `chain` = (index, ring_count, phase, spin_speed). Uniform
// scale commutes with the rotation, so rotating the model-space vertex here is
// the old `basis = Basis(chain) * MESH_CORR` exactly. The ring's custom_aabb is
// its rotation sphere, so culling stays exact while this moves it.

instance uniform vec4 chain = vec4(0.0, 1.0, 0.0, 1.0);

const float GIMBAL_RATE_BASE = 0.35;

vec4 gimbal_q_axis(vec3 axis, float ang) {
	return vec4(axis * sin(ang * 0.5), cos(ang * 0.5));
}

vec4 gimbal_q_mul(vec4 a, vec4 b) {
	return vec4(a.w * b.xyz + b.w * a.xyz + cross(a.xyz, b.xyz), a.w * b.w - dot(a.xyz, b.xyz));
}

vec3 gimbal_q_rot(vec4 q, vec3 v) {
	vec3 t = 2.0 * cross(q.xyz, v);
	return v + q.w * t + cross(q.xyz, t);
}

// The accumulated rotation of ring `index` in a chain of `ring_count`, at spin
// clock `t` (= TIME * spin_speed + phase). Axes alternate RIGHT/UP; standing
// tilt PI * i / ring_count; rate GIMBAL_RATE_BASE * (1 + 0.55 i).
vec4 gimbal_chain(int index, int ring_count, float t) {
	vec4 q = vec4(0.0, 0.0, 0.0, 1.0);
	for (int i = 0; i < 5; i++) {
		if (i > index) {
			break;
		}
		vec3 axis = (i % 2 == 0) ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
		float base_tilt = PI * float(i) / float(ring_count);
		float rate = GIMBAL_RATE_BASE * (1.0 + float(i) * 0.55);
		q = gimbal_q_mul(q, gimbal_q_axis(axis, base_tilt + t * rate));
	}
	return q;
}

// Call from vertex(): gimbal_vertex(VERTEX, NORMAL, TIME);
void gimbal_vertex(inout vec3 vertex, inout vec3 normal, float time) {
	vec4 q = gimbal_chain(int(chain.x + 0.5), max(int(chain.y + 0.5), 1), time * chain.w + chain.z);
	vertex = gimbal_q_rot(q, vertex);
	normal = gimbal_q_rot(q, normal);
}
