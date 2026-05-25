class_name SphereMarker
extends RefCounted

# 标记结果
var vertex_coords: Dictionary = {}   # int(顶点全局索引) -> SphereCoord
var triangle_coords: Array = []      # Array[SphereCoord]，索引对应三角形ID

# ------------------------------------------------------------
# 主入口：为三角形数据分配全局坐标
# ------------------------------------------------------------
func mark_all(triangles_data: Array):
	vertex_coords.clear()
	triangle_coords.clear()
	triangle_coords.resize(triangles_data.size())

	# 1. 找出所有特殊顶点（被5个三角形包围的顶点）
	var special_vertices = _find_special_vertices(triangles_data)
	print("找到特殊顶点数量: ", special_vertices.size())  # 应该输出 12

	# 2. 建立顶点到三角形的映射
	var vert_to_tris = _build_vert_to_tris(triangles_data)

	# 3. 从特殊顶点开始 BFS，分配顶点坐标
	_assign_vertex_coords(special_vertices, vert_to_tris)

	# 4. 根据顶点坐标为三角形分配坐标
	_assign_triangle_coords(triangles_data)

	return special_vertices.size()

# ------------------------------------------------------------
# 找出被5个三角形包围的顶点（五边形中心）
# ------------------------------------------------------------
func _find_special_vertices(triangles_data: Array) -> Array:
	var vert_count = {}  # 顶点索引 -> 出现次数
	for tri in triangles_data:
		var indices = tri["indices"] as PackedInt32Array
		for idx in [indices[0], indices[1], indices[2]]:
			vert_count[idx] = vert_count.get(idx, 0) + 1

	var special = []
	for idx in vert_count:
		if vert_count[idx] == 5:   # 只被5个面包围，而不是6个
			special.append(idx)
	return special

# ------------------------------------------------------------
# 建立顶点到三角形的映射
# ------------------------------------------------------------
func _build_vert_to_tris(triangles_data: Array) -> Dictionary:
	var mapping = {}
	for tri in triangles_data:
		var indices = tri["indices"] as PackedInt32Array
		for idx in [indices[0], indices[1], indices[2]]:
			if not mapping.has(idx):
				mapping[idx] = []
			mapping[idx].append(tri)
	return mapping

# ------------------------------------------------------------
# BFS 分配顶点坐标
# ------------------------------------------------------------
func _assign_vertex_coords(special_vertices: Array, vert_to_tris: Dictionary):
	var visited = {}
	var queue = []

	# 初始化特殊顶点坐标（简化为按顺序分配，后续可精确）
	for i in range(special_vertices.size()):
		var idx = special_vertices[i]
		var coord = SphereCoord.new(i * 10, 0, SphereCoord.CellType.FACE_SPECIAL, i)
		vertex_coords[idx] = coord
		visited[idx] = true
		queue.append(idx)

	# BFS
	while queue.size() > 0:
		var current = queue.pop_front()
		var current_coord = vertex_coords[current]
		var tris = vert_to_tris.get(current, [])

		for tri in tris:
			var indices = tri["indices"] as PackedInt32Array
			# 找出当前顶点在这个三角形中的另外两个邻居顶点
			var others = []
			for idx in [indices[0], indices[1], indices[2]]:
				if idx != current:
					others.append(idx)

			# 为每个邻居顶点分配坐标（如果还没访问过）
			for i in range(others.size()):
				var nid = others[i]
				if visited.has(nid):
					continue
				var coord = SphereCoord.new()
				coord.q = current_coord.q + _neighbor_q_offset(i)
				coord.r = current_coord.r + _neighbor_r_offset(i)
				coord.type = SphereCoord.CellType.FACE
				coord.type_idx = 0
				vertex_coords[nid] = coord
				visited[nid] = true
				queue.append(nid)

# 邻居方向偏移（简化版）
func _neighbor_q_offset(dir: int) -> int:
	return [1, 0, -1, -1, 0, 1][dir % 6]

func _neighbor_r_offset(dir: int) -> int:
	return [0, 1, 1, 0, -1, -1][dir % 6]

# ------------------------------------------------------------
# 为三角形分配坐标（用三个顶点坐标的平均值）
# ------------------------------------------------------------
func _assign_triangle_coords(triangles_data: Array):
	for i in range(triangles_data.size()):
		var tri = triangles_data[i]
		var indices = tri["indices"] as PackedInt32Array
		var q_sum = 0
		var r_sum = 0
		var has_special = false
		for idx in [indices[0], indices[1], indices[2]]:
			if vertex_coords.has(idx):
				var c = vertex_coords[idx] as SphereCoord
				q_sum += c.q
				r_sum += c.r
				if c.type == SphereCoord.CellType.FACE_SPECIAL:
					has_special = true
		var avg_q = int(float(q_sum) / 3.0)
		var avg_r = int(float(r_sum) / 3.0)
		var type = SphereCoord.CellType.FACE_SPECIAL if has_special else SphereCoord.CellType.FACE
		triangle_coords[i] = SphereCoord.new(avg_q, avg_r, type, i)
