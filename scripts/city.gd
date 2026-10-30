extends Node3D
## City scene: roads, intersections, modular buildings, stairs, merchants,
## customers, blockers, one roadside reward. All primitives, plain colours.
## Drive-away targets are distinguished by SHAPE + outline icon, not colour
## alone; dodge targets show only a predicted trajectory line.
##
## Layout (world XZ, station at origin, Y up):
##   north (-Z): merchant A + customer A
##   east  (+X): merchant B (slow) + customer B, uphill
##   south (+Z): merchant C + customer C
##   west  (-X): mountain / slope road, x < -30
##   centre: crossroads, station at (0, 0, 10)

var merchants := {}
var customers := {}
var blockers: Array = []
var reward_node: MeshInstance3D = null
var reward_taken := false
var exploration_node: MeshInstance3D = null
var exploration_taken := false
var extraction_node: MeshInstance3D = null
var props: Array = []

const ROAD_COLOUR := Color(0.25, 0.25, 0.28)
const GROUND_COLOUR := Color(0.45, 0.55, 0.4)


func _ready() -> void:
	_add_box(Vector3(0, -0.1, 0), Vector3(140, 0.2, 140), GROUND_COLOUR, "Ground")
	# Cross roads, all directions.
	_add_box(Vector3(0, 0.05, 0), Vector3(140, 0.1, 10), ROAD_COLOUR, "RoadNS")
	_add_box(Vector3(0, 0.05, 0), Vector3(10, 0.1, 140), ROAD_COLOUR, "RoadEW")
	_add_box(Vector3(-45, 0.05, 0), Vector3(40, 0.1, 10), ROAD_COLOUR, "RoadMountain")
	# Mountain slope: an inclined slab west of x = -30, plus steps.
	var slope := _add_box(Vector3(-45, 1.2, 0), Vector3(30, 0.6, 12), Color(0.4, 0.5, 0.35), "Mountain")
	slope.rotation.z = deg_to_rad(-12.0)
	for i in range(5):
		_add_box(Vector3(18 + i * 1.2, 0.15 + i * 0.3, 18), Vector3(1.2, 0.3, 4), Color(0.6, 0.6, 0.6), "Stairs%d" % i)

	# Modular buildings: varied heights / footprints, no text, no logos.
	var building_spots := [
		Vector3(-20, 0, -20), Vector3(20, 0, -20), Vector3(-20, 0, 20),
		Vector3(28, 0, -32), Vector3(-32, 0, -18), Vector3(32, 0, 28),
		Vector3(-28, 0, 32), Vector3(20, 0, 38), Vector3(-38, 0, 38),
	]
	var colours := [Color(0.7, 0.65, 0.55), Color(0.6, 0.7, 0.8), Color(0.8, 0.7, 0.6), Color(0.65, 0.75, 0.65)]
	for i in range(building_spots.size()):
		var p: Vector3 = building_spots[i]
		var h := 4.0 + float(i % 4) * 2.5
		_add_box(Vector3(p.x, h / 2.0, p.z), Vector3(9, h, 9), colours[i % colours.size()], "Building%d" % i)

	# Merchants (green cylinders) and customers (orange cones, shape-coded).
	merchants["A"] = _add_marker(Vector3(0, 0, -38), Color(0.2, 0.8, 0.3), "MerchantA", "cylinder")
	merchants["B"] = _add_marker(Vector3(38, 0, -6), Color(0.2, 0.8, 0.3), "MerchantB", "cylinder")
	merchants["C"] = _add_marker(Vector3(-6, 0, 38), Color(0.2, 0.8, 0.3), "MerchantC", "cylinder")
	customers["A"] = _add_marker(Vector3(-18, 0, -30), Color(1.0, 0.6, 0.1), "CustomerA", "cone")
	customers["B"] = _add_marker(Vector3(44, 0, 14), Color(1.0, 0.6, 0.1), "CustomerB", "cone")
	customers["C"] = _add_marker(Vector3(18, 0, 34), Color(1.0, 0.6, 0.1), "CustomerC", "cone")

	# Blockers: wandering figures. Drive-away targets = tall boxes with a
	# ring outline; they move slowly and respawn after being driven away.
	for i in range(3):
		var b := MeshInstance3D.new()
		b.mesh = BoxMesh.new()
		b.mesh.size = Vector3(1.2, 2.0, 1.2)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.3, 0.5)
		b.material_override = mat
		b.name = "Blocker%d" % i
		b.position = Vector3(-12 + i * 12, 1.0, -12 + i * 8)
		add_child(b)
		var ring := MeshInstance3D.new()
		ring.mesh = TorusMesh.new()
		ring.mesh.inner_radius = 0.9
		ring.mesh.outer_radius = 1.1
		var ring_mat := StandardMaterial3D.new()
		ring_mat.albedo_color = Color(1.0, 1.0, 1.0)
		ring.material_override = ring_mat
		ring.position.y = -0.8
		ring.rotation.x = deg_to_rad(90.0)
		b.add_child(ring)
		blockers.append({"node": b, "home": b.position, "away_until": 0.0, "phase": float(i)})

	_spawn_props()

	# One roadside reward, on-route on the main crossroad, not a detour.
	reward_node = MeshInstance3D.new()
	reward_node.mesh = SphereMesh.new()
	reward_node.mesh.radius = 0.7
	reward_node.mesh.height = 1.4
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(1.0, 0.9, 0.2)
	reward_node.material_override = rmat
	reward_node.name = "RoadsideReward"
	reward_node.position = Vector3(6, 0.8, -6)
	add_child(reward_node)

	# Exploration reward: clearly off-route, in the mountain corner.
	# Detour time cost is shown in main when the player gets close.
	exploration_node = MeshInstance3D.new()
	exploration_node.mesh = SphereMesh.new()
	exploration_node.mesh.radius = 0.9
	exploration_node.mesh.height = 1.8
	var emat := StandardMaterial3D.new()
	emat.albedo_color = Color(0.2, 0.9, 0.9)
	exploration_node.material_override = emat
	exploration_node.name = "ExplorationReward"
	exploration_node.position = Vector3(-38, 0.9, -38)
	add_child(exploration_node)

	# Early-stage extraction point, separate from the station, with a
	# clear time cost (see main). Later stages merge this into station
	# settlement; this slice is the early stage, so it stays separate.
	extraction_node = MeshInstance3D.new()
	extraction_node.mesh = BoxMesh.new()
	extraction_node.mesh.size = Vector3(2.0, 2.0, 2.0)
	var xmat := StandardMaterial3D.new()
	xmat.albedo_color = Color(0.9, 0.9, 0.9)
	extraction_node.material_override = xmat
	extraction_node.name = "ExtractionPoint"
	extraction_node.position = Vector3(-10, 1.0, 30)
	add_child(extraction_node)


