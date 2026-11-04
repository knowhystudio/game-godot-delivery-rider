extends Node3D
## Screenshot-only scene (next playable): the REAL Kenney district from
## the 2026-10-31 shots, plus REAL traffic and pedestrians.
## - Traffic: Kenney Car Kit GLBs (sedan/taxi/van/truck/police), wheels are
##   separate meshes and really spin; cars drive lanes and loop.
## - Pedestrians: Kenney Animated Characters (Blender-merged GLB with
##   Idle/Run/Jump). The pack has NO walk clip (verified: only idle, run,
##   jump in the ZIP), so pedestrians STAND on the sidewalk playing Idle.
##   They have no collision shape: they never block, never take part in
##   collisions.
## - Crash damage is REAL logic, not staging: a moving car that hits the
##   rider (physics slide collision, distance check on the crash car as a
##   fallback) applies the prototype's own rules — shake +45 (the
##   prototype spill rule then fires at shake>=100: integrity -20, shake
##   reset to 60), stamina -25, order clock -5s, one combined message.
##   Rider is still the prototype yellow box rider (out of scope here).
## No prototype game logic is touched: this file + shots2.tscn are the
## only new files in the copy.

const S := 4.0  # Kenney kit is 1 m miniature scale; x4 fits the rider.
const SHOT1 := "/home/hatch/workspace/delivery-game-effects/next-playable-2026-11-03/01-street-alive.png"
const SHOT2 := "/home/hatch/workspace/delivery-game-effects/next-playable-2026-11-03/02-crash.png"

var rider: CharacterBody3D
var ui: CanvasLayer
var camera: Camera3D

var _t := 0.0
var _phase := 0  # 0 = street alive for shot 1, 1 = wait for crash shot, 2 = done
var _order_time_left := 47.0
var _integrity := 100.0
var _spill_count := 0
var _crashes := 0
var _crash_cooldown := 0.0
var _crash_at := -1.0
var _crash_source := ""
var _crash_frame := false
var _cam_dist := 9.0
var _cam_height := 10.0

var _cars: Array = []  # each: {root, speed, dir, wheels, name}
var _peds: Array = []

# Fixed district points (also fed to the minimap, live).
var merchant_a := Vector3(-14, 0, -5.2)
var merchant_b := Vector3(22, 0, 5.2)
var customer_a := Vector3(16, 0, 5.2)
var customer_b := Vector3(-4, 0, -5.2)
var station_pos := Vector3(30, 0, -14)
var reward_pos := Vector3(6, 0.8, -1.6)
var blocker_positions := [Vector3(-2, 0, -1.0), Vector3(-1, 0, 10)]


