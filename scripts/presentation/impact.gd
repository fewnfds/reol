extends RefCounted
## Presentation classification, never used to settle an attack.
const Defs = preload("res://scripts/sim/kernel/action_defs.gd")
static func key(event: Dictionary) -> String:
	return "%s:%s:%s:%s:%s:%s" % [event.get("epoch", 0), event.actor, event.get("activation", 0), event.get("target", 0), event.kind, event.at_ms]

static func tone(event: Dictionary) -> String:
	match str(event.kind):
		"action_started": return "warning" if int(Defs.ACTIONS.get(event.get("action", ""), {}).get("post", 0)) > 0 else ""
		"action_active":
			var def: Dictionary = Defs.ACTIONS.get(event.get("action", ""), {})
			if def.is_empty(): return ""
			if def.delivery.kind == "blink": return "step"
			if def.delivery.kind == "direct": return "armor" if def.payload.any(func(effect: Dictionary): return effect.kind in ["guard", "shield"]) else "evade"
			if def.delivery.kind == "entity": return "evade"
			if def.stat == "ranged": return "shot"
			if def.delivery.kind == "evade": return "step"
			return "swing_heavy" if preload("res://scripts/sim/kernel/effect_payload.gd").summary(def.payload).heavy_hit else "swish"
		"area_trigger": return "heavy"
		"implement_hit": return "armor"
		"hit":
			if event.get("guarded", false) or int(event.get("blocked", 0)) > 0 or (int(event.get("absorbed", 0)) > 0 and int(event.get("damage", 0)) == 0): return "armor"
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
