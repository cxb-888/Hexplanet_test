@tool
class_name TileMapper
extends Node

# 公开属性（由 Main.gd 设置）
var grid_data: Array = []           # 三角形数据
var marker: SphereMarker = null     # 坐标标记器
var tiles_parent: Node3D = null     # 模型放置的父节点

# 模型数据
var _tile_scene: PackedScene = null
var _bottom_corners: PackedVector3Array = []   # 下三角面锚点（Y 最小的三个顶点）
var _top_corners: PackedVector3Array = []      # 上三角面锚点（Y 最大的三个顶点）
var _src_vertices: PackedVector3Array = []     # 模型所有顶点
var _src_indices: PackedInt32Array = []        # 三角形索引

# ------------------------------------------------------------
# 初始化：加载模型并提取锚点
# ------------------------------------------------------------
func setup(tile_path: String) -> bool:
	_tile_scene = load(tile_path) as PackedScene
	if not _tile_scene:
		printerr("无法加载模型: ", tile_path)
		return false
	if not _extract_anchor_vertices():
		printerr("无法提取锚点")
		return false
	return true

# ------------------------------------------------------------
# 生成所有瓦片
# ------------------------------------------------------------
func build():
	if not _tile_scene or _bottom_corners.is_empty():
		return

	for child in tiles_parent.get_children():
		child.queue_free()

	var success_count = 0
	var fail_count = 0
	for tri in grid_data:
		var inner = tri["inner"] as PackedVector3Array
		var outer = tri["outer"] as PackedVector3Array
		var indices = tri["indices"] as PackedInt32Array

		var sorted_inner = _get_sorted_vertices(inner, indices)
		var sorted_outer = _get_sorted_vertices(outer, indices)

		if sorted_inner.size() < 3 or sorted_outer.size() < 3:
			print("跳过三角形 ", tri["id"], " 因为排序顶点不足: inner=", sorted_inner.size(), " outer=", sorted_outer.size())
			fail_count += 1
			continue

		var mesh = _build_morphed_mesh(sorted_inner, sorted_outer)
		if mesh:
			var mi = MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = _get_debug_material()
			tiles_parent.add_child(mi)
			success_count += 1
		else:
			print("三角形 ", tri["id"], " 网格生成失败")
			fail_count += 1

	print("模型放置完成，成功: ", success_count, " 失败: ", fail_count, " 总数: ", grid_data.size())
# ------------------------------------------------------------
# 提取锚点（按 Y 轴位置：最小 3 个是下三角面，最大 3 个是上三角面）
# ------------------------------------------------------------
func _extract_anchor_vertices() -> bool:
	var temp = _tile_scene.instantiate()
	var mesh_instance = temp.find_child("*", true, false) as MeshInstance3D
	if not mesh_instance:
		mesh_instance = temp.get_node_or_null("MeshInstance3D")
	if not mesh_instance:
		printerr("未找到 MeshInstance3D")
		temp.queue_free()
		return false

	var mesh = mesh_instance.mesh
	var arrays = mesh.surface_get_arrays(0)
	_src_vertices = arrays[Mesh.ARRAY_VERTEX]
	_src_indices = arrays[Mesh.ARRAY_INDEX]
	if _src_indices.is_empty():
		_src_indices = PackedInt32Array()
		for i in range(_src_vertices.size()):
			_src_indices.append(i)

	# 按 Y 坐标排序，找出最小的 3 个（下锚点）和最大的 3 个（上锚点）
	var vertices_with_y = []
	for i in range(_src_vertices.size()):
		vertices_with_y.append({"y": _src_vertices[i].y, "idx": i})
	vertices_with_y.sort_custom(func(a, b): return a["y"] < b["y"])

	_bottom_corners.clear()
	_top_corners.clear()
	for i in range(3):
		_bottom_corners.append(_src_vertices[vertices_with_y[i]["idx"]])
	for i in range(vertices_with_y.size() - 3, vertices_with_y.size()):
		_top_corners.append(_src_vertices[vertices_with_y[i]["idx"]])

	# 调试打印锚点坐标
	print("=== 锚点调试 ===")
	print("下锚点 (BOTTOM):")
	for p in _bottom_corners:
		print("  ", p)
	print("上锚点 (TOP):")
	for p in _top_corners:
		print("  ", p)
	print("总顶点数: ", _src_vertices.size())
	print("=================================")

	# 验证
	if _bottom_corners.size() != 3 or _top_corners.size() != 3:
		printerr("锚点数量错误，下: ", _bottom_corners.size(), " 上: ", _top_corners.size())
		temp.queue_free()
		return false

	var area_bottom = (_bottom_corners[1] - _bottom_corners[0]).cross(_bottom_corners[2] - _bottom_corners[0]).length()
	var area_top = (_top_corners[1] - _top_corners[0]).cross(_top_corners[2] - _top_corners[0]).length()
	if area_bottom < 0.0001 or area_top < 0.0001:
		printerr("锚点构成的三角形退化")
		temp.queue_free()
		return false

	temp.queue_free()
	return true