func _ready() -> void:
	# --- light: sun + sky (the prototype has no lights in-repo) ---
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.78, 0.96)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_BG
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

	# --- ground ---
	_add_box(Vector3(0, -0.1, 0), Vector3(120, 0.2, 120), Color(0.48, 0.56, 0.44), "Ground")

	# --- Kenney roads (1x1 m tiles, x4) ---
	var road_straight: PackedScene = load("res://kenney/roads/road-straight.glb")
	var road_crossroad: PackedScene = load("res://kenney/roads/road-crossroad.glb")
	for ix in range(-7, 8):
		if ix == 0:
			continue
		_place_glb(road_straight, Vector3(ix * S, 0, 0), 0.0, S)
	for iz in range(-5, 6):
		if iz == 0:
			continue
		_place_glb(road_straight, Vector3(0, 0, iz * S), PI / 2.0, S)
	_place_glb(road_crossroad, Vector3(0, 0, 0), 0.0, S)

	# --- Kenney buildings (x4), both sides of the main street ---
	var b_a: PackedScene = load("res://kenney/commercial/building-a.glb")
	var b_b: PackedScene = load("res://kenney/commercial/building-b.glb")
	var b_c: PackedScene = load("res://kenney/commercial/building-c.glb")
	var b_d: PackedScene = load("res://kenney/commercial/building-d.glb")
	var b_e: PackedScene = load("res://kenney/commercial/building-e.glb")
	var b_f: PackedScene = load("res://kenney/commercial/building-f.glb")
	var lb_a: PackedScene = load("res://kenney/commercial/low-detail-building-a.glb")
	var lb_b: PackedScene = load("res://kenney/commercial/low-detail-building-b.glb")
	var lb_c: PackedScene = load("res://kenney/commercial/low-detail-building-c.glb")
	var sky_a: PackedScene = load("res://kenney/commercial/building-skyscraper-a.glb")
	var sky_b: PackedScene = load("res://kenney/commercial/building-skyscraper-b.glb")
	var awning: PackedScene = load("res://kenney/commercial/detail-awning.glb")
	_place_glb(b_b, Vector3(-14, 0, -7), 0.0, S)
	_place_glb(b_c, Vector3(-4, 0, -7), 0.0, S)
	_place_glb(lb_a, Vector3(8, 0, -7), 0.0, S)
	_place_glb(b_d, Vector3(18, 0, -7), 0.0, S)
	_place_glb(lb_b, Vector3(-22, 0, 7), PI, S)
	_place_glb(b_f, Vector3(-12, 0, 7), PI, S)
	_place_glb(b_a, Vector3(12, 0, 7), PI, S)
	_place_glb(awning, Vector3(12, 2.4, 5.0), PI, S)
	_place_glb(lb_c, Vector3(22, 0, 7), PI, S)
	_place_glb(sky_a, Vector3(-28, 0, -18), 0.0, S)
	_place_glb(sky_b, Vector3(28, 0, 14), 0.0, S)

	# --- real station scene, north side EAST end, far back ---
	var station_scene: PackedScene = load("res://scenes/station.tscn")
	var station := station_scene.instantiate() as Node3D
	station.position = Vector3(30, 0, -30)
	add_child(station)

	# --- Kenney street props (x4) ---
	var lamp: PackedScene = load("res://kenney/roads/light-curved.glb")
	_place_glb(lamp, Vector3(-20, 0, -3.2), PI, S)
	_place_glb(lamp, Vector3(-10, 0, 3.2), 0.0, S)
	_place_glb(lamp, Vector3(10, 0, -3.2), PI, S)
	_place_glb(lamp, Vector3(20, 0, 3.2), 0.0, S)
	_place_glb(lamp, Vector3(-3.2, 0, -12), -PI / 2.0, S)
	_place_glb(lamp, Vector3(3.2, 0, 12), PI / 2.0, S)
	var sign: PackedScene = load("res://kenney/roads/road-sign-stop.glb")
	_place_glb(sign, Vector3(3.6, 0, 3.6), PI, S)
	_place_glb(sign, Vector3(-3.6, 0, 3.6), PI / 2.0, S)
	_place_glb(sign, Vector3(3.6, 0, -3.6), -PI / 2.0, S)
	_place_glb(sign, Vector3(-3.6, 0, -3.6), 0.0, S)
	var cone: PackedScene = load("res://kenney/roads/construction-cone.glb")
	_place_glb(cone, Vector3(12, 0, 1.2), 0.0, S)
	_place_glb(cone, Vector3(12.8, 0, 0.6), 0.0, S)
	_place_glb(cone, Vector3(11.4, 0, 1.6), 0.0, S)
	_place_glb(cone, Vector3(12.4, 0, -0.4), 0.0, S)
	var barrier: PackedScene = load("res://kenney/roads/construction-barrier.glb")
	_place_glb(barrier, Vector3(13.6, 0, 1.8), PI / 2.0, S)

	# --- prototype markers: merchants (green cylinders), customers (orange cones) ---
	_add_marker(merchant_a, Color(0.2, 0.8, 0.3), "MerchantA", "cylinder")
	_add_marker(merchant_b, Color(0.2, 0.8, 0.3), "MerchantB", "cylinder")
	_add_marker(customer_a, Color(1.0, 0.6, 0.1), "CustomerA", "cone")
	_add_marker(customer_b, Color(1.0, 0.6, 0.1), "CustomerB", "cone")

	# --- prototype blockers (pink box + white ring), static for the shot ---
	for i in range(blocker_positions.size()):
		var p: Vector3 = blocker_positions[i]
		var b := MeshInstance3D.new()
		b.mesh = BoxMesh.new()
		b.mesh.size = Vector3(1.2, 2.0, 1.2)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.3, 0.5)
		b.material_override = mat
		b.name = "Blocker%d" % i
		b.position = Vector3(p.x, 1.0, p.z)
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

	# --- prototype roadside reward (gold sphere) + one normal prop pillar ---
	var reward := MeshInstance3D.new()
	reward.mesh = SphereMesh.new()
	reward.mesh.radius = 0.7
	reward.mesh.height = 1.4
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(1.0, 0.9, 0.2)
	reward.material_override = rmat
	reward.name = "RoadsideReward"
	reward.position = reward_pos
	add_child(reward)
	_spawn_normal_prop(Vector3(-8, 0, 1.8))

	# --- TRAFFIC: Kenney Car Kit, native scale (measured: sedan
	# 1.50w x 1.45h x 2.55l; roof below the 1.9 m rider's head, correct
	# for a sedan; the kit's stubby cartoon proportions, not the x4 city
	# factor — x4 would make a 6 m wide car). Cars are StaticBody3D
	# so the rider's move_and_slide really collides with them.
	# Lanes are right-hand traffic: eastbound south lane (z=+1.6),
	# westbound north lane (z=-1.6); the slow crash car shares the
	# rider's line (z=0) — a rear-end in the same lane.
	_spawn_car("sedan", Vector3(-8, 0, 0), PI / 2.0, 3.0, Vector3(1, 0, 0), "CrashCar")
	_spawn_car("taxi", Vector3(14, 0, -1.6), -PI / 2.0, 6.0, Vector3(-1, 0, 0), "Taxi")
	_spawn_car("van", Vector3(1.2, 0, -16), PI, 5.0, Vector3(0, 0, -1), "Van")
	_spawn_car("truck", Vector3(-1.2, 0, 16), 0.0, 5.0, Vector3(0, 0, 1), "Truck")
	_spawn_car("police", Vector3(24, 0, 1.6), PI / 2.0, 7.0, Vector3(1, 0, 0), "Police")

	# --- PEDESTRIANS: Kenney Animated Characters, scale 0.5 (native
	# 3.76 m tall -> 1.88 m). NO walk clip exists in the pack, so they
	# stand on the sidewalk playing Idle. No collision shapes: they
	# never block and never take part in collisions.
	_spawn_pedestrian(Vector3(-10, 0, -5.5), 0.0, "res://kenney/characters/Skins/skaterMaleA.png", "PedA")
	_spawn_pedestrian(Vector3(8, 0, 5.5), PI, "res://kenney/characters/Skins/skaterFemaleA.png", "PedB")
	_spawn_pedestrian(Vector3(-2, 0, 5.5), PI, "", "PedC")
	_spawn_pedestrian(Vector3(18, 0, -5.5), 0.0, "", "PedD")

	# --- REAL prototype rider (yellow box rider + delivery box) ---
	var rider_scene: PackedScene = load("res://scenes/rider.tscn")
	rider = rider_scene.instantiate() as CharacterBody3D
	var vehicle: Dictionary = (GameData.VEHICLES["e_bike"] as Dictionary).duplicate(true)
	vehicle["id"] = "e_bike"
	rider.apply_vehicle(vehicle)
	rider.position = Vector3(-20, 0, 0)
	rider.heading = PI / 2.0
	rider.rotation.y = PI / 2.0
	add_child(rider)

	# --- camera: same third-person panoramic rig as main.gd ---
	camera = Camera3D.new()
	camera.name = "ShotCamera"
	add_child(camera)
	_snap_camera()

	# --- REAL UI (ui.tscn + minimap), CJK font so Chinese renders ---
	var ui_scene: PackedScene = load("res://scenes/ui.tscn")
	ui = ui_scene.instantiate() as CanvasLayer
	add_child(ui)
	_apply_cjk_font(ui)
	ui.float_label.visible = false
	ui.set_message("已取餐 热汤单，送去客户处（小地图橙三角），注意别洒！")
	ui.set_inventory("局外仓库：空")

	# Hold D: the rider's input is world-space, W drives north (-Z),
	# D drives east (+X) along the main street.
	_press_key(KEY_D, true)
	print("SHOTS2_READY cars=", _cars.size(), " peds=", _peds.size())


