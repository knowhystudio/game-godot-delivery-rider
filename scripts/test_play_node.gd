extends Node
## Frame-driven play-through test. Run with the test scene, not --script:
## godot --headless --path . res://scenes/test_play.tscn
## _ready adds the main scene; _process (first frame) runs the play-through
## with the same methods the UI buttons / keys call, then quits.

var _done := false


func _ready() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main_node: Node3D = scene.instantiate()
	main_node.name = "TestMain"
	add_child(main_node)


func _process(_delta: float) -> void:
	if _done:
		return
	_done = true
	var main = $TestMain
	var failures := 0
	if main.delivered_count != 0:
		print("FAIL start delivered != 0")
		failures += 1
	main._on_accept("light_meal")
	if main.accepted_count() != 1:
		print("FAIL accept light_meal")
		failures += 1
	main.orders["light_meal"]["prep_left"] = 0.0
	main.rider.global_position = main.city.merchant_pos("A")
	main._do_action()
	if main.orders["light_meal"]["state"] != "carried":
		print("FAIL pickup light_meal, state=%s" % main.orders["light_meal"]["state"])
		failures += 1
	main.rider.global_position = main.city.customer_pos("A")
	main._do_action()
	if main.orders["light_meal"]["state"] != "delivered" or main.delivered_count != 1:
		print("FAIL deliver light_meal")
		failures += 1
	if main.coins != 50:
		print("FAIL coins after perfect first delivery, got %d" % main.coins)
		failures += 1
	main._on_accept("hot_soup")
	main.orders["hot_soup"]["prep_left"] = 0.0
	main.rider.global_position = main.city.merchant_pos("B")
	main._do_action()
	main.rider.global_position = main.city.customer_pos("B")
	main._do_action()
	if main.delivered_count != 2 or main.phase != "upgrade":
		print("FAIL upgrade trigger, delivered=%d phase=%s" % [main.delivered_count, main.phase])
		failures += 1
	main._on_upgrade("big_box")
	if main.capacity() != 3 or main.phase != "playing":
		print("FAIL upgrade apply, capacity=%d phase=%s" % [main.capacity(), main.phase])
		failures += 1
	main._on_accept("family_bag")
	main.orders["family_bag"]["prep_left"] = 0.0
	main.rider.global_position = main.city.merchant_pos("C")
	main._do_action()
	main.rider.global_position = main.city.customer_pos("C")
	main._do_action()
	if main.delivered_count != 3:
		print("FAIL deliver family_bag")
		failures += 1
	# Props: run-only drink restores stamina; extractable grip tyre is
	# carried out at settlement into the saved inventory, but only
	# after registering at the extraction point (early-stage rule).
	main.rider.stamina = 50.0
	main._collect_prop(main.city.props[0])
	if main.rider.stamina != 80.0:
		print("FAIL prop drink stamina, got %f" % main.rider.stamina)
		failures += 1
	main._collect_prop(main.city.props[3])
	if main.extracted_pending != ["grip_tyre"]:
		print("FAIL prop extracted_pending")
		failures += 1
	main.rider.global_position = main.city.extraction_node.global_position
	main._do_extract()
	if not main.extraction_registered:
		print("FAIL extraction registration")
		failures += 1
	main._on_end_shift()
	if not main.inventory.has("grip_tyre"):
		print("FAIL prop extraction to inventory")
		failures += 1
	# Extraction cost: 1 epic = 5% of 195 = 10, so coins 195 -> 185.
	if main.coins != 185:
		print("FAIL extraction cost, coins=%d" % main.coins)
		failures += 1
	if main.settlement_step != 1:
		print("FAIL settlement step 1")
		failures += 1
	main._advance_settlement()
	if main.settlement_step != 2:
		print("FAIL settlement step 2")
		failures += 1
	main._advance_settlement()
	if main.settlement_step != 3 or main.settlement_sync_left != 2.0:
		print("FAIL settlement step 3 sync")
		failures += 1
	if main.phase != "settled":
		print("FAIL settlement phase")
		failures += 1
	if failures == 0:
		print("PASS play-through: 3 delivered, coins=%d, reputation=%d, capacity=%d, props+extraction ok" % [main.coins, main.reputation, main.capacity()])
	else:
		print("FAIL %d play-through checks" % failures)
	get_tree().quit()
