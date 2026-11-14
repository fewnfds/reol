extends RefCounted
## Presentation classification, never used to settle an attack.
static func key(event: Dictionary) -> String:
	return "%s:%s:%s:%s:%s:%s" % [event.get("epoch", 0), event.actor, event.get("activation", 0), event.get("target", 0), event.kind, event.at_ms]

static func tone(event: Dictionary) -> String:
	match str(event.kind):
		"action_started": return "warning" if str(event.get("action", "")).begins_with("enemy_") else ""
		"action_active":
			if event.get("action") in ["shot", "fan", "enemy_shot"]: return "shot"
			if event.get("action") == "step": return "step"
			return "swing_heavy" if event.get("action") in ["slash_3", "cleave", "enemy_heavy"] else "swish"
		"hit":
			if event.get("target") == 1: return "hurt"
			if event.get("armored", false): return "armor"
			if event.get("off_balance", false): return "break"
			return "heavy" if event.get("heavy_hit", false) else "hit"
		"evaded": return "evade"
		"death": return "death"
	return ""

static func visible(frame: RefCounted, event: Dictionary, fog: bool) -> bool:
	var id: int = int(event.get("target", event.actor)) if event.kind in ["hit", "evaded"] else int(event.actor)
	var slot: int = int(frame.actor_slots.get(id, -1))
	if slot < 0 or (fog and id != 1 and frame.visible[slot] == 0): return false
	return frame.positions[slot].distance_to(frame.positions[frame.actor_slots[1]]) <= 22.0