func _process(delta: float) -> void:
	_t += delta
	# Move traffic in _process: StaticBody3D keeps transform changes made
	# outside the physics step (verified in isolation: 3.00 m in 1.0 s),
	# while AnimatableBody3D position writes were silently reverted in
	# this heavy scene. Wheels spin at v / r (r = 0.30 m).
	for c in _cars:
		var root: StaticBody3D = c["root"]
		root.global_position += c["dir"] * c["speed"] * delta
		var p: Vector3 = root.global_position
		if c["dir"].x > 0.0 and p.x > 30.0:
			p.x = -30.0
		elif c["dir"].x < 0.0 and p.x < -30.0:
			p.x = 30.0
		elif c["dir"].z > 0.0 and p.z > 22.0:
			p.z = -22.0
		elif c["dir"].z < 0.0 and p.z < -22.0:
			p.z = 22.0
		root.global_position = p
		var w := float(c["speed"]) / 0.30
		for wheel in (c["wheels"] as Array):
			(wheel as MeshInstance3D).rotation.x -= w * delta
	_crash_cooldown = maxf(0.0, _crash_cooldown - delta)
	_order_time_left = maxf(0.0, _order_time_left - delta)
	_check_crash()
	# Prototype spill rule, exact numbers: shake hits 100 -> integrity
	# -20, shake reset to 60. Suppressed while the crash cooldown runs:
	# a crash already applies its spill once inline, so a second spill
	# must not fire while the rider is still recovering.
	if _crash_cooldown <= 0.0 and rider.shake >= GameData.BALANCE["spill_threshold"]:
		rider.shake = GameData.BALANCE["spill_reset"]
		_integrity = SliceLogic.spill_integrity(_integrity, 20.0)
		_spill_count += 1
		ui.set_message("洒了！完好度 -20%，稳住骑行让晃动回落。")
	_update_hud()
	_update_camera(delta)
	if _phase == 0 and _t >= 1.2:
		_capture(SHOT1)
		_phase = 1
	elif _phase == 1 and _crash_at >= 0.0 and _t >= _crash_at + 0.5:
		_capture(SHOT2)
		_phase = 2
		print("SHOTS2_DONE crashes=", _crashes, " source=", _crash_source, " integrity=", _integrity, " time_left=", _order_time_left)
		get_tree().quit()
	elif _t > 8.0:
		print("SHOTS2_TIMEOUT crashes=", _crashes, " source=", _crash_source)
		_capture(SHOT2)
		get_tree().quit()


