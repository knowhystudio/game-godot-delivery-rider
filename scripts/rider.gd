extends CharacterBody3D
## Rider + vehicle as one swappable scene.
## Changing vehicle only changes parameters / appearance (see apply_vehicle).
## Pet is an appearance-only follower. No real names, no licensed assets:
## everything here is a built-in primitive mesh with a plain colour.

var vehicle_id := "e_bike"
var max_speed := 10.0
var accel := 18.0
var spill_resist := 0.0
var damping_factor := 1.0
var nitro_refill_factor := 1.0

var shake := 0.0
var nitrogen := 100.0
var stamina := 100.0
var heading := 0.0
var tool_cooldown_left := 0.0
var tool_cooldown := 3.0
var tool_charges := 1
var tool_charges_max := 1
var tool_slow_left := 0.0
var nitro_boost_left := 0.0
var grip_part := false
var pet_fatigue := 0.0
var pet_active := true
var nitrogen_drain := 30.0
var aiming := false
var current_speed := 0.0

var _body: MeshInstance3D
var _box_mesh: MeshInstance3D
var _pet: MeshInstance3D
var _tool_cone: MeshInstance3D
var _prev_heading := 0.0


func _ready() -> void:
	_body = MeshInstance3D.new()
	_body.mesh = BoxMesh.new()
	_body.mesh.size = Vector3(0.9, 1.1, 1.6)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(1.0, 0.85, 0.1)
	_body.material_override = body_mat
	_body.position.y = 0.7
	add_child(_body)

	var head := MeshInstance3D.new()
	head.mesh = SphereMesh.new()
	head.mesh.radius = 0.32
	head.mesh.height = 0.64
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(1.0, 0.85, 0.1)
	head.material_override = head_mat
	head.position = Vector3(0, 1.6, 0.2)
	add_child(head)

	_box_mesh = MeshInstance3D.new()
	_box_mesh.mesh = BoxMesh.new()
	_box_mesh.mesh.size = Vector3(0.9, 0.9, 0.7)
	var box_mat := StandardMaterial3D.new()
	box_mat.albedo_color = Color(1.0, 0.85, 0.1)
	_box_mesh.material_override = box_mat
	_box_mesh.position = Vector3(0, 1.0, -0.95)
	add_child(_box_mesh)

	# Pet seat: a small follower, appearance only, no gameplay effect.
	_pet = MeshInstance3D.new()
	_pet.mesh = SphereMesh.new()
	_pet.mesh.radius = 0.22
	_pet.mesh.height = 0.44
	var pet_mat := StandardMaterial3D.new()
	pet_mat.albedo_color = Color(0.9, 0.6, 0.3)
	_pet.material_override = pet_mat
	add_child(_pet)

	# Aim fan: semi-transparent, only visible in aim mode.
	_tool_cone = MeshInstance3D.new()
	_tool_cone.mesh = CylinderMesh.new()
	_tool_cone.mesh.top_radius = 0.3
	_tool_cone.mesh.bottom_radius = 3.0
	_tool_cone.mesh.height = 7.0
	var cone_mat := StandardMaterial3D.new()
	cone_mat.albedo_color = Color(1.0, 0.85, 0.1, 0.25)
	cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tool_cone.material_override = cone_mat
	_tool_cone.visible = false
	add_child(_tool_cone)

	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(1.0, 1.6, 1.8)
	shape.position.y = 0.8
	add_child(shape)


func apply_vehicle(vehicle: Dictionary) -> void:
	vehicle_id = vehicle.get("id", vehicle_id)
	max_speed = float(vehicle.get("speed", max_speed))
	accel = float(vehicle.get("accel", accel))
	spill_resist = float(vehicle.get("spill_resist", spill_resist))
	if _body:
		var mat := _body.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = vehicle.get("colour", Color.YELLOW)