func _spawn_props() -> void:
	# Battlefield props: base shape differs by rarity (box / cylinder /
	# sphere + ring), light pillar colour + height differ by rarity.
	# A prop root is a Node3D so the pickup pop can scale the whole prop.
	for spawn in GameData.PROP_SPAWNS:
		var prop_id: String = spawn["id"]
		var def: Dictionary = GameData.PROPS[prop_id]
		var tier: Dictionary = GameData.PROP_TIERS[def["rarity"]]
		var root := Node3D.new()
		root.name = "Prop_" + prop_id
		root.position = Vector3(spawn["pos"].x, 0.0, spawn["pos"].z)
		add_child(root)
		var mesh_node := MeshInstance3D.new()
		# Base shape, never colour alone: normal = smooth circle disc,
		# epic = hexagonal cylinder (serrated look), legendary =
		# twelve-point cylinder + radiating ring.
		if def["rarity"] == "epic":
			mesh_node.mesh = CylinderMesh.new()
			mesh_node.mesh.radial_segments = 6
			mesh_node.mesh.top_radius = 0.7
			mesh_node.mesh.bottom_radius = 0.7
			mesh_node.mesh.height = 1.4
		elif def["rarity"] == "legendary":
			mesh_node.mesh = CylinderMesh.new()
			mesh_node.mesh.radial_segments = 12
			mesh_node.mesh.top_radius = 0.7
			mesh_node.mesh.bottom_radius = 0.7
			mesh_node.mesh.height = 1.4
		else:
			mesh_node.mesh = CylinderMesh.new()
			mesh_node.mesh.radial_segments = 32
			mesh_node.mesh.top_radius = 0.7
			mesh_node.mesh.bottom_radius = 0.7
			mesh_node.mesh.height = 0.5
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(tier["pillar_colour"])
		mesh_node.material_override = mat
		mesh_node.position.y = 0.9
		root.add_child(mesh_node)
		# Ground ring size differs by rarity, so rarity reads at a glance.
		var ring := MeshInstance3D.new()
		ring.mesh = TorusMesh.new()
		ring.mesh.inner_radius = float(tier["ring_radius"]) - 0.15
		ring.mesh.outer_radius = float(tier["ring_radius"])
		var ring_mat := StandardMaterial3D.new()
		ring_mat.albedo_color = Color(tier["pillar_colour"])
		ring.material_override = ring_mat
		ring.position.y = 0.15
		ring.rotation.x = deg_to_rad(90.0)
		root.add_child(ring)
		if def["rarity"] == "legendary":
			# Twelve radiating spikes around the ring.
			for k in range(12):
				var spike := MeshInstance3D.new()
				spike.mesh = BoxMesh.new()
				spike.mesh.size = Vector3(0.25, 0.1, 0.8)
				var spike_mat := StandardMaterial3D.new()
				spike_mat.albedo_color = Color(1.0, 0.75, 0.1)
				spike.material_override = spike_mat
				var ang := float(k) / 12.0 * TAU
				spike.position = Vector3(cos(ang) * 2.2, 0.15, sin(ang) * 2.2)
				spike.rotation.y = -ang
				root.add_child(spike)
		var pillar := MeshInstance3D.new()
		pillar.mesh = CylinderMesh.new()
		# Thin normal pillar, thick epic pillar, legendary rainbow beam.
		var pr := 0.4 if def["rarity"] == "normal" else 0.8
		pillar.mesh.top_radius = pr
		pillar.mesh.bottom_radius = pr
		pillar.mesh.height = float(tier["pillar_height"])
		var pillar_mat := StandardMaterial3D.new()
		pillar_mat.albedo_color = Color(tier["pillar_colour"], 0.25)
		pillar_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pillar.material_override = pillar_mat
		pillar.position.y = float(tier["pillar_height"]) / 2.0
		root.add_child(pillar)
		props.append({
			"id": prop_id, "root": root, "mesh": mesh_node,
			"pillar": pillar, "taken": false, "pop_t": 0.0,
		})


