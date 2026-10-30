extends CanvasLayer
## UI scene, separate from gameplay scenes.
## Layering (Gemini internal rules): countdown on top (z 10), urge is a
## non-intrusive bottom tip, slip is an edge effect only, never covering
## the route. Central golden triangle (road ahead) stays clear: no
## permanent panel sits over the centre; upgrade / settlement panels
## only appear when the run is not being driven.
## Skill buttons = angular style, prop float labels = rounded square
## style, completely different cooldown masks (skill buttons show
## seconds + colour, props show no cooldown). Popup titles differ by
## at least 4px: upgrade title 24px, settlement title 20px.

signal accept_pressed(order_key: String)
signal action_pressed
signal urge_pressed
signal report_pressed
signal tool_pressed
signal end_shift_pressed
signal upgrade_chosen(upgrade_id: String)
signal restart_pressed
signal vehicle_selected(vehicle_id: String)
signal settlement_next_pressed
signal settlement_skip_pressed
signal abandon_pressed
signal extract_pressed
signal discard_legendary_pressed
signal tuning_applied(spill_damage: float, tool_cooldown: float, nitrogen_drain: float)

var countdown_label: Label
var message_label: Label
var order_label: Label
var status_label: Label
var action_button: Button
var urge_button: Button
var report_button: Button
var tool_button: Button
var shake_bar: ProgressBar
var nitrogen_bar: ProgressBar
var stamina_bar: ProgressBar
var minimap: Control
var upgrade_panel: Panel
var settlement_panel: Panel
var settlement_label: Label
var settlement_title_label: Label
var settlement_next_button: Button
var settlement_skip_button: Button
var settlement_restart_button: Button
var settlement_legendary_label: Label
var settlement_sync_label: Label
var discard_button: Button
var inventory_label: Label
var float_label: Label
var effects_panel: Panel
var effects_labels: Array = []
var slip_edge: Panel
var tuning_panel: Panel
var tuning_dirty_label: Label
var tuning_sliders: Dictionary = {}
var tuning_values: Dictionary = {}
var tuning_presets: Dictionary = {
	1: {"spill_damage": 20.0, "tool_cooldown": 3.0, "nitrogen_drain": 30.0},
}
var tuning_level := 1
var tuning_snapshot: Dictionary = {}
var tuning_confirm_pending := false
var _float_timer := 0.0
var _settlement_timer := 0.0
var _discard_confirm_pending := false


