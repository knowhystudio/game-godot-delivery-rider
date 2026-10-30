extends Node3D
## Main run scene: city, station, orders, time, weather (rain corner in city),
## minimap. Wires rider + city + station + UI together.
## No code here invents numbers: all numbers come from GameData / SliceLogic.

var rider: CharacterBody3D
var city: Node3D
var ui: CanvasLayer
var camera: Camera3D

var orders := {}
var coins := 0
var reputation := 100
var delivered_count := 0
var spill_count := 0
var late_count := 0
var capacity_bonus := 0
var upgrade_offered := false
var phase := "playing"  # playing | upgrade | settled
var elapsed := 0.0
var message_timer := 0.0
var inventory: Array = []
var collected_run: Array = []
var extracted_pending: Array = []
var _particles: Array = []
var current_vehicle_id := "e_bike"
var difficulty := 0
var extraction_registered := false
var urge_cooldown_left := 0.0
var spill_shield_left := 0.0
var settlement_step := 0
var settlement_sync_left := 0.0
var settlement_text_step2 := ""
var settlement_text_step3 := ""
var equipped_skills: Array = ["drive_away", "urge", "nitrogen"]
var tuning_spill_damage := 20.0
var tuning_tool_cooldown := 3.0
var _slowmo_until := 0
var _pickup_progress: Dictionary = {}


func _ready() -> void:
	rider = $Rider
	city = $City
	ui = $UI
	# Copy, never mutate the shared GameData table.
	var vehicle: Dictionary = (GameData.VEHICLES[current_vehicle_id] as Dictionary).duplicate(true)
	vehicle["id"] = current_vehicle_id
	rider.apply_vehicle(vehicle)
	rider.position = Vector3(0, 0, 10)
	camera = Camera3D.new()
	camera.name = "ThirdPersonCamera"
	add_child(camera)
	_reset_orders()
	ui.accept_pressed.connect(_on_accept)
	ui.action_pressed.connect(_do_action)
	ui.urge_pressed.connect(_do_urge)
	ui.report_pressed.connect(_do_report)
	ui.tool_pressed.connect(_do_tool)
	ui.end_shift_pressed.connect(_on_end_shift)
	ui.upgrade_chosen.connect(_on_upgrade)
	ui.restart_pressed.connect(_on_restart)
	ui.vehicle_selected.connect(_on_vehicle_selected)
	ui.settlement_next_pressed.connect(_advance_settlement)
	ui.settlement_skip_pressed.connect(_on_settlement_skip)
	ui.abandon_pressed.connect(_on_abandon)
	ui.extract_pressed.connect(_do_extract)
	ui.discard_legendary_pressed.connect(_on_discard_legendary)
	ui.tuning_applied.connect(_on_tuning_applied)
	ui.set_message("先接单：点左侧接单按钮，或按 1/2/3。WASD 移动，E 取餐/送达。")


func _reset_orders() -> void:
	orders = {
		"light_meal": _new_order("light_meal", "A", "A", 2.0),
		"hot_soup": _new_order("hot_soup", "B", "B", 8.0),
		"family_bag": _new_order("family_bag", "C", "C", 4.0),
	}
	coins = 0
	reputation = 100
	delivered_count = 0
	spill_count = 0
	late_count = 0
	capacity_bonus = 0
	upgrade_offered = false
	phase = "playing"
	collected_run = []
	extracted_pending = []
	extraction_registered = false
	settlement_step = 0
	urge_cooldown_left = 0.0
	spill_shield_left = 0.0
	_pickup_progress = {}
	if city and city.has_method("merchant_pos"):
		city.reward_taken = false
		if city.reward_node:
			city.reward_node.visible = true
		city.exploration_taken = false
		if city.exploration_node:
			city.exploration_node.visible = true
		if city.extraction_node:
			city.extraction_node.visible = true
		if city.has_method("reset_props"):
			city.reset_props()
	# Inventory effects apply AFTER the coin reset, so a starter pack
	# consumed at the start of a new run actually adds its coins.
	_apply_inventory()


func _new_order(type_key: String, merchant_key: String, customer_key: String, prep: float) -> Dictionary:
	var t: Dictionary = GameData.ORDER_TYPES[type_key]
	# Next-run difficulty rises slightly after successful extraction
	# (anti-snowball): time limits shrink up to 10%, never below 90%.
	var diff_rate := minf(float(GameData.EXTRACTION["difficulty_max"]), float(difficulty) * float(GameData.EXTRACTION["difficulty_step"]))
	var limit := float(t["time_limit"]) * (1.0 - diff_rate)
	return {
		"type": type_key, "name": t["name"], "pay": t["pay"],
		"time_limit": limit, "time_left": limit,
		"spill_prone": float(t["spill_prone"]), "vehicle_hint": t["vehicle_hint"],
		"merchant": merchant_key, "customer": customer_key,
		"state": "available", "prep_left": prep, "prep_total": prep,
		"merchant_wait": 0.0, "urge_count": 0, "reported": false,
		"over_urged": false, "integrity": 100.0,
	}