func reset_props() -> void:
	# Per-run instances are new each run: old prop roots are freed and
	# fresh ones are spawned from the read-only definitions. Definitions
	# in GameData are never mutated.
	for p in props:
		(p["root"] as Node3D).queue_free()
	props = []
	_spawn_props()


func _add_box(pos: Vector3, size: Vector3, colour: Color, node_name: String) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = BoxMesh.new()
	m.mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	m.material_override = mat
	m.position = pos
	m.name = node_name
	add_child(m)
	return m


func _add_marker(pos: Vector3, colour: Color, node_name: String, shape_kind: String) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	if shape_kind == "cone":
		m.mesh = CylinderMesh.new()
		m.mesh.top_radius = 0.1
		m.mesh.bottom_radius = 0.9
		m.mesh.height = 2.2
	else:
		m.mesh = CylinderMesh.new()
		m.mesh.top_radius = 0.9
		m.mesh.bottom_radius = 0.9
		m.mesh.height = 2.2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	m.material_override = mat
	m.position = Vector3(pos.x, 1.1, pos.z)
	m.name = node_name
	add_child(m)
	return m


func merchant_pos(key: String) -> Vector3:
	if merchants.has(key):
		return (merchants[key] as MeshInstance3D).global_position
	return Vector3.ZERO


func customer_pos(key: String) -> Vector3:
	if customers.has(key):
		return (customers[key] as MeshInstance3D).global_position
	return Vector3.ZERO