func _ready() -> void:
	countdown_label = _label(Vector2(440, 10), Vector2(400, 40), "倒计时 --")
	countdown_label.z_index = 10
	message_label = _label(Vector2(10, 660), Vector2(900, 50), "WASD 移动 | Shift 氮气 | Tab 瞄准 | 空格/Q 驱赶 | E 取餐/送达 | F 催商家 | R 举报")
	order_label = _label(Vector2(10, 50), Vector2(420, 200), "订单：")
	status_label = _label(Vector2(10, 250), Vector2(420, 120), "")
	inventory_label = _label(Vector2(10, 340), Vector2(420, 36), "局外仓库：空")
	float_label = _label(Vector2(440, 60), Vector2(400, 60), "")
	float_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Rounded-square float style (prop style, distinct from skill buttons).
	var float_style := StyleBoxFlat.new()
	float_style.bg_color = Color(0.1, 0.1, 0.1, 0.6)
	float_style.corner_radius_top_left = 12
	float_style.corner_radius_top_right = 12
	float_style.corner_radius_bottom_left = 12
	float_style.corner_radius_bottom_right = 12
	float_label.add_theme_stylebox_override("normal", float_style)
	shake_bar = _bar(Vector2(10, 380), Vector2(300, 22), "晃动")
	nitrogen_bar = _bar(Vector2(10, 410), Vector2(300, 22), "氮气")
	stamina_bar = _bar(Vector2(10, 440), Vector2(300, 22), "体力")

	minimap = preload("res://scripts/minimap.gd").new()
	minimap.position = Vector2(1090, 10)
	minimap.size = Vector2(180, 180)
	minimap.clip_contents = true
	add_child(minimap)

	# Effects bar: side narrow bar, icons at least 22px (here 28px).
	effects_panel = Panel.new()
	effects_panel.position = Vector2(1090, 200)
	effects_panel.size = Vector2(180, 140)
	add_child(effects_panel)

	# Slip edge effect: border only, never covering the route.
	slip_edge = Panel.new()
	slip_edge.position = Vector2.ZERO
	slip_edge.size = Vector2(1280, 720)
	slip_edge.visible = false
	var edge_style := StyleBoxFlat.new()
	edge_style.bg_color = Color(0, 0, 0, 0)
	edge_style.border_color = Color(1, 0.2, 0.2, 0.8)
	edge_style.border_width_left = 6
	edge_style.border_width_right = 6
	edge_style.border_width_top = 6
	edge_style.border_width_bottom = 6
	slip_edge.add_theme_stylebox_override("panel", edge_style)
	add_child(slip_edge)

	for i in range(3):
		var key: String = ["light_meal", "hot_soup", "family_bag"][i]
		var b := Button.new()
		b.position = Vector2(10, 480 + i * 40)
		b.size = Vector2(220, 32)
		b.text = "接单 %d" % (i + 1)
		b.pressed.connect(_emit_accept.bind(key))
		add_child(b)

	action_button = _button(Vector2(240, 480), Vector2(160, 32), "取餐 / 送达 (E)", func() -> void: action_pressed.emit())
	urge_button = _button(Vector2(240, 520), Vector2(160, 32), "催商家 (F)", func() -> void: urge_pressed.emit())
	report_button = _button(Vector2(240, 560), Vector2(160, 32), "举报一次 (R)", func() -> void: report_pressed.emit())
	tool_button = _button(Vector2(240, 600), Vector2(160, 32), "驱赶 (空格)", func() -> void: tool_pressed.emit())
	_button(Vector2(410, 480), Vector2(160, 32), "结束本班", func() -> void: end_shift_pressed.emit())
	_button(Vector2(410, 520), Vector2(160, 32), "放弃本班", func() -> void: abandon_pressed.emit())
	_button(Vector2(410, 560), Vector2(160, 32), "提取登记", func() -> void: extract_pressed.emit())
	_button(Vector2(580, 480), Vector2(160, 32), "调参面板", func() -> void: tuning_panel.visible = not tuning_panel.visible)

	# Vehicle selector: per-order selection (see main vehicle gate).
	var vehicle_label := _label(Vector2(580, 520), Vector2(160, 32), "选车：")
	var vehicle_opt := OptionButton.new()
	vehicle_opt.position = Vector2(580, 550)
	vehicle_opt.size = Vector2(160, 32)
	var vehicle_ids := ["e_bike", "motorcycle", "car", "van"]
	for vid in vehicle_ids:
		vehicle_opt.add_item(String(GameData.VEHICLES[vid]["name"]))
	vehicle_opt.item_selected.connect(func(idx: int) -> void: vehicle_selected.emit(vehicle_ids[idx]))
	add_child(vehicle_opt)

	upgrade_panel = Panel.new()
	upgrade_panel.position = Vector2(390, 200)
	upgrade_panel.size = Vector2(500, 220)
	upgrade_panel.visible = false
	add_child(upgrade_panel)
	var up_label := Label.new()
	up_label.position = Vector2(20, 20)
	up_label.size = Vector2(460, 40)
	up_label.text = "升级！选一个（每级三选一）"
	up_label.add_theme_font_size_override("font_size", 24)
	upgrade_panel.add_child(up_label)
	for i in range(3):
		var up: Dictionary = GameData.UPGRADES[i]
		var ub := Button.new()
		ub.position = Vector2(20, 70 + i * 40)
		ub.size = Vector2(460, 32)
		ub.text = "%s：%s" % [up["name"], up["desc"]]
		ub.pressed.connect(_emit_upgrade.bind(up["id"]))
		upgrade_panel.add_child(ub)

	settlement_panel = Panel.new()
	settlement_panel.position = Vector2(390, 150)
	settlement_panel.size = Vector2(500, 360)
	settlement_panel.visible = false
	add_child(settlement_panel)
	settlement_title_label = Label.new()
	settlement_title_label.position = Vector2(20, 10)
	settlement_title_label.size = Vector2(460, 30)
	settlement_title_label.text = "结算"
	settlement_title_label.add_theme_font_size_override("font_size", 20)
	settlement_panel.add_child(settlement_title_label)
	settlement_label = Label.new()
	settlement_label.position = Vector2(20, 45)
	settlement_label.size = Vector2(460, 180)
	settlement_label.text = "结算"
	settlement_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settlement_panel.add_child(settlement_label)
	# Legendary row: 80% width, locked by default.
	settlement_legendary_label = Label.new()
	settlement_legendary_label.position = Vector2(20, 230)
	settlement_legendary_label.size = Vector2(400, 30)
	settlement_legendary_label.text = "🔒 已锁定：传说道具"
	settlement_panel.add_child(settlement_legendary_label)
	settlement_sync_label = Label.new()
	settlement_sync_label.position = Vector2(20, 260)
	settlement_sync_label.size = Vector2(460, 30)
	settlement_sync_label.text = ""
	settlement_panel.add_child(settlement_sync_label)
	settlement_next_button = Button.new()
	settlement_next_button.position = Vector2(20, 295)
	settlement_next_button.size = Vector2(220, 32)
	settlement_next_button.text = "下一步"
	settlement_next_button.pressed.connect(func() -> void: settlement_next_pressed.emit())
	settlement_panel.add_child(settlement_next_button)
	settlement_skip_button = Button.new()
	settlement_skip_button.position = Vector2(250, 295)
	settlement_skip_button.size = Vector2(220, 32)
	settlement_skip_button.text = "跳过（2秒后可用）"
	settlement_skip_button.disabled = true
	settlement_skip_button.pressed.connect(func() -> void: settlement_skip_pressed.emit())
	settlement_panel.add_child(settlement_skip_button)
	settlement_restart_button = Button.new()
	settlement_restart_button.position = Vector2(20, 330)
	settlement_restart_button.size = Vector2(220, 32)
	settlement_restart_button.text = "再来一班"
	settlement_restart_button.disabled = true
	settlement_restart_button.pressed.connect(func() -> void: restart_pressed.emit())
	settlement_panel.add_child(settlement_restart_button)
	# Dangerous action separated by 80px from the restart button row.
	discard_button = Button.new()
	discard_button.position = Vector2(250, 330)
	discard_button.size = Vector2(220, 32)
	discard_button.text = "丢弃传说道具"
	discard_button.pressed.connect(_on_discard_pressed)
	settlement_panel.add_child(discard_button)

	_build_tuning_panel()


