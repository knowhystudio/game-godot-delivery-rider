extends RefCounted
class_name SliceLogic
## Pure, testable formulas. Main gameplay code calls these, never duplicates them.

static func urge_remaining(remaining: float, urge_count: int) -> float:
	# First urge is best, later urges diminish, over-urging (3rd+) backfires.
	match urge_count:
		0:
			return remaining * 0.4
		1:
			return remaining * 0.7
		_:
			return remaining + 2.0

static func spill_integrity(integrity: float, damage: float) -> float:
	return maxf(0.0, integrity - damage)

static func settlement_pay(base_pay: int, on_time: bool, zero_spill: bool,
		integrity: float, late: bool, merchant_offset: bool) -> int:
	var pay := float(base_pay)
	if on_time:
		pay += 10
	if zero_spill:
		pay += 10
	if integrity < 100.0:
		pay *= integrity / 100.0
	if late:
		pay *= 0.5
		if merchant_offset:
			# Report offsets half of the late penalty, never more than the loss.
			pay += float(base_pay) * 0.25
	return int(round(pay))

static func prop_tier_frame(rarity: String) -> String:
	if GameData.PROP_TIERS.has(rarity):
		return String(GameData.PROP_TIERS[rarity]["icon_frame"])
	return "普通·灰框"


static func prop_is_extractable(prop_id: String) -> bool:
	if GameData.PROPS.has(prop_id):
		return bool(GameData.PROPS[prop_id]["extractable"])
	return false


static func clamp_spill_resist(value: float) -> float:
	return minf(value, float(GameData.STAT_CAPS["spill_resist_max"]))


static func clamp_speed(base: float, value: float) -> float:
	return minf(value, base * float(GameData.STAT_CAPS["speed_rate_max"]))


static func clamp_range(base: float, value: float) -> float:
	return minf(value, base * float(GameData.STAT_CAPS["range_rate_max"]))


static func props_excluded(a: String, b: String) -> bool:
	if GameData.PROP_EXCLUSIONS.has(a):
		return (GameData.PROP_EXCLUSIONS[a] as Array).has(b)
	return false


static func vehicle_can_take(vehicle_id: String, order_type: String) -> bool:
	# Large trunk/transfer vehicles cannot enter narrow alleys or climb
	# stairs; orders needing the last 100m on a small vehicle, or alleys,
	# must be taken on a small vehicle or on foot, otherwise they soft-lock.
	if not GameData.VEHICLES.has(vehicle_id) or not GameData.ORDER_TYPES.has(order_type):
		return false
	var v: Dictionary = GameData.VEHICLES[vehicle_id]
	var o: Dictionary = GameData.ORDER_TYPES[order_type]
	if bool(o.get("needs_small_last_100m", false)) and String(v["role"]) == "干线/中转":
		return false
	if bool(o.get("needs_alleys", false)) and not bool(v["can_alleys"]):
		return false
	return true


static func validate_skills(equipped: Array) -> bool:
	if equipped.size() > int(GameData.SKILL_CAPS["max_active"]):
		return false
	var drive_count := 0
	for s in equipped:
		if String(s) == "drive_away":
			drive_count += 1
	return drive_count <= int(GameData.SKILL_CAPS["max_drive_away"])


static func tuning_validate(value: float, key: String) -> String:
	# ok | yellow (outside safe, inside hard) | orange (at hard edge, needs
	# confirm) | red (outside hard, refuse).
	var t: Dictionary = GameData.TUNING[key]
	var hard: Array = t["hard"]
	var safe: Array = t["safe"]
	if value < float(hard[0]) or value > float(hard[1]):
		return "red"
	if value == float(hard[0]) or value == float(hard[1]):
		return "orange"
	if value < float(safe[0]) or value > float(safe[1]):
		return "yellow"
	return "ok"


static func prop_pillar_height(rarity: String) -> float:
	if GameData.PROP_TIERS.has(rarity):
		return float(GameData.PROP_TIERS[rarity]["pillar_height"])
	return 3.0


static func review_for(on_time: bool, integrity: float, over_urged: bool) -> String:
	if over_urged:
		return "中评"
	if on_time and integrity >= 100.0:
		return "好评"
	if on_time or integrity >= 80.0:
		return "中评"
	return "差评"