func capacity() -> int:
	# Capacity bonus is capped at +2 total, so capacity sources do not
	# stack without limit (golden_box + big_box upgrade + base).
	return int(GameData.VEHICLES[current_vehicle_id]["capacity"]) + mini(capacity_bonus, 2)


func _on_vehicle_selected(vehicle_id: String) -> void:
	if not GameData.VEHICLES.has(vehicle_id):
		return
	current_vehicle_id = vehicle_id
	var vehicle: Dictionary = (GameData.VEHICLES[vehicle_id] as Dictionary).duplicate(true)
	vehicle["id"] = vehicle_id
	rider.apply_vehicle(vehicle)
	_apply_inventory()
	ui.set_message("已选 %s（%s）。大车是干线/中转车，进不了窄巷、上不了楼，最后100米必须换小车或步行。" % [vehicle["name"], vehicle["role"]])


func carried_count() -> int:
	var n := 0
	for o in orders.values():
		if o["state"] == "carried":
			n += 1
	return n


func accepted_count() -> int:
	var n := 0
	for o in orders.values():
		if o["state"] == "accepted" or o["state"] == "carried":
			n += 1
	return n


func _on_accept(order_key: String) -> void:
	if phase != "playing":
		return
	if not orders.has(order_key):
		return
	var o: Dictionary = orders[order_key]
	if o["state"] != "available":
		ui.set_message("这单已经接了或送完了。")
		return
	if not SliceLogic.vehicle_can_take(current_vehicle_id, order_key):
		ui.set_message("这单最后100米要小车/步行，大车（干线/中转）进不了窄巷、上不了楼，会软锁。请先换回小车再接。")
		return
	# Red blocking for impossible time limits: if even driving straight
	# at max speed cannot make it in 1.5x the straight-line time, refuse.
	var dist: float = city.merchant_pos(o["merchant"]).distance_to(city.customer_pos(o["customer"]))
	if float(o["time_limit"]) < dist / rider.max_speed * 1.5:
		ui.set_message("这单时限不可能完成，已拦截（红色拦截：距离 %.0f 米，时限 %.0f 秒）。" % [dist, o["time_limit"]])
		return
	if accepted_count() >= capacity():
		ui.set_message("餐箱满了（容量 %d），先送一单再接。" % capacity())
		return
	o["state"] = "accepted"
	ui.set_message("已接 %s，去商家取餐（小地图绿方块）。" % o["name"])


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E:
				_do_action()
			KEY_F:
				_do_urge()
			KEY_R:
				_do_report()
			KEY_SPACE, KEY_Q:
				_do_tool()
			KEY_1:
				_on_accept("light_meal")
			KEY_2:
				_on_accept("hot_soup")
			KEY_3:
				_on_accept("family_bag")


func _near(pos: Vector3, radius: float) -> bool:
	return rider.global_position.distance_to(pos) < radius


func _order_near_merchant(o: Dictionary) -> bool:
	return _near(city.merchant_pos(o["merchant"]), 6.0)


func _order_near_customer(o: Dictionary) -> bool:
	return _near(city.customer_pos(o["customer"]), 6.0)


func _do_action() -> void:
	if phase != "playing":
		return
	# Deliver first if standing at a customer for a carried order.
	for o in orders.values():
		if o["state"] == "carried" and _order_near_customer(o):
			_deliver(o)
			return
	# Then pick up if standing at a merchant.
	for o in orders.values():
		if o["state"] == "accepted" and _order_near_merchant(o):
			if o["prep_left"] > 0.0:
				ui.set_message("商家备餐中，还剩 %.0f 秒。按 F 催一次效果最好，催多了会适得其反。" % o["prep_left"])
				return
			o["state"] = "carried"
			ui.set_message("已取餐 %s，送去客户处（小地图橙三角），注意别洒！" % o["name"])
			return
	ui.set_message("附近没有可取餐的商家或可送达的客户，先看小地图走过去。")


func _do_urge() -> void:
	if phase != "playing":
		return
	# Urge and drive-away are separate buttons with separate cooldowns.
	if urge_cooldown_left > 0.0:
		ui.set_message("催商家冷却中，还剩 %.0f 秒（与驱赶分开计算）。" % urge_cooldown_left)
		return
	if rider.stamina < float(GameData.BALANCE["urge_stamina_cost"]):
		ui.set_message("体力不足，催商家需要 10 体力。")
		return
	for o in orders.values():
		if o["state"] == "accepted" and _order_near_merchant(o) and o["prep_left"] > 0.0:
			rider.stamina -= float(GameData.BALANCE["urge_stamina_cost"])
			urge_cooldown_left = float(GameData.BALANCE["urge_cooldown"])
			var before: float = o["prep_left"]
			o["prep_left"] = SliceLogic.urge_remaining(before, int(o["urge_count"]))
			o["urge_count"] += 1
			if o["urge_count"] >= 3:
				o["over_urged"] = true
				ui.set_message("催过头了！商家反而慢了，还可能给差评。")
			elif o["urge_count"] == 1:
				ui.set_message("催促有效！备餐从 %.0f 秒降到 %.0f 秒。" % [before, o["prep_left"]])
			else:
				ui.set_message("再催效果变小了，备餐还剩 %.0f 秒。" % o["prep_left"])
			return
	ui.set_message("只有在商家门口、备餐还没好时催促才有用。")