func _check_crash() -> void:
	if _crash_cooldown > 0.0 or _phase == 2:
		return
	# Primary: real physics slide collision with a traffic car.
	for i in range(rider.get_slide_collision_count()):
		var col := rider.get_slide_collision(i).get_collider()
		if col != null and (col as Node).is_in_group("traffic_car"):
			_do_crash("slide:" + (col as Node).name)
			return
	# Fallback: distance to the designated crash car only (other lanes
	# pass within 2 m, so a generic distance check would false-fire).
	var crash_car: Dictionary = _cars[0]
	var cr: StaticBody3D = crash_car["root"]
	var dx: float = absf(cr.global_position.x - rider.global_position.x)
	var dz: float = absf(cr.global_position.z - rider.global_position.z)
	if dz < 1.0 and dx < 2.2:
		_do_crash("distance:CrashCar")


func _do_crash(source: String) -> void:
	_crash_cooldown = 2.0
	_crashes += 1
	_crash_at = _t
	_crash_source = source
	# Impact speed before the stop: a hard hit (>= 5 m/s, i.e. a real
	# rear-end at riding speed) spills the goods once, using the
	# prototype's spill numbers (-20% integrity, shake reset to 60).
	# A slow nudge only shakes the rider.
	var impact_speed: float = rider.current_speed
	rider.shake = minf(100.0, rider.shake + 45.0)
	rider.stamina = maxf(0.0, rider.stamina - 25.0)
	_order_time_left = maxf(0.0, _order_time_left - 5.0)
	rider.current_speed = 0.0
	rider.velocity = Vector3.ZERO
	var spilled := false
	if impact_speed >= 5.0 or rider.shake >= GameData.BALANCE["spill_threshold"]:
		rider.shake = GameData.BALANCE["spill_reset"]
		_integrity = SliceLogic.spill_integrity(_integrity, 20.0)
		_spill_count += 1
		spilled = true
	if spilled:
		ui.set_message("被车撞了！完好度 -20%，体力 -25，时间 -5 秒！")
	else:
		ui.set_message("被车撞了！晃动 +45，体力 -25，时间 -5 秒！")
	print("CRASH t=", "%.2f" % _t, " source=", source, " impact_speed=", "%.1f" % impact_speed, " rider=", rider.global_position, " shake=", rider.shake, " integrity=", _integrity, " stamina=", rider.stamina, " time_left=", _order_time_left)


