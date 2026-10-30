extends SceneTree
## Headless logic test. Run: godot --headless --path . --script res://scripts/test_slice.gd
## Prints PASS/FAIL lines and quits. No rendering, no user input needed.

func _init() -> void:
	var failures := 0
	# Data tables exist and have the settled scope.
	if GameData.VEHICLES.size() != 4:
		print("FAIL vehicles != 4")
		failures += 1
	if GameData.ORDER_TYPES.size() != 3:
		print("FAIL order types != 3")
		failures += 1
	if int(GameData.VEHICLES["e_bike"]["capacity"]) != 2:
		print("FAIL e-bike capacity != 2")
		failures += 1
	# Urge: first best, second diminishing, third backfires.
	if not is_equal_approx(SliceLogic.urge_remaining(8.0, 0), 3.2):
		print("FAIL urge 1")
		failures += 1
	if not is_equal_approx(SliceLogic.urge_remaining(8.0, 1), 5.6):
		print("FAIL urge 2")
		failures += 1
	if not is_equal_approx(SliceLogic.urge_remaining(8.0, 2), 10.0):
		print("FAIL urge 3 backfire")
		failures += 1
	# Spill: 100 - 20 = 80, never below 0.
	if not is_equal_approx(SliceLogic.spill_integrity(100.0, 20.0), 80.0):
		print("FAIL spill")
		failures += 1
	if not is_equal_approx(SliceLogic.spill_integrity(10.0, 20.0), 0.0):
		print("FAIL spill floor")
		failures += 1
	# Settlement: base 30 + on-time 10 + zero-spill 10 = 50.
	if SliceLogic.settlement_pay(30, true, true, 100.0, false, false) != 50:
		print("FAIL settlement perfect")
		failures += 1
	# Late halves, report offsets a quarter of base: (45+10) * 0.5 + 11.25 = 38.75 -> 39.
	if SliceLogic.settlement_pay(45, false, true, 100.0, true, true) != 39:
		print("FAIL settlement late+report, got %d" % SliceLogic.settlement_pay(45, false, true, 100.0, true, true))
		failures += 1
	if SliceLogic.review_for(true, 100.0, false) != "好评":
		print("FAIL review good")
		failures += 1
	if SliceLogic.review_for(true, 100.0, true) != "中评":
		print("FAIL review over-urged")
		failures += 1
	# Props: 6 props, red-team pillar heights 2 / 4 / 8, extraction rules.
	if GameData.PROPS.size() != 6:
		print("FAIL props != 6")
		failures += 1
	if not is_equal_approx(SliceLogic.prop_pillar_height("normal"), 2.0):
		print("FAIL normal pillar != 2m")
		failures += 1
	if not is_equal_approx(SliceLogic.prop_pillar_height("epic"), 4.0):
		print("FAIL epic pillar != 4m")
		failures += 1
	if not is_equal_approx(SliceLogic.prop_pillar_height("legendary"), 8.0):
		print("FAIL legendary pillar != 8m")
		failures += 1
	if SliceLogic.prop_tier_frame("legendary") != "传说·金框":
		print("FAIL legendary frame")
		failures += 1
	if SliceLogic.prop_is_extractable("drink") or not SliceLogic.prop_is_extractable("grip_tyre"):
		print("FAIL prop extraction rules")
		failures += 1
	if SliceLogic.prop_is_extractable("golden_box") or not SliceLogic.prop_is_extractable("tool_slot"):
		print("FAIL prop extraction rules 2")
		failures += 1
	# Per-run caps: normal 2, epic 1, legendary 1.
	if int(GameData.PROP_TIERS["normal"]["per_run_cap"]) != 2 or int(GameData.PROP_TIERS["epic"]["per_run_cap"]) != 1 or int(GameData.PROP_TIERS["legendary"]["per_run_cap"]) != 1:
		print("FAIL per-run caps")
		failures += 1
	# Stat caps: spill 50%, speed 130%, range 150%.
	if not is_equal_approx(SliceLogic.clamp_spill_resist(0.9), 0.5):
		print("FAIL spill cap")
		failures += 1
	if not is_equal_approx(SliceLogic.clamp_speed(10.0, 20.0), 13.0):
		print("FAIL speed cap")
		failures += 1
	if not is_equal_approx(SliceLogic.clamp_range(8.0, 20.0), 12.0):
		print("FAIL range cap")
		failures += 1
	# Mutual exclusion: grip_tyre <-> golden_box.
	if not SliceLogic.props_excluded("grip_tyre", "golden_box") or SliceLogic.props_excluded("grip_tyre", "drink"):
		print("FAIL mutual exclusion")
		failures += 1
	# Vehicle gate: large trunk vehicles cannot take small-last-100m orders.
	if SliceLogic.vehicle_can_take("car", "light_meal") or SliceLogic.vehicle_can_take("van", "light_meal"):
		print("FAIL vehicle gate car/van light_meal")
		failures += 1
	if not SliceLogic.vehicle_can_take("e_bike", "light_meal") or not SliceLogic.vehicle_can_take("car", "family_bag"):
		print("FAIL vehicle gate e_bike/car")
		failures += 1
	# Skill caps: max 6, at most 2 drive-away.
	if not SliceLogic.validate_skills(["drive_away", "urge", "nitrogen"]):
		print("FAIL skill valid set")
		failures += 1
	if SliceLogic.validate_skills(["drive_away", "drive_away", "drive_away"]):
		print("FAIL skill drive-away cap")
		failures += 1
	if SliceLogic.validate_skills(["a", "b", "c", "d", "e", "f", "g"]):
		print("FAIL skill total cap")
		failures += 1
	# Tuning validation: ok / yellow / orange / red.
	if SliceLogic.tuning_validate(20.0, "spill_damage") != "ok":
		print("FAIL tuning ok")
		failures += 1
	if SliceLogic.tuning_validate(28.0, "spill_damage") != "yellow":
		print("FAIL tuning yellow")
		failures += 1
	if SliceLogic.tuning_validate(30.0, "spill_damage") != "orange":
		print("FAIL tuning orange")
		failures += 1
	if SliceLogic.tuning_validate(31.0, "spill_damage") != "red":
		print("FAIL tuning red")
		failures += 1
	# Run upgrades never extract: upgrade ids are not prop ids.
	for up in GameData.UPGRADES:
		if GameData.PROPS.has(up["id"]):
			print("FAIL upgrade in props")
			failures += 1
	# Save round-trip on a test path only (never the real inventory).
	var test_inv: Array = ["grip_tyre", "starter_pack"]
	if not SaveSystem.save_state(test_inv, 2, "user://test_inventory2.json"):
		print("FAIL save state")
		failures += 1
	if SaveSystem.load_inventory("user://test_inventory2.json") != test_inv:
		print("FAIL load inventory round-trip")
		failures += 1
	if SaveSystem.load_difficulty("user://test_inventory2.json") != 2:
		print("FAIL load difficulty")
		failures += 1
	# Rollback: save a second time (first save creates the backup slot
	# on the second write), corrupt the main file, rollback restores it.
	if not SaveSystem.save_state(test_inv, 2, "user://test_inventory2.json"):
		print("FAIL save state second")
		failures += 1
	var corrupt := FileAccess.open("user://test_inventory2.json", FileAccess.WRITE)
	corrupt.store_string("not json")
	corrupt.close()
	var rolled: Array = SaveSystem.rollback("user://test_inventory2.json")
	if rolled != test_inv:
		print("FAIL rollback, got %s" % str(rolled))
		failures += 1
	if failures == 0:
		print("PASS all slice logic tests")
	else:
		print("FAIL %d logic tests" % failures)
	quit()