func _do_report() -> void:
	if phase != "playing":
		return
	for o in orders.values():
		if o["state"] == "accepted" and _order_near_merchant(o) and not o["reported"]:
			o["reported"] = true
			ui.set_message("已举报一次：如果是商家原因超时，结算时可部分抵扣。")
			return
	ui.set_message("没有可举报的等待订单，或已经举报过了（每单一次）。")


func _do_extract() -> void:
	if phase != "playing":
		return
	if city.extraction_node == null or not _near(city.extraction_node.global_position, 6.0):
		ui.set_message("去提取点（灰色方块，地图南侧）登记带出，登记要花 10 秒总时间。")
		return
	if extraction_registered:
		ui.set_message("已经登记过了。")
		return
	extraction_registered = true
	for o in orders.values():
		if o["state"] == "accepted" or o["state"] == "carried":
			o["time_left"] = float(o["time_left"]) - float(GameData.EXTRACTION["extraction_point_time_cost"])
	ui.set_message("已在提取点登记！结算时可带出道具（已扣除 10 秒总时间）。")


func _do_tool() -> void:
	if phase != "playing":
		return
	if not rider.try_tool():
		ui.set_message("驱赶冷却中，或氮气不足 15 / 体力不足 5（与催商家分开计算）。")
		return
	var forward: Vector3 = rider.transform.basis.z
	var hit := false
	for b in city.blockers:
		var node: MeshInstance3D = b["node"]
		var to_blocker: Vector3 = node.global_position - rider.global_position
		to_blocker.y = 0
		if to_blocker.length() > SliceLogic.clamp_range(float(GameData.BALANCE["tool_range"]), float(GameData.BALANCE["tool_range"])):
			continue
		var angle := rad_to_deg(forward.angle_to(to_blocker.normalized()))
		if angle <= GameData.BALANCE["tool_fan_degrees"] / 2.0 + 30.0:
			node.global_position += forward * 6.0 + Vector3(0, 0, 0)
			b["away_until"] = elapsed + 20.0
			hit = true
	ui.set_message("驱赶！" if hit else "驱赶落空了，前方扇形范围内没有障碍。")


func _deliver(o: Dictionary) -> void:
	var on_time: bool = o["time_left"] > 0.0
	var late: bool = not on_time
	var merchant_offset: bool = o["reported"] and o["merchant_wait"] > 0.0
	var pay := SliceLogic.settlement_pay(int(o["pay"]), on_time, o["integrity"] >= 100.0, float(o["integrity"]), late, merchant_offset)
	var review := SliceLogic.review_for(on_time, float(o["integrity"]), bool(o["over_urged"]))
	coins += pay
	if review == "好评":
		reputation += 2
	elif review == "差评":
		reputation -= 5
	if late:
		late_count += 1
	o["state"] = "delivered"
	delivered_count += 1
	var note := ""
	if merchant_offset:
		note = "（商家等待已部分抵扣超时损失）"
	ui.set_message("送达 %s！收入 %d，评价 %s，完好度 %.0f%%%s" % [o["name"], pay, review, o["integrity"], note])
	if delivered_count == 2 and not upgrade_offered:
		upgrade_offered = true
		phase = "upgrade"
		ui.show_upgrade()


func _on_upgrade(upgrade_id: String) -> void:
	match upgrade_id:
		"big_box":
			capacity_bonus += 1
			ui.set_message("升级：大餐箱，容量 +1。")
		"damping":
			rider.damping_factor *= 0.7
			ui.set_message("升级：减震，晃动积累 -30%。")
		"nitro_refill":
			rider.nitro_refill_factor *= 1.5
			ui.set_message("升级：氮气快充，恢复 +50%。")
	ui.hide_upgrade()
	phase = "playing"


func _inventory_text() -> String:
	if inventory.is_empty():
		return "局外仓库：空"
	var parts: Array = []
	for item in inventory:
		var def: Dictionary = GameData.PROPS[item]
		parts.append("%s %s" % [SliceLogic.prop_tier_frame(def["rarity"]), def["name"]])
	return "局外仓库：" + "，".join(parts)


