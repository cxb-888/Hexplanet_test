class_name SphereCoord
extends RefCounted

# 单元格类型
enum CellType {
	POLE,           # 极点（南北极）
	MID_VERTEX,     # 边的中点
	FACE,           # 普通面（六边形单元格）
	FACE_SPECIAL,   # 特殊面（五边形单元格，只有5个邻居）
	EDGE_SPECIAL    # 特殊边
}

var q: int           # 坐标 Q
var r: int           # 坐标 R
var type: CellType   # 顶点类型
var type_idx: int    # 该类型内的序号

func _init(p_q: int = 0, p_r: int = 0, p_type: CellType = CellType.FACE, p_type_idx: int = 0):
	q = p_q
	r = p_r
	type = p_type
	type_idx = p_type_idx

func as_string() -> String:
	return "(%d, %d) %s[%d]" % [q, r, CellType.keys()[type], type_idx]
