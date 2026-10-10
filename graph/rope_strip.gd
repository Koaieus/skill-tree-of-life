class_name RopeStrip
extends RefCounted

## Shared triangle-strip builder for the closed-form rope shaders
## ([GateRope], [ChannelLasso]). Each rope is [param segments] quads; UV.x of
## rope k runs s + 2k (s in [0,1], 0 = its anchor), UV.y is the side (0 / 1).
## The shaders recompute every vertex from UV, so the baked positions only
## seed the AABB — callers set a custom canvas rect anyway. Rope 0 is laid
## from x = 0, rope 1 back from x = [param span], each covering
## `span / ropes`.


static func build(span: float, segments: int, ropes: int) -> ArrayMesh:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var reach := span / float(maxi(ropes, 1))
	for k in ropes:
		for i in segments:
			var s0 := float(i) / segments
			var s1 := float(i + 1) / segments
			for q in [[s0, 0.0], [s1, 0.0], [s1, 1.0], [s0, 0.0], [s1, 1.0], [s0, 1.0]]:
				var s: float = q[0]
				var x := s * reach if k == 0 else span - s * reach
				verts.append(Vector2(x, 0.0))
				uvs.append(Vector2(s + 2.0 * k, q[1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
