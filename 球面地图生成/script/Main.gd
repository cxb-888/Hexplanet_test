@tool
extends Node3D

@export var subdivisions: int = 3:
	set(v):
		subdivisions = v
		regenerate()
@export var inner_radius: float = 1.0:
	set(v):
		inner_radius = v
		regenerate()
@export var outer_radius: float = 1.2:
	set(v):
		outer_radius = v
		regenerate()

@export var tile_model_path: String = "res://tiles/color_point_test.glb"

var inner_lines: MeshInstance3D = null
var outer_lines: MeshInstance3D = null
var model_container: Node3D = null

func _ready():
	_ensure_nodes()
	regenerate()
	# 确保有 WorldEnvironment
	var we = get_node_or_null("WorldEnvironment")
	if not we:
		we = WorldEnvironment.new()
		we.name = "WorldEnvironment"
		add_child(we)
		var env = Environment.new()
		env.background_mode = Environment.BG_SKY
		env.sky = Sky.new()
		env.sky.sky_material = ProceduralSkyMaterial.new()
		we.environment = env

# 如果没有 DirectionalLight3D，自动创建一个
	var dl = get_node_or_null("DirectionalLight3D")
	if not dl:
		dl = DirectionalLight3D.new()
		dl.name = "DirectionalLight3D"
		add_child(dl)
		dl.energy = 5.0
	
func _ensure_nodes():
	if not inner_lines:
		inner_lines = get_node_or_null("InnerLines")
		if not inner_lines:
			inner_lines = MeshInstance3D.new()
			inner_lines.name = "InnerLines"
			add_child(inner_lines)
	if not outer_lines:
		outer_lines = get_node_or_null("OuterLines")
		if not outer_lines:
			outer_lines = MeshInstance3D.new()
			outer_lines.name = "OuterLines"
			add_child(outer_lines)
	if not model_container:
		model_container = get_node_or_null("ModelContainer")
		if not model_container:
			model_container = Node3D.new()
			model_container.name = "ModelContainer"
			add_child(model_container)

func regenerate():
	if not inner_lines or not outer_lines or not model_container:
		_ensure_nodes()

	inner_lines.mesh = null
	outer_lines.mesh = null
	for child in model_container.get_children():
		child.queue_free()

	var data = GeoSphereDataGenerator.generate_triangles(subdivisions, inner_radius, outer_radius)
	if data.is_empty():
		return

	# 线框（可注释）
	_draw_wireframe(data, "inner", Color.RED, inner_lines)
	_draw_wireframe(data, "outer", Color.BLUE, outer_lines)
	print("双层网格已生成，三角形数量: ", data.size())

	# 坐标标记
	var marker = SphereMarker.new()
	var special_count = marker.mark_all(data)
	print("找到特殊顶点数量: ", special_count)

	# 模型映射
	var tile_mapper = TileMapper.new()
	tile_mapper.grid_data = data
	tile_mapper.marker = marker
	tile_mapper.tiles_parent = model_container
	if tile_mapper.setup(tile_model_path):
		tile_mapper.build()
		print("模型映射完成")
	else:
		printerr("TileMapper 初始化失败")

func _draw_wireframe(triangles: Array, key: String, color: Color, target: MeshInstance3D):
	var line_mesh = ImmediateMesh.new()
	line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for tri in triangles:
		var vtx = tri[key] as PackedVector3Array
		for i in range(3):
			line_mesh.surface_add_vertex(vtx[i])
			line_mesh.surface_add_vertex(vtx[(i+1)%3])
	line_mesh.surface_end()
	target.mesh = line_mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.flags_unshaded = true
	target.material_override = mat