func _spawn_car(model: String, pos: Vector3, rot_y: float, speed: float, dir: Vector3, car_name: String) -> void:
	var root := StaticBody3D.new()
	root.name = car_name
	root.add_to_group("traffic_car")
	root.position = pos
	root.rotation.y = rot_y
	add_child(root)
	var scene: PackedScene = load("res://kenney/cars/%s.glb" % model)
	var body := scene.instantiate() as Node3D
	root.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 1.3, 2.55)
	shape.shape = box
	shape.position = Vector3(0, 0.7, 0)
	root.add_child(shape)
	var wheels: Array = []
	for c in _all_nodes(body):
		if c is MeshInstance3D and "wheel" in (c as MeshInstance3D).name.to_lower():
			wheels.append(c)
	_cars.append({"root": root, "speed": speed, "dir": dir, "wheels": wheels, "name": car_name})
	print("CAR ", car_name, " model=", model, " wheels=", wheels.size(), " pos=", pos)


func _spawn_pedestrian(pos: Vector3, rot_y: float, skin_path: String, ped_name: String) -> void:
	var scene: PackedScene = load("res://kenney/characters/characterMedium.glb")
	var n := scene.instantiate() as Node3D
	n.name = ped_name
	n.position = pos
	n.rotation.y = rot_y
	n.scale = Vector3(0.5, 0.5, 0.5)
	add_child(n)
	var player: AnimationPlayer = null
	var mesh_node: MeshInstance3D = null
	for c in _all_nodes(n):
		if c is AnimationPlayer:
			player = c
		if c is MeshInstance3D:
			mesh_node = c
	if skin_path != "":
		var base_mat := mesh_node.mesh.surface_get_material(0) as StandardMaterial3D
		if base_mat != null:
			var mat := base_mat.duplicate() as StandardMaterial3D
			mat.albedo_texture = load(skin_path) as Texture2D
			mesh_node.set_surface_override_material(0, mat)
	else:
		var base_mat2 := mesh_node.mesh.surface_get_material(0) as StandardMaterial3D
		if base_mat2 != null:
			var mat2 := base_mat2.duplicate() as StandardMaterial3D
			mat2.albedo_color = Color(0.95, 0.95, 0.95)
			mesh_node.set_surface_override_material(0, mat2)
	if player != null:
		player.play("Root_001|Root|Idle")
	_peds.append({"node": n, "skin": skin_path, "name": ped_name})
	print("PED ", ped_name, " skin=", skin_path, " player=", player != null)


