class_name LifeTimeMigration
extends RefCounted
## Explicit minute-native v1 -> shared-time v2 conversion. Sources stay immutable.

const MINUTE_MS: int = 60000


static func village(source: Dictionary, content: ReolContentDB, allowed: Dictionary = {}) -> Dictionary:
	if not SimSnapshotSchema.validate(source, content, allowed, true):
		return {}
	if source.has("elapsed_ms") or float(source.tick_index) > floorf(float(SimInventory.MAX_COUNT) / MINUTE_MS):
		return {}
	var result: Dictionary = source.duplicate(true)
	var now: int = int(source.tick_index) * MINUTE_MS
	result["version"] = 2
	result["elapsed_ms"] = now
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SimLocalMotion.RULES_PATH))
	@warning_ignore("integer_division")
	var maximum_minutes: int = SimInventory.MAX_COUNT / MINUTE_MS
	for actor: Dictionary in result.actors.values():
		if actor.has("position") or actor.has("need_carry") or actor.has("retry_ms"):
			return {}
		var point: Vector2 = TileGrid.cell_to_world(Vector2i(int(actor.cell[0]), int(actor.cell[1])))
		actor["position"] = [point.x, point.y]
		if int(actor.retry_at) > maximum_minutes:
			return {}
		actor["retry_ms"] = int(actor.retry_at) * MINUTE_MS
		actor.erase("retry_at")
		actor["need_carry"] = {"hunger": 0, "energy": 0}
		actor["exertion_until_ms"] = 0
		actor["stamina_carry"] = 0
		var action: Dictionary = actor.active
		if action.is_empty():
			continue
		# Work already completed in old history is untouched; unfinished work
		# keeps its remaining duration. A road's fractional old step maps to
		# the same fraction of the new physical step, with no premature cargo.
		if int(action.started) > maximum_minutes:
			return {}
		action["started_ms"] = int(action.started) * MINUTE_MS
		action["segment_from"] = actor.position.duplicate()
		action["segment_started_ms"] = now
		var duration: int = maxi(1, ceili(float(action.remaining) * MINUTE_MS))
		if action.phase == "travel":
			duration = 1
			if not action.path.is_empty():
				var target: Vector2 = TileGrid.cell_to_world(Vector2i(int(action.path[0][0]), int(action.path[0][1])))
				var fraction: float = float(action.move_left) / float(result.config.move_minutes_per_cell)
				duration = maxi(1, ceili(point.distance_to(target) / float(rules.motion.speed) * 1000.0 * fraction))
		if duration > SimInventory.MAX_COUNT - now:
			return {}
		action["due_ms"] = now + duration
		action.erase("remaining")
		action.erase("move_left")
		action.erase("started")
	return result