func _apply_inventory() -> void:
	inventory = SaveSystem.load_inventory()
	difficulty = SaveSystem.load_difficulty()
	var base: Dictionary = GameData.VEHICLES[current_vehicle_id]
	# Extractable effects apply at 70% next run, capped at 50% total.
	var grip_bonus := 0.0
	if inventory.has("grip_tyre"):
		grip_bonus = float(GameData.PROPS["grip_tyre"]["effect_value"]) * float(GameData.EXTRACTION["next_run_effect_rate"])
	rider.spill_resist = SliceLogic.clamp_spill_resist(float(base["spill_resist"]) + grip_bonus)
	rider.grip_part = inventory.has("grip_tyre")
	# tool_slot: second charge + cooldown -0.7s (70% of 1.0s).
	rider.tool_charges_max = 2 if inventory.has("tool_slot") else 1
	rider.tool_charges = rider.tool_charges_max
	rider.tool_cooldown = tuning_tool_cooldown - (float(GameData.PROPS["tool_slot"]["effect_value"]) if inventory.has("tool_slot") else 0.0)
	if inventory.has("starter_pack"):
		inventory.erase("starter_pack")
		coins += int(round(float(GameData.PROPS["starter_pack"]["effect_value"]) * float(GameData.EXTRACTION["next_run_effect_rate"])))
		rider.stamina = 100.0
		SaveSystem.save_state(inventory, difficulty)
	ui.set_inventory(_inventory_text())


func _spawn_pickup_particles(pos: Vector3, count: int, colour: Color) -> void:
	# Pickup feel: rising, shrinking sparks, count grows with rarity.
	for i in range(count):
		var s := MeshInstance3D.new()
		s.mesh = SphereMesh.new()
		s.mesh.radius = 0.12
		s.mesh.height = 0.24
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colour
		s.material_override = mat
		s.position = pos + Vector3(float(i % 5) * 0.3 - 0.6, 0.5, float(i / 5) * 0.3 - 0.6)
		add_child(s)
		_particles.append({"node": s, "life": 0.8})


func _collect_prop(p: Dictionary) -> void:
	if bool(p["taken"]):
		return
	var def: Dictionary = GameData.PROPS[p["id"]]
	var tier: Dictionary = GameData.PROP_TIERS[def["rarity"]]
	# Same-name per-run cap: normal 2, epic 1, legendary 1.
	var same_count := 0
	for item in collected_run:
		if item == p["id"]:
			same_count += 1
	if same_count >= int(tier["per_run_cap"]):
		ui.set_message("同名道具已达本局上限（%s %d 个），不能再拾。" % [def["name"], tier["per_run_cap"]])
		return
	p["taken"] = true
	p["pop_t"] = 1.0
	var frame: String = SliceLogic.prop_tier_frame(def["rarity"])
	var root: Node3D = p["root"]
	var pillar_colour: Color = tier["pillar_colour"]
	_spawn_pickup_particles(root.global_position, int(tier["particle_count"]), pillar_colour)
	collected_run.append(p["id"])
	if String(def["rarity"]) == "legendary":
		# Slow-mo pickup: 0.8s real time at 0.3x speed, restored in _process.
		Engine.time_scale = 0.3
		_slowmo_until = Time.get_ticks_msec() + 800
	if bool(def["extractable"]):
		extracted_pending.append(p["id"])
		ui.show_float_text("拾取 %s %s\n可带出！" % [frame, def["name"]], pillar_colour)
		ui.set_message("拾取 %s %s：%s（本局不生效，结算时带出到局外仓库，需先去提取点登记）" % [frame, def["name"], def["desc"]])
		return
	# Run-only: apply immediately. Epic/legendary give a new behaviour,
	# not just a number (see GameData.PROPS comments).
	match String(def["effect_id"]):
		"stamina":
			rider.stamina = minf(100.0, rider.stamina + float(def["effect_value"]))
		"nitrogen":
			rider.nitrogen = float(def["effect_value"])
			rider.nitro_boost_left = 3.0
		"capacity":
			capacity_bonus += int(def["effect_value"])
			spill_shield_left = 30.0
			for o in orders.values():
				if o["state"] == "carried":
					o["integrity"] = 100.0
		_:
			pass
	ui.show_float_text("拾取 %s %s！" % [frame, def["name"]], pillar_colour)
	ui.set_message("拾取 %s %s：%s" % [frame, def["name"], def["desc"]])