func _build_tuning_panel() -> void:
	tuning_panel = Panel.new()
	tuning_panel.position = Vector2(300, 100)
	tuning_panel.size = Vector2(680, 420)
	tuning_panel.visible = false
	add_child(tuning_panel)
	var title := Label.new()
	title.position = Vector2(20, 10)
	title.size = Vector2(400, 30)
	title.text = "调参面板（内部用，v1）"
	tuning_panel.add_child(title)
	tuning_dirty_label = Label.new()
	tuning_dirty_label.position = Vector2(430, 10)
	tuning_dirty_label.size = Vector2(200, 30)
	tuning_dirty_label.text = "已保存"
	tuning_panel.add_child(tuning_dirty_label)
	# Level presets: L1 unlocked, L2/L3 locked (disabled).
	for lvl in [1, 2, 3]:
		var lb := Button.new()
		lb.position = Vector2(20 + (lvl - 1) * 120, 50)
		lb.size = Vector2(100, 32)
		lb.text = "第 %d 关" % lvl if lvl == 1 else "第 %d 关（锁定）" % lvl
		lb.disabled = lvl != 1
		lb.pressed.connect(_on_tuning_level.bind(lvl))
		tuning_panel.add_child(lb)
	tuning_values = (tuning_presets[1] as Dictionary).duplicate(true)
	var keys := ["spill_damage", "tool_cooldown", "nitrogen_drain"]
	var names := {"spill_damage": "洒餐伤害", "tool_cooldown": "驱赶冷却", "nitrogen_drain": "氮气消耗"}
	for i in range(keys.size()):
		var key: String = keys[i]
		var lab := Label.new()
		lab.position = Vector2(20, 100 + i * 60)
		lab.size = Vector2(200, 30)
		lab.text = "%s（建议 %s）" % [names[key], GameData.TUNING[key]["safe"]]
		tuning_panel.add_child(lab)
		var slider := HSlider.new()
		slider.position = Vector2(230, 100 + i * 60)
		slider.size = Vector2(300, 30)
		slider.min_value = float(GameData.TUNING[key]["hard"][0])
		slider.max_value = float(GameData.TUNING[key]["hard"][1])
		slider.step = 0.5
		slider.value = float(tuning_values[key])
		slider.value_changed.connect(_on_tuning_changed.bind(key))
		tuning_panel.add_child(slider)
		tuning_sliders[key] = slider
		var num := Label.new()
		num.position = Vector2(540, 100 + i * 60)
		num.size = Vector2(80, 30)
		num.text = str(slider.value)
		tuning_panel.add_child(num)
		tuning_sliders[key + "_label"] = num
	var snap := Button.new()
	snap.position = Vector2(20, 300)
	snap.size = Vector2(150, 32)
	snap.text = "快照"
	snap.pressed.connect(func() -> void: tuning_snapshot = tuning_values.duplicate(true))
	tuning_panel.add_child(snap)
	var roll := Button.new()
	roll.position = Vector2(190, 300)
	roll.size = Vector2(150, 32)
	roll.text = "回滚快照"
	roll.pressed.connect(_on_tuning_rollback)
	tuning_panel.add_child(roll)
	var apply_b := Button.new()
	apply_b.position = Vector2(360, 300)
	apply_b.size = Vector2(150, 32)
	apply_b.text = "应用"
	apply_b.pressed.connect(_on_tuning_apply)
	tuning_panel.add_child(apply_b)
	var close_b := Button.new()
	close_b.position = Vector2(530, 300)
	close_b.size = Vector2(120, 32)
	close_b.text = "关闭"
	close_b.pressed.connect(func() -> void: tuning_panel.visible = false)
	tuning_panel.add_child(close_b)


