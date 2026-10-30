extends Node3D
## Station scene, per stage: spawn / rest / resupply / vehicle swap /
## orders / upgrade choice. This slice has one station, at the route centre.
## The building is one floor plus a mezzanine, yellow + dark grey, with a
## fictional geometric emblem (a plain diamond shape, no text).

var spawn_point: Vector3 = Vector3(0, 0, 10)


func _ready() -> void:
	var base := MeshInstance3D.new()
	base.mesh = BoxMesh.new()
	base.mesh.size = Vector3(14, 5, 10)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.1)
	base.material_override = mat
	base.position = Vector3(0, 2.5, 16)
	base.name = "StationBuilding"
	add_child(base)

	var mezz := MeshInstance3D.new()
	mezz.mesh = BoxMesh.new()
	mezz.mesh.size = Vector3(8, 2.5, 7)
	var mat2 := StandardMaterial3D.new()
	mat2.albedo_color = Color(0.25, 0.25, 0.28)
	mezz.material_override = mat2
	mezz.position = Vector3(0, 6.2, 16)
	mezz.name = "StationMezzanine"
	add_child(mezz)

	# Diamond emblem, shape only, no text.
	var emblem := MeshInstance3D.new()
	emblem.mesh = BoxMesh.new()
	emblem.mesh.size = Vector3(1.4, 1.4, 0.2)
	var mat3 := StandardMaterial3D.new()
	mat3.albedo_color = Color(0.25, 0.25, 0.28)
	emblem.material_override = mat3
	emblem.position = Vector3(0, 3.2, 10.9)
	emblem.rotation.z = deg_to_rad(45.0)
	emblem.name = "StationEmblem"
	add_child(emblem)

	# Front yard zones, marked by flat coloured pads, not by text.
	_add_pad(Vector3(-6, 0.06, 10), Color(0.3, 0.5, 1.0), "ParkingCharging")
	_add_pad(Vector3(0, 0.06, 10), Color(0.2, 0.8, 0.3), "PickupSorting")
	_add_pad(Vector3(6, 0.06, 10), Color(1.0, 0.6, 0.1), "RepairUpgrade")


func _add_pad(pos: Vector3, colour: Color, node_name: String) -> void:
	var m := MeshInstance3D.new()
	m.mesh = BoxMesh.new()
	m.mesh.size = Vector3(4, 0.1, 4)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	m.material_override = mat
	m.position = pos
	m.name = node_name
	add_child(m)