func _on_end_shift() -> void:
	if delivered_count == 0:
		ui.set_message("先送至少一单再结算。")
		return
	phase = "settled"
	settlement_step = 1
	# Extraction: only props registered at the extraction point are
	# carried out; unregistered extractables are lost. At most 1 epic
	# + 1 legendary per run; extras are converted to coins.
	# Cost: 5% of run reward per epic, 10% per legendary.
	var kept: Array = []
	var converted: Array = []
	var lost: Array = []
	var epic_kept := 0
	var legendary_kept := 0
	for item in collected_run:
		var def: Dictionary = GameData.PROPS[item]
		var label := "%s %s（来源：战场拾取）" % [SliceLogic.prop_tier_frame(def["rarity"]), def["name"]]
		if bool(def["extractable"]) and extraction_registered:
			if def["rarity"] == "epic" and epic_kept >= int(GameData.EXTRACTION["max_epic_per_run"]):
				converted.append(label)
				coins += 10
				continue
			if def["rarity"] == "legendary" and legendary_kept >= int(GameData.EXTRACTION["max_legendary_per_run"]):
				converted.append(label)
				coins += 10
				continue
			if def["rarity"] == "epic":
				epic_kept += 1
			if def["rarity"] == "legendary":
				legendary_kept += 1
			if item == "starter_pack" or not inventory.has(item):
				inventory.append(item)
			kept.append(label)
		else:
			lost.append(label)
	var cost_rate := float(epic_kept) * float(GameData.EXTRACTION["epic_cost_rate"]) + float(legendary_kept) * float(GameData.EXTRACTION["legendary_cost_rate"])
	var extraction_cost := int(round(float(coins) * cost_rate))
	coins -= extraction_cost
	# Successful extraction raises next-run difficulty slightly
	# (anti-snowball); run upgrades are never extracted or saved.
	if not kept.is_empty():
		difficulty = mini(5, difficulty + 1)
	SaveSystem.save_state(inventory, difficulty)
	ui.set_inventory(_inventory_text())
	var step1 := "结算结论（不可跳过，先看结论再看明细）\n已送 %d 单\n收入 %d 金币（提取费 %d）\n声誉 %d\n洒餐 %d 次，超时 %d 单\n" % [delivered_count, coins, extraction_cost, reputation, spill_count, late_count]
	settlement_text_step2 = "明细\n带出：" + ("，".join(kept) if not kept.is_empty() else "无") + "\n转换（超上限→金币）：" + ("，".join(converted) if not converted.is_empty() else "无") + "\n丢失：" + ("，".join(lost) if not lost.is_empty() else "无") + "\n" + ("未去提取点登记，带出道具全部丢失。" if not extraction_registered and not extracted_pending.is_empty() else "")
	settlement_text_step3 = "仓库同步\n" + _inventory_text() + "\n传说道具单独一行、默认锁定，丢弃需二次确认。\n下一局难度 +" + str(difficulty) + " 级（时限最多 -10%）。"
	ui.show_settlement(step1)
	ui.set_settlement_step(1, settlement_text_step2, settlement_text_step3)


func _advance_settlement() -> void:
	if phase != "settled":
		return
	if settlement_step == 1:
		settlement_step = 2
		ui.set_settlement_step(2, settlement_text_step2, settlement_text_step3)
	elif settlement_step == 2:
		settlement_step = 3
		settlement_sync_left = 2.0
		ui.set_settlement_step(3, settlement_text_step2, settlement_text_step3)


func _on_abandon() -> void:
	# Failed run: inventory slots are halved (kept items only), no
	# extraction, no difficulty rise. This is the failure penalty.
	if phase != "playing":
		return
	phase = "settled"
	settlement_step = 3
	var keep_count := inventory.size() / 2
	var kept_inv: Array = []
	for i in range(keep_count):
		kept_inv.append(inventory[i])
	inventory = kept_inv
	SaveSystem.save_state(inventory, difficulty)
	ui.set_inventory(_inventory_text())
	settlement_text_step2 = "失败：本局放弃，仓库减半。"
	settlement_text_step3 = "仓库同步\n" + _inventory_text()
	ui.show_settlement("失败结算：本局放弃，仓库减半，道具不带出。")
	ui.set_settlement_step(3, settlement_text_step2, settlement_text_step3)


func _on_tuning_applied(spill_damage: float, tool_cooldown: float, nitrogen_drain: float) -> void:
	tuning_spill_damage = spill_damage
	tuning_tool_cooldown = tool_cooldown
	rider.tool_cooldown = tool_cooldown - (float(GameData.PROPS["tool_slot"]["effect_value"]) if inventory.has("tool_slot") else 0.0)
	rider.nitrogen_drain = nitrogen_drain
	ui.set_message("调参已应用：洒餐伤害 %.0f，驱赶冷却 %.1f 秒，氮气消耗 %.0f（本局生效）。" % [spill_damage, tool_cooldown, nitrogen_drain])


func _on_settlement_skip() -> void:
	# Skip only activates after 2s (ui enforces); jump to the final step.
	if phase != "settled":
		return
	settlement_step = 3
	settlement_sync_left = 0.0
	ui.set_settlement_step(3, settlement_text_step2, settlement_text_step3)
	ui.set_settlement_sync(0.0)


func _on_discard_legendary() -> void:
	# Second-confirmed discard of locked legendary inventory items.
	var kept_inv: Array = []
	for item in inventory:
		if GameData.PROPS[item]["rarity"] != "legendary":
			kept_inv.append(item)
	inventory = kept_inv
	SaveSystem.save_state(inventory, difficulty)
	ui.set_inventory(_inventory_text())
	ui.set_message("已丢弃传说道具（二次确认后），仓库已更新。")