func _on_tuning_level(lvl: int) -> void:
	# Per-level presets are independent; switching levels keeps the
	# dirty state of the previous level in its own preset dict.
	tuning_presets[tuning_level] = tuning_values.duplicate(true)
	tuning_level = lvl
	if tuning_presets.has(lvl):
		tuning_values = (tuning_presets[lvl] as Dictionary).duplicate(true)
		for key in ["spill_damage", "tool_cooldown", "nitrogen_drain"]:
			(tuning_sliders[key] as HSlider).value = float(tuning_values[key])
	tuning_dirty_label.text = "已保存"


func _on_tuning_changed(value: float, key: String) -> void:
	tuning_values[key] = value
	(tuning_sliders[key + "_label"] as Label).text = str(value)
	var state := SliceLogic.tuning_validate(value, key)
	var lab := tuning_sliders[key + "_label"] as Label
	if state == "yellow":
		lab.modulate = Color(1, 1, 0)
	elif state == "orange":
		lab.modulate = Color(1, 0.6, 0)
	elif state == "red":
		lab.modulate = Color(1, 0, 0)
	else:
		lab.modulate = Color(1, 1, 1)
	tuning_dirty_label.text = "未保存（跨关保留）"


func _on_tuning_rollback() -> void:
	if tuning_snapshot.is_empty():
		return
	tuning_values = tuning_snapshot.duplicate(true)
	for key in ["spill_damage", "tool_cooldown", "nitrogen_drain"]:
		(tuning_sliders[key] as HSlider).value = float(tuning_values[key])
	tuning_dirty_label.text = "已回滚"


func _on_tuning_apply() -> void:
	# Orange confirm step: first press asks, second press applies.
	if not tuning_confirm_pending:
		tuning_confirm_pending = true
		tuning_dirty_label.text = "确认应用？再点一次应用"
		return
	tuning_confirm_pending = false
	tuning_presets[tuning_level] = tuning_values.duplicate(true)
	tuning_dirty_label.text = "已保存"
	tuning_applied.emit(float(tuning_values["spill_damage"]), float(tuning_values["tool_cooldown"]), float(tuning_values["nitrogen_drain"]))


func _on_discard_pressed() -> void:
	# Dangerous action: second confirmation required.
	if not _discard_confirm_pending:
		_discard_confirm_pending = true
		discard_button.text = "再次确认丢弃？"
		return
	_discard_confirm_pending = false
	discard_button.text = "丢弃传说道具"
	discard_legendary_pressed.emit()


func _emit_accept(key: String) -> void:
	accept_pressed.emit(key)


func _emit_upgrade(upgrade_id: String) -> void:
	upgrade_chosen.emit(upgrade_id)


func _label(pos: Vector2, size: Vector2, text: String) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = size
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(l)
	return l


func _bar(pos: Vector2, size: Vector2, _name: String) -> ProgressBar:
	var b := ProgressBar.new()
	b.position = pos
	b.size = size
	b.min_value = 0
	b.max_value = 100
	b.value = 0
	add_child(b)
	return b


