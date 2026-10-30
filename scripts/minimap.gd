extends Control
## Minimap, top-right. Heading-up: the map rotates so the rider's
## forward direction points up, player always centred. Speed-adaptive
## zoom: fast = zoom out (larger world range), slow = zoom in.
## Only ONE ground route line is drawn (to the next target); other
## targets are icons / edge indicators, never extra route lines.
## Shapes distinguish targets, not colour alone.

var data := {}


func set_data(d: Dictionary) -> void:
	data = d
	queue_redraw()


func _map_point(p: Vector3) -> Vector2:
	# Relative to player, rotated by -heading, scaled by zoom, centred.
	var player_pos: Vector3 = data.get("player", Vector3.ZERO)
	var heading: float = float(data.get("heading", 0.0))
	var speed: float = float(data.get("speed", 0.0))
	var zoom := 1.4 if speed > 8.0 else 1.0
	var rel := Vector3(p.x - player_pos.x, 0, p.z - player_pos.z)
	var c := cos(-heading)
	var s := sin(-heading)
	var rx := rel.x * c - rel.z * s
	var rz := rel.x * s + rel.z * c
	var scale := (size.x / 2.0) / (60.0 * zoom)
	return Vector2(size.x / 2.0 + rx * scale, size.y / 2.0 + rz * scale)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.1, 0.15, 0.85))
	var player_pos: Vector3 = data.get("player", Vector3.ZERO)
	var centre := Vector2(size.x / 2.0, size.y / 2.0)
	var target: Vector3 = data.get("target", Vector3.ZERO)
	if data.get("has_target", false):
		var b := _map_point(target)
		# Edge indicator if the target is off-map: clamp to the border.
		if b.x < 4.0 or b.x > size.x - 4.0 or b.y < 4.0 or b.y > size.y - 4.0:
			b = Vector2(clampf(b.x, 8.0, size.x - 8.0), clampf(b.y, 8.0, size.y - 8.0))
			draw_colored_polygon(PackedVector2Array([b + Vector2(0, -6), b + Vector2(5, 5), b + Vector2(-5, 5)]), Color(1.0, 1.0, 0.0))
		else:
			# One main dashed route line only.
			var steps := 12
			for i in range(steps):
				if i % 2 == 0:
					var t0 := float(i) / float(steps)
					var t1 := float(i + 1) / float(steps)
					draw_line(centre.lerp(b, t0), centre.lerp(b, t1), Color(1, 1, 1, 0.8), 2.0)
	for key in ["merchants", "customers"]:
		var arr: Array = data.get(key, [])
		for p in arr:
			var mp := _map_point(p)
			if mp.x < 0.0 or mp.x > size.x or mp.y < 0.0 or mp.y > size.y:
				continue
			if key == "merchants":
				draw_rect(Rect2(mp - Vector2(4, 4), Vector2(8, 8)), Color(0.2, 0.8, 0.3))
			else:
				draw_colored_polygon(PackedVector2Array([mp + Vector2(0, -6), mp + Vector2(5, 5), mp + Vector2(-5, 5)]), Color(1.0, 0.6, 0.1))
	var sp := _map_point(data.get("station", Vector3.ZERO))
	if sp.x >= 0.0 and sp.x <= size.x and sp.y >= 0.0 and sp.y <= size.y:
		draw_rect(Rect2(sp - Vector2(6, 6), Vector2(12, 12)), Color(0.3, 0.5, 1.0))
	if data.get("reward_visible", false):
		var rp := _map_point(data.get("reward", Vector3.ZERO))
		draw_colored_polygon(PackedVector2Array([rp + Vector2(0, -6), rp + Vector2(5, 0), rp + Vector2(0, 6), rp + Vector2(-5, 0)]), Color(1.0, 0.9, 0.2))
	if data.get("exploration_visible", false):
		var ep := _map_point(data.get("exploration", Vector3.ZERO))
		draw_circle(ep, 4.0, Color(0.2, 0.9, 0.9))
	for p in data.get("blockers", []):
		var bp := _map_point(p)
		if bp.x < 0.0 or bp.x > size.x or bp.y < 0.0 or bp.y > size.y:
			continue
		draw_colored_polygon(PackedVector2Array([bp + Vector2(0, -4), bp + Vector2(4, 0), bp + Vector2(0, 4), bp + Vector2(-4, 0)]), Color(0.85, 0.3, 0.5))
	# Player is always centred, heading up.
	draw_circle(centre, 6.0, Color(1.0, 0.85, 0.1))