# ------------------------------------------------------------
# 按全局坐标排序目标三角形顶点
# ------------------------------------------------------------
func _get_sorted_vertices(verts: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var coords = []
	for idx in indices:
		if marker.vertex_coords.has(idx):
			coords.append({"idx": idx, "coord": marker.vertex_coords[idx]})
		else:
			print("警告：顶点索引 ", idx, " 没有坐标！")
	if coords.size() < 3:
		return PackedVector3Array()
		
	coords.sort_custom(func(a, b):
		var ca = a["coord"] as SphereCoord
		var cb = b["coord"] as SphereCoord
		if ca.q != cb.q: return ca.q < cb.q
		return ca.r < cb.r)

	var sorted = PackedVector3Array()
	for item in coords:
		var orig_idx = -1
		for j in range(indices.size()):
			if indices[j] == item["idx"]:
				orig_idx = j
				break
		if orig_idx >= 0:
			sorted.append(verts[orig_idx])
	return sorted

# ------------------------------------------------------------
# 生成变形后的网格（重心坐标 + 高度插值）
# ------------------------------------------------------------
func _build_morphed_mesh(inner_sorted: PackedVector3Array, outer_sorted: PackedVector3Array) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var bot_normal = (_bottom_corners[1] - _bottom_corners[0]).cross(_bottom_corners[2] - _bottom_corners[0]).normalized()

	var src_bary = []
	var src_heights = []
	for v in _src_vertices:
		var bary = _calc_barycentric(v, _bottom_corners, bot_normal)
		src_bary.append(bary)
		# 修正：使用到下三角面的距离
		var bot_dist = _signed_distance_to_plane(v, _bottom_corners[0], bot_normal)
		var vertical_height = _top_corners[0].y - _bottom_corners[0].y
		var t = clamp(bot_dist / vertical_height, 0.0, 1.0)
		src_heights.append(t)

	var morphed_vertices = PackedVector3Array()
	for i in range(_src_vertices.size()):
		var bary = src_bary[i]
		var t = src_heights[i]
		var inner_pos = bary[0]*inner_sorted[0] + bary[1]*inner_sorted[1] + bary[2]*inner_sorted[2]
		var outer_pos = bary[0]*outer_sorted[0] + bary[1]*outer_sorted[1] + bary[2]*outer_sorted[2]
		var target_pos = inner_pos.lerp(outer_pos, t)
		morphed_vertices.append(target_pos)

	for idx in _src_indices:
		st.add_vertex(morphed_vertices[idx])

	st.generate_normals()
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
	return mesh

# ------------------------------------------------------------
# 辅助函数
# ------------------------------------------------------------
func _calc_barycentric(p: Vector3, corners: PackedVector3Array, normal: Vector3) -> Array:
	var A = corners[0]; var B = corners[1]; var C = corners[2]
	var p_proj = p - normal * _signed_distance_to_plane(p, A, normal)
	var area_a = (C - p_proj).cross(B - p_proj).length()
	var area_b = (A - p_proj).cross(C - p_proj).length()
	var area_c = (B - p_proj).cross(A - p_proj).length()
	var sum = area_a + area_b + area_c
	if sum < 0.0001:
		return [1.0/3.0, 1.0/3.0, 1.0/3.0]
	return [area_a/sum, area_b/sum, area_c/sum]

func _signed_distance_to_plane(point: Vector3, origin: Vector3, normal: Vector3) -> float:
	return (point - origin).dot(normal)

func _get_debug_material() -> Material:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.9, 0.9)
	mat.cull_mode = StandardMaterial3D.CULL_DISABLED
	# 微弱自发光，让暗面也不会全黑
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.2, 0.2)
	mat.emission_energy_multiplier = 0.5
	return mat