func _update_camera(delta: float) -> void:
	if camera == null or rider == null:
		return
	var forward: Vector3 = rider.transform.basis.z
	var cam_target := rider.global_position - forward * _cam_dist + Vector3(0, _cam_height, 0)
	camera.global_position = camera.global_position.lerp(cam_target, 1.0 - pow(0.001, delta))
	camera.look_at(rider.global_position + forward * 4.0 + Vector3(0, 1.0, 0), Vector3.UP)


func _snap_camera() -> void:
	var forward: Vector3 = rider.transform.basis.z
	camera.global_position = rider.global_position - forward * _cam_dist + Vector3(0, _cam_height, 0)
	camera.look_at(rider.global_position + forward * 4.0 + Vector3(0, 1.0, 0), Vector3.UP)


func _update_hud() -> void:
	if ui == null or rider == null:
		return
	var order_name: String = GameData.ORDER_TYPES["hot_soup"]["name"]
	var countdown_text := "最近截止：%.0f 秒" % _order_time_left
	var order_text := "订单（容量 1/2）\n下一单：%s，剩余 %.0f 秒，完好度 %.0f%%\n还有 0 单在途（停下看全单）\n" % [order_name, _order_time_left, _integrity]
	var vehicle_name: String = GameData.VEHICLES["e_bike"]["name"]
	var status_text := "车辆：%s（末端，技能 3/6，驱赶 1/2）\n金币 0 | 声誉 100 | 已送 0\n宠物：挂载座位，疲劳 %.0f%%（100%% 休息）\n局外仓库：空" % [vehicle_name, rider.pet_fatigue]
	ui.set_hud(countdown_text, order_text, status_text, rider.shake, rider.nitrogen, rider.stamina, _order_time_left < 15.0)
	(ui.minimap as Control).call("set_data", {
		"player": rider.global_position,
		"heading": rider.heading,
		"speed": rider.current_speed,
		"merchants": [merchant_a, merchant_b],
		"customers": [customer_a, customer_b],
		"station": station_pos,
		"reward": reward_pos,
		"reward_visible": true,
		"exploration": Vector3.ZERO,
		"exploration_visible": false,
		"blockers": blocker_positions,
		"target": customer_a,
		"has_target": true,
	})


func _capture(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("CAPTURE ", path, " err=", err, " size=", img.get_size(),
		" rider=", rider.global_position, " cam=", camera.global_position,
		" integrity=", _integrity, " time_left=", _order_time_left)


func _press_key(keycode: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _apply_cjk_font(node: Node) -> void:
	var sysfont := SystemFont.new()
	sysfont.font_names = ["Noto Serif CJK SC", "Noto Sans CJK SC", "Noto Sans CJK"]
	if node is Label or node is Button or node is OptionButton:
		(node as Control).add_theme_font_override("font", sysfont)
	for child in node.get_children():
		_apply_cjk_font(child)


func _place_glb(scene: PackedScene, pos: Vector3, rot_y: float, scl: float) -> Node3D:
	var n := scene.instantiate() as Node3D
	n.position = pos
	n.rotation.y = rot_y
	n.scale = Vector3(scl, scl, scl)
	add_child(n)
	return n


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


func _spawn_normal_prop(pos: Vector3) -> void:
	var tier: Dictionary = GameData.PROP_TIERS["normal"]
	var root := Node3D.new()
	root.name = "Prop_demo"
	root.position = pos
	add_child(root)
	var mesh_node := MeshInstance3D.new()
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
	var pillar := MeshInstance3D.new()
	pillar.mesh = CylinderMesh.new()
	pillar.mesh.top_radius = 0.4
	pillar.mesh.bottom_radius = 0.4
	pillar.mesh.height = float(tier["pillar_height"])
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color(tier["pillar_colour"], 0.25)
	pillar_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pillar.material_override = pillar_mat
	pillar.position.y = float(tier["pillar_height"]) / 2.0
	root.add_child(pillar)


func _all_nodes(n: Node) -> Array:
	var out = [n]
	for ch in n.get_children():
		out += _all_nodes(ch)
	return out