func _button(pos: Vector2, size: Vector2, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.position = pos
	b.size = size
	b.text = text
	# Angular skill-button style (distinct from rounded prop floats).
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 0.9)
	style.border_color = Color(1.0, 0.85, 0.1, 0.9)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	b.add_theme_stylebox_override("normal", style)
	b.pressed.connect(cb)
	add_child(b)
	return b


func set_hud(countdown_text: String, order_text: String, status_text: String,
		shake: float, nitrogen: float, stamina: float, pulse: bool) -> void:
	countdown_label.text = countdown_text
	order_label.text = order_text
	status_label.text = status_text
	shake_bar.value = shake
	nitrogen_bar.value = nitrogen
	stamina_bar.value = stamina
	countdown_label.modulate = Color(1, 0.3, 0.3) if pulse else Color(1, 1, 1)


func set_message(text: String) -> void:
	message_label.text = text


func set_inventory(text: String) -> void:
	inventory_label.text = text


func show_float_text(text: String, colour: Color) -> void:
	float_label.text = text
	float_label.modulate = colour
	float_label.scale = Vector2(1.6, 1.6)
	_float_timer = 1.2


func set_effects(effects: Array) -> void:
	# At most 4 shown permanently; the rest fold into a +N label.
	for lab in effects_labels:
		(lab as Label).queue_free()
	effects_labels = []
	var shown := mini(effects.size(), 4)
	for i in range(shown):
		var e: Dictionary = effects[i]
		var lab := Label.new()
		lab.position = Vector2(10, 10 + i * 30)
		lab.size = Vector2(160, 28)
		var secs: float = float(e["secs"])
		var time_text := "常驻" if secs < 0.0 else "%d:%02d" % [int(secs) / 60, int(secs) % 60]
		lab.text = "%s x1 %s" % [e["name"], time_text]
		if secs >= 0.0 and secs <= 10.0:
			lab.modulate = Color(1, 0.3, 0.3)
		elif secs >= 0.0 and secs <= 30.0:
			lab.modulate = Color(1, 1, 0)
		effects_panel.add_child(lab)
		effects_labels.append(lab)
	if effects.size() > 4:
		var more := Label.new()
		more.position = Vector2(10, 10 + 4 * 30)
		more.size = Vector2(160, 28)
		more.text = "+%d 更多" % (effects.size() - 4)
		effects_panel.add_child(more)
		effects_labels.append(more)


func set_slip_edge(visible: bool) -> void:
	slip_edge.visible = visible


func set_urge_state(enabled: bool, mood_text: String, mood_colour: Color) -> void:
	urge_button.disabled = not enabled
	urge_button.text = "催商家 (F) - " + mood_text
	urge_button.modulate = mood_colour


func set_tool_state(disabled: bool) -> void:
	tool_button.disabled = disabled


func show_upgrade() -> void:
	upgrade_panel.visible = true


func hide_upgrade() -> void:
	upgrade_panel.visible = false


func show_settlement(text: String) -> void:
	settlement_label.text = text
	settlement_panel.visible = true
	settlement_next_button.visible = true
	settlement_skip_button.disabled = true
	settlement_skip_button.text = "跳过（2秒后可用）"
	settlement_restart_button.disabled = true
	_settlement_timer = 0.0


func set_settlement_step(step: int, step2_text: String, step3_text: String) -> void:
	if step == 2:
		settlement_label.text = step2_text
	elif step == 3:
		settlement_label.text = step3_text
		settlement_next_button.visible = false
		settlement_sync_label.text = "正在同步仓库…（至少 2 秒）"


func set_settlement_sync(left: float) -> void:
	if left <= 0.0:
		settlement_sync_label.text = "同步完成"
		settlement_restart_button.disabled = false
	else:
		settlement_sync_label.text = "正在同步仓库… %.0f 秒" % left


func hide_settlement() -> void:
	settlement_panel.visible = false


func _process(delta: float) -> void:
	if _float_timer > 0.0:
		_float_timer -= delta
		float_label.scale = float_label.scale.lerp(Vector2.ONE, 1.0 - pow(0.001, delta))
		if _float_timer <= 0.0:
			float_label.text = ""
			float_label.modulate = Color(1, 1, 1)
	if settlement_panel.visible:
		_settlement_timer += delta
		if _settlement_timer >= 2.0 and settlement_skip_button.disabled:
			settlement_skip_button.disabled = false
			settlement_skip_button.text = "跳过"