func _physics_process(delta: float) -> void:
	aiming = Input.is_key_pressed(KEY_TAB)
	if _tool_cone:
		_tool_cone.visible = aiming
		# Fan points forward (-Z), lying flat in front of the rider.
		_tool_cone.position = Vector3(0, 0.4, 3.5)
		_tool_cone.rotation.x = deg_to_rad(90.0)

	var input_x := 0.0
	var input_z := 0.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_z += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_x += 1.0
	var input_vec := Vector2(input_x, input_z)
	if input_vec.length() > 0.0:
		input_vec = input_vec.normalized()

	# Third-person: input is in world space for this slice; the camera
	# follows behind the rider, so W always reads as "forward on screen"
	# when the rider is facing away from the camera start position.
	var boosting := Input.is_key_pressed(KEY_SHIFT) and nitrogen > 0.0
	var target_speed := max_speed * (1.5 if boosting else 1.0)
	# Move + drive-away never stack at full power: after a tool use the
	# rider is slowed for tool_slow_secs (see try_tool).
	if tool_slow_left > 0.0:
		target_speed *= float(GameData.BALANCE["tool_slow_rate"])
	# Nitro boost window (nitro_can behaviour): faster, grip halved.
	if nitro_boost_left > 0.0:
		target_speed *= 1.2
		nitro_boost_left = maxf(0.0, nitro_boost_left - delta)
	tool_slow_left = maxf(0.0, tool_slow_left - delta)
	# Overall speed cap: 130% of base max speed, whatever stacks.
	target_speed = SliceLogic.clamp_speed(max_speed, target_speed)
	if input_vec.length() > 0.0:
		var target_heading := atan2(input_vec.x, input_vec.y)
		# Turn smoothly toward the input direction.
		var diff := wrapf(target_heading - heading, -PI, PI)
		heading += clamp(diff, -6.0 * delta, 6.0 * delta)
		rotation.y = heading
		current_speed = move_toward(current_speed, target_speed, accel * delta)
	else:
		current_speed = move_toward(current_speed, 0.0, accel * delta)

	if boosting and current_speed > 0.5:
		nitrogen = maxf(0.0, nitrogen - nitrogen_drain * delta)
	else:
		nitrogen = minf(100.0, nitrogen + GameData.BALANCE["nitrogen_refill_per_sec"] * nitro_refill_factor * delta)

	# Mountain / slope zone (west side, x < -30): slower, costs stamina.
	# Grip part behaviour: slope penalty eased, stamina drain halved.
	var on_slope := global_position.x < -30.0
	if on_slope and current_speed > 0.5:
		stamina = maxf(0.0, stamina - (2.0 if grip_part else 4.0) * delta)
		current_speed = minf(current_speed, max_speed * (0.95 if grip_part else 0.8))
	elif global_position.distance_to(Vector3.ZERO) < 12.0:
		# Near the station: rest / resupply.
		stamina = minf(100.0, stamina + 10.0 * delta)

	# Shake: turning fast, going fast, or hitting something adds shake.
	# Smooth, slow riding lets it decay (forgiveness, not instant spill).
	# During a nitro boost the grip bonus is halved (mutual exclusion).
	var turn_rate := absf(wrapf(heading - _prev_heading, -PI, PI)) / maxf(delta, 0.001)
	_prev_heading = heading
	var effective_resist := spill_resist * (0.5 if nitro_boost_left > 0.0 else 1.0)
	var shake_gain := (current_speed * 0.35 + turn_rate * 0.6) * (1.0 - effective_resist) * damping_factor
	if current_speed > 1.0:
		shake += shake_gain * delta
	else:
		shake = maxf(0.0, shake - GameData.BALANCE["shake_decay_per_sec"] * delta)
	shake = clampf(shake, 0.0, 100.0)

	# Model front is +Z (head at +Z, delivery box at -Z), so forward is +basis.z.
	var forward := transform.basis.z
	velocity = forward * current_speed
	# If the player steers with A/D only (no W), keep the rider turning in place.
	if input_vec.length() == 0.0:
		velocity = Vector3.ZERO
	move_and_slide()
	if get_slide_collision_count() > 0 and current_speed > 5.0:
		shake = minf(100.0, shake + 8.0)

	tool_cooldown_left = maxf(0.0, tool_cooldown_left - delta)
	if tool_cooldown_left <= 0.0 and tool_charges < tool_charges_max:
		tool_charges = tool_charges_max

	# Pet: dedicated mount slot on the vehicle (side seat), NOT a cargo
	# slot. Pet never picks up orders and never blocks drive-away: it is
	# not in any order / blocker list. Fatigue: fast riding tires the pet;
	# at 100 it rests (hidden) until stamina recovers near the station.
	if current_speed > 8.0:
		pet_fatigue = minf(100.0, pet_fatigue + 2.0 * delta)
	elif global_position.distance_to(Vector3.ZERO) < 12.0:
		pet_fatigue = maxf(0.0, pet_fatigue - 10.0 * delta)
	pet_active = pet_fatigue < 100.0
	if _pet:
		_pet.visible = pet_active
		# Mount slot: fixed side offset from the rider, not behind in cargo.
		var side := transform.basis.x
		var pet_target := global_position + side * 0.7 + Vector3(0, 0.9, 0)
		_pet.global_position = _pet.global_position.lerp(pet_target, 1.0 - pow(0.001, delta))


func try_tool() -> bool:
	# Second charge (tool_slot behaviour) is a charge, not just cooldown.
	if tool_charges <= 0:
		return false
	if nitrogen < float(GameData.BALANCE["tool_nitrogen_cost"]) or stamina < float(GameData.BALANCE["tool_stamina_cost"]):
		return false
	tool_charges -= 1
	nitrogen -= float(GameData.BALANCE["tool_nitrogen_cost"])
	stamina -= float(GameData.BALANCE["tool_stamina_cost"])
	tool_cooldown_left = tool_cooldown
	tool_slow_left = float(GameData.BALANCE["tool_slow_secs"])
	return true
