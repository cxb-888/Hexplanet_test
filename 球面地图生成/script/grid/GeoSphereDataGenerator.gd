class_name GeoSphereDataGenerator
extends RefCounted

const PHI = (1.0 + sqrt(5.0)) / 2.0

static func generate_triangles(subdivisions: int, inner_radius: float, outer_radius: float) -> Array:
	var base_verts: PackedVector3Array = _get_icosahedron_vertices()
	for i in base_verts.size():
		base_verts[i] = base_verts[i].normalized() * inner_radius

	var tris: PackedInt32Array = _get_icosahedron_triangles()
	var verts: PackedVector3Array = base_verts

	for sub in range(subdivisions):
		var new_tris: PackedInt32Array = PackedInt32Array()
		var mid_cache: Dictionary = {}
		for i in range(0, tris.size(), 3):
			var i0: int = tris[i]
			var i1: int = tris[i+1]
			var i2: int = tris[i+2]
			var a: int = _get_or_add_mid(i0, i1, verts, inner_radius, mid_cache)
			var b: int = _get_or_add_mid(i1, i2, verts, inner_radius, mid_cache)
			var c: int = _get_or_add_mid(i2, i0, verts, inner_radius, mid_cache)
			new_tris.append_array([i0, a, c, i1, b, a, i2, c, b, a, b, c])
		tris = new_tris

	var verts_inner: PackedVector3Array = PackedVector3Array()
	var verts_outer: PackedVector3Array = PackedVector3Array()
	for v in verts:
		var dir: Vector3 = v.normalized()
		verts_inner.append(dir * inner_radius)
		verts_outer.append(dir * outer_radius)

	var triangles_data: Array = []
	for t in range(0, tris.size(), 3):
		var idx0: int = tris[t]
		var idx1: int = tris[t+1]
		var idx2: int = tris[t+2]
		triangles_data.append({
			"id": int(float(t) / 3.0),
			"indices": PackedInt32Array([idx0, idx1, idx2]),
			"inner": PackedVector3Array([verts_inner[idx0], verts_inner[idx1], verts_inner[idx2]]),
			"outer": PackedVector3Array([verts_outer[idx0], verts_outer[idx1], verts_outer[idx2]])
		})

	return triangles_data

static func _get_icosahedron_vertices() -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(-1, PHI, 0), Vector3(1, PHI, 0), Vector3(-1, -PHI, 0), Vector3(1, -PHI, 0),
		Vector3(0, -1, PHI), Vector3(0, 1, PHI), Vector3(0, -1, -PHI), Vector3(0, 1, -PHI),
		Vector3(PHI, 0, -1), Vector3(PHI, 0, 1), Vector3(-PHI, 0, -1), Vector3(-PHI, 0, 1)
	])

static func _get_icosahedron_triangles() -> PackedInt32Array:
	return PackedInt32Array([
		0,11,5, 0,5,1, 0,1,7, 0,7,10, 0,10,11,
		1,5,9, 5,11,4, 11,10,2, 10,7,6, 7,1,8,
		3,9,4, 3,4,2, 3,2,6, 3,6,8, 3,8,9,
		4,9,5, 2,4,11, 6,2,10, 8,6,7, 9,8,1
	])

static func _get_or_add_mid(i0: int, i1: int, verts: PackedVector3Array, radius: float, cache: Dictionary) -> int:
	var key: Array = [i0, i1] if i0 < i1 else [i1, i0]
	if cache.has(key):
		return cache[key]
	var mid: Vector3 = (verts[i0] + verts[i1]) * 0.5
	mid = mid.normalized() * radius
	verts.append(mid)
	var idx: int = verts.size() - 1
	cache[key] = idx
	return idx