func _on_restart() -> void:
	Engine.time_scale = 1.0
	ui.hide_settlement()
	rider.position = Vector3(0, 0, 10)
	rider.shake = 0.0
	rider.nitrogen = 100.0
	rider.stamina = 100.0
	_reset_orders()
	ui.set_message("新一班开始了，先接单。")


func _process(delta: float) -> void:
	if camera == null or rider == null:
		return
	elapsed += delta
	urge_cooldown_left = maxf(0.0, urge_cooldown_left - delta)
	spill_shield_left = maxf(0.0, spill_shield_left - delta)
	if settlement_step == 3 and settlement_sync_left > 0.0:
		settlement_sync_left -= delta
		ui.set_settlement_sync(settlement_sync_left)
	# Legendary slow-mo pickup: restore normal speed after 0.8s real time.
	if Engine.time_scale != 1.0 and _slowmo_until > 0 and Time.get_ticks_msec() > _slowmo_until:
		Engine.time_scale = 1.0
		_slowmo_until = 0
	# Camera: third-person panoramic, behind + above the rider.
	# Aim mode (Tab held) zooms slightly out and shows the aim fan (rider script).
	var dist := 16.0 if rider.aiming else 11.0
	var height := 17.0 if rider.aiming else 13.0
	var forward: Vector3 = rider.transform.basis.z
	var cam_target := rider.global_position - forward * dist + Vector3(0, height, 0)
	camera.global_position = camera.global_position.lerp(cam_target, 1.0 - pow(0.001, delta))
	camera.look_at(rider.global_position + forward * 4.0 + Vector3(0, 1.0, 0), Vector3.UP)

	if phase == "playing":
		# Timers, prep, merchant waiting.
		for o in orders.values():
			if o["state"] == "accepted" or o["state"] == "carried":
				o["time_left"] = float(o["time_left"]) - delta
			if o["state"] == "accepted":
				if o["prep_left"] > 0.0:
					o["prep_left"] = maxf(0.0, float(o["prep_left"]) - delta)
				if _order_near_merchant(o) and o["prep_left"] > 0.0:
					o["merchant_wait"] = float(o["merchant_wait"]) + delta
		# Spill: forgiveness — shake hits 100, lose integrity, reset to 60.
		# Golden-box spill shield: spills do no damage while active.
		if rider.shake >= GameData.BALANCE["spill_threshold"]:
			rider.shake = GameData.BALANCE["spill_reset"]
			if spill_shield_left > 0.0:
				ui.set_message("防洒护盾挡住了这次洒餐！完好度不受损。")
			else:
				for o in orders.values():
					if o["state"] == "carried":
						o["integrity"] = SliceLogic.spill_integrity(float(o["integrity"]), tuning_spill_damage)
				spill_count += 1
				ui.set_message("洒了！完好度 -%.0f%%，稳住骑行让晃动回落。" % tuning_spill_damage)
		# Battlefield props: channelled pickup — normal instant, epic
		# 0.5s, legendary 1.0s standing near the prop. Leaving resets.
		for p in city.props:
			if bool(p["taken"]):
				continue
			var pid: String = p["id"]
			var tier_p: Dictionary = GameData.PROP_TIERS[GameData.PROPS[pid]["rarity"]]
			if _near((p["root"] as Node3D).global_position, 3.0):
				_pickup_progress[pid] = float(_pickup_progress.get(pid, 0.0)) + delta
				if float(_pickup_progress[pid]) >= float(tier_p["pickup_secs"]):
					_collect_prop(p)
			else:
				_pickup_progress[pid] = 0.0

		# Roadside reward, on-route, one per run, no detour.
		# Expanded loading zone with pet fetch: pet active = 6m radius.
		var reward_radius := 6.0 if rider.pet_active else 3.5
		if city.reward_node and not city.reward_taken and _near(city.reward_node.global_position, reward_radius):
			city.reward_taken = true
			city.reward_node.visible = false
			coins += GameData.BALANCE["roadside_reward_coins"]
			rider.stamina = minf(100.0, rider.stamina + 20.0)
			if rider.pet_active:
				ui.set_message("宠物帮你捡了顺路奖励！+15 金币，体力 +20（无需绕路）。")
			else:
				ui.set_message("顺路奖励！+15 金币，体力 +20（无需绕路）。")
		# Exploration reward: clearly off-route, with a detour time cost.
		if city.exploration_node and not city.exploration_taken and _near(city.exploration_node.global_position, 3.5):
			city.exploration_taken = true
			city.exploration_node.visible = false
			coins += 30
			for o in orders.values():
				if o["state"] == "accepted" or o["state"] == "carried":
					o["time_left"] = float(o["time_left"]) - float(GameData.EXTRACTION["exploration_detour_time_cost"])
			ui.set_message("探索奖励！+30 金币，但绕路扣了 20 秒总时间。")
		# Extraction point hint (early stage, separate from station).
		if city.extraction_node and not extraction_registered and _near(city.extraction_node.global_position, 8.0):
			ui.set_message("提取点到了：按提取按钮登记带出（登记花 10 秒），不登记结算时带出道具会丢失。")

	# Prop life: epic pillars rotate, legendary pillars cycle rainbow
	# colours (top-layer beam, visible at distance, never buried).
	# Pillars fade to near-transparent within 10m so they never block
	# obstacles or the road ahead; they have no collision shape.
	for p in city.props:
		if bool(p["taken"]):
			continue
		var rarity_p: String = GameData.PROPS[p["id"]]["rarity"]
		var pillar_p: MeshInstance3D = p["pillar"]
		var pdist := rider.global_position.distance_to((p["root"] as Node3D).global_position)
		var pmat := pillar_p.material_override as StandardMaterial3D
		if pmat:
			var alpha := 0.25 if pdist >= 10.0 else 0.05 + (pdist / 10.0) * 0.2
			var base_col := pmat.albedo_color
			pmat.albedo_color = Color(base_col.r, base_col.g, base_col.b, alpha)
		if rarity_p == "epic":
			pillar_p.rotation.y += delta * 1.5
		elif rarity_p == "legendary":
			var hue := fmod(elapsed * 0.2, 1.0)
			var lmat := pillar_p.material_override as StandardMaterial3D
			if lmat:
				var a := lmat.albedo_color.a
				lmat.albedo_color = Color.from_hsv(hue, 0.8, 1.0, a)
	# Pickup pop: scale up to the tier pop scale, then shrink back and
	# hide. Particles rise and shrink, then free themselves.
	for p in city.props:
		if float(p["pop_t"]) > 0.0:
			p["pop_t"] = float(p["pop_t"]) - delta * 2.0
			var tier_pop: Dictionary = GameData.PROP_TIERS[GameData.PROPS[p["id"]]["rarity"]]
			var s := 1.0 + (float(tier_pop["pop_scale"]) - 1.0) * maxf(0.0, float(p["pop_t"]))
			(p["root"] as Node3D).scale = Vector3(s, s, s)
			if float(p["pop_t"]) <= 0.0 and bool(p["taken"]):
				(p["root"] as Node3D).visible = false
	for i in range(_particles.size() - 1, -1, -1):
		var part: Dictionary = _particles[i]
		var node: MeshInstance3D = part["node"]
		node.position.y += delta * 3.0
		node.scale *= 0.98
		part["life"] = float(part["life"]) - delta
		if float(part["life"]) <= 0.0:
			node.queue_free()
			_particles.remove_at(i)

	# Blockers wander; driven-away ones stay away for 20 s, then return.
	for b in city.blockers:
		var node: MeshInstance3D = b["node"]
		if elapsed < float(b["away_until"]):
			continue
		var home: Vector3 = b["home"]
		var phase_w: float = b["phase"]
		node.position = Vector3(
			home.x + sin(elapsed * 0.5 + phase_w) * 3.0,
			1.0,
			home.z + cos(elapsed * 0.35 + phase_w) * 2.0)

	_update_hud()


