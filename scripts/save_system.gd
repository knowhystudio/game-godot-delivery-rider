extends RefCounted
class_name SaveSystem
## Out-of-run save. Extraction writes ONLY definition id + tier, never
## per-run instance state. Two slots: main + backup (rollback).
## Format: {"inventory": [ids], "difficulty": int, "version": 1}
## Old inventory-only files still load (difficulty defaults to 0).

const MAIN_PATH := "user://delivery_inventory.json"
const BACKUP_PATH := "user://delivery_inventory.bak.json"


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		return data
	return {}


static func _inventory_from(data: Dictionary) -> Array:
	if data.get("inventory") is Array:
		var out: Array = []
		for item in data["inventory"]:
			if item is String:
				out.append(item)
		return out
	return []


static func load_inventory(path: String = MAIN_PATH) -> Array:
	var data := _read(path)
	if data.is_empty():
		# Corrupt / missing main: roll back to the backup slot.
		data = _read(BACKUP_PATH)
	return _inventory_from(data)


static func load_difficulty(path: String = MAIN_PATH) -> int:
	var data := _read(path)
	if data.is_empty():
		data = _read(BACKUP_PATH)
	if data.get("difficulty") is float:
		return int(data["difficulty"])
	return 0


static func save_inventory(inventory: Array, path: String = MAIN_PATH) -> bool:
	return save_state(inventory, load_difficulty(path), path)


static func save_state(inventory: Array, difficulty: int, path: String = MAIN_PATH) -> bool:
	# Snapshot the previous main file into the backup slot first, so a
	# bad write can roll back. Backup path is fixed for the real slot;
	# test paths use a sibling .bak file so tests never touch real data.
	var backup := BACKUP_PATH
	if path != MAIN_PATH:
		backup = path + ".bak"
	if FileAccess.file_exists(path):
		var old := FileAccess.open(path, FileAccess.READ)
		if old != null:
			var text := old.get_as_text()
			old.close()
			var b := FileAccess.open(backup, FileAccess.WRITE)
			if b != null:
				b.store_string(text)
				b.close()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({
		"inventory": inventory, "difficulty": difficulty, "version": 1,
	}))
	f.close()
	return true


static func rollback(path: String = MAIN_PATH) -> Array:
	var backup := BACKUP_PATH
	if path != MAIN_PATH:
		backup = path + ".bak"
	var data := _read(backup)
	if data.is_empty():
		return []
	var inv := _inventory_from(data)
	save_state(inv, int(data.get("difficulty", 0)) if data.get("difficulty") is float else 0, path)
	return inv