func _next_target() -> Dictionary:
	# Carried orders first, then accepted orders waiting for pickup.
	for o in orders.values():
		if o["state"] == "carried":
			return {"pos": city.customer_pos(o["customer"]), "has": true}
	for o in orders.values():
		if o["state"] == "accepted":
			return {"pos": city.merchant_pos(o["merchant"]), "has": true}
	return {"pos": Vector3(0, 0, 10), "has": false}


func _update_hud() -> void:
	# Cognitive overload rule: normally show only the NEXT order + its
	# margin; full route comparison only when stopped or slow (<1 m/s).
	var active_keys: Array = []
	for key in ["light_meal", "hot_soup", "family_bag"]:
		var st: String = orders[key]["state"]
		if st == "accepted" or st == "carried":
			active_keys.append(key)
	var order_text := "订单（容量 %d/%d）\n" % [carried_count(), capacity()]
	if active_keys.is_empty():
		order_text += "未接单：点接单按钮，或按 1/2/3。\n"
	elif rider.current_speed < 1.0:
		order_text += "全单对比（已停车/慢速）：\n"
		for key in active_keys:
			var o: Dictionary = orders[key]
			order_text += "%s：%s，剩余 %.0f 秒，余量 %.0f 秒\n" % [o["name"], "取餐中" if o["state"] == "accepted" else "送达中", o["time_left"], o["time_left"]]
	else:
		var o0: Dictionary = orders[active_keys[0]]
		order_text += "下一单：%s，剩余 %.0f 秒\n还有 %d 单在途（停下看全单）\n" % [o0["name"], o0["time_left"], active_keys.size() - 1]
	var nearest := 9999.0
	var pulse := false
	for o in orders.values():
		if o["state"] == "accepted" or o["state"] == "carried":
			nearest = minf(nearest, float(o["time_left"]))
	# Vibration/pulse rule: short critical pulse only in the last 15s,
	# reduced (off) after severe lateness (< -30s) so it stops nagging.
	if nearest >= 0.0 and nearest < 15.0:
		pulse = true
	var countdown_text := "倒计时 --"
	if nearest < 9998.0:
		countdown_text = "最近截止：%.0f 秒" % nearest
	var vehicle_name: String = GameData.VEHICLES[current_vehicle_id]["name"]
	var status_text := "车辆：%s（%s，技能 %d/6，驱赶 1/2）\n金币 %d | 声誉 %d | 已送 %d\n宠物：挂载座位，疲劳 %.0f%%（100%% 休息）\n%s" % [vehicle_name, GameData.VEHICLES[current_vehicle_id]["role"], equipped_skills.size(), coins, reputation, delivered_count, rider.pet_fatigue, _inventory_text()]
	ui.set_hud(countdown_text, order_text, status_text, rider.shake, rider.nitrogen, rider.stamina, pulse)
	# Active effects bar: at most 4 permanent, others fold into +N.
	var effects: Array = []
	if rider.nitro_boost_left > 0.0:
		effects.append({"name": "氮气爆发", "secs": rider.nitro_boost_left})
	if spill_shield_left > 0.0:
		effects.append({"name": "防洒护盾", "secs": spill_shield_left})
	if inventory.has("grip_tyre"):
		effects.append({"name": "防滑轮胎", "secs": -1.0})
	if inventory.has("tool_slot"):
		effects.append({"name": "工具槽", "secs": -1.0})
	ui.set_effects(effects)
	ui.set_slip_edge(rider.shake > 80.0)
	# Merchant urge zone: urge button only replaces the throw button
	# inside a slow pickup zone (< 10 km/h ≈ 2.8 m/s) near a merchant
	# with food still preparing, with a three-stage mood meter.
	var urge_near := false
	var urge_mood := 0
	for o in orders.values():
		if o["state"] == "accepted" and _order_near_merchant(o) and o["prep_left"] > 0.0:
			urge_near = true
			urge_mood = int(o["urge_count"])
	var urge_slow: bool = rider.current_speed < 2.8
	var urge_ok: bool = urge_near and urge_slow and urge_cooldown_left <= 0.0 and rider.stamina >= float(GameData.BALANCE["urge_stamina_cost"])
	var mood_text := "心情好" if urge_mood == 0 else ("有点不耐烦" if urge_mood == 1 else "快发火了")
	var mood_col := Color(0.3, 1.0, 0.3) if urge_mood == 0 else (Color(1, 1, 0) if urge_mood == 1 else Color(1, 0.3, 0.3))
	ui.set_urge_state(urge_ok, mood_text, mood_col)
	# In the urge zone the throw button is replaced (disabled); outside
	# it, the throw button follows its own cooldown / charges / costs.
	ui.set_tool_state(urge_ok or rider.tool_charges <= 0 or rider.tool_cooldown_left > 0.0)
	# Large-vehicle no-entry warning (holographic wall indicator in HUD;
	# a 3D wall needs alley geometry that this slice does not define).
	if (current_vehicle_id == "car" or current_vehicle_id == "van") and not active_keys.is_empty():
		var o_next: Dictionary = orders[active_keys[0]]
		var target_pos: Vector3 = city.merchant_pos(o_next["merchant"]) if o_next["state"] == "accepted" else city.customer_pos(o_next["customer"])
		if bool(GameData.ORDER_TYPES[o_next["type"]].get("needs_alleys", false)) and rider.global_position.distance_to(target_pos) < 40.0:
			ui.set_message("前方 40 米内窄巷：大车禁入（全息禁入墙），请换小车走最后100米。")

	var merchants_arr: Array = []
	var customers_arr: Array = []
	for k in ["A", "B", "C"]:
		merchants_arr.append(city.merchant_pos(k))
		customers_arr.append(city.customer_pos(k))
	var blockers_arr: Array = []
	for b in city.blockers:
		blockers_arr.append((b["node"] as MeshInstance3D).global_position)
	var target := _next_target()
	var minimap_data := {
		"player": rider.global_position,
		"heading": rider.heading,
		"speed": rider.current_speed,
		"merchants": merchants_arr,
		"customers": customers_arr,
		"station": Vector3(0, 0, 10),
		"reward": city.reward_node.global_position if city.reward_node else Vector3.ZERO,
		"reward_visible": city.reward_node and not city.reward_taken,
		"exploration": city.exploration_node.global_position if city.exploration_node else Vector3.ZERO,
		"exploration_visible": city.exploration_node and not city.exploration_taken,
		"blockers": blockers_arr,
		"target": target["pos"],
		"has_target": target["has"],
	}
	(ui.minimap as Control).call("set_data", minimap_data)
