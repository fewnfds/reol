extends RefCounted
## Contact outcomes and personal commitments, not a global relationship scan.
## Learning, physical possessions, practiced skill and stored qi are distinct.

const State = preload("res://scripts/sim/kernel/state.gd")
const Units = preload("res://scripts/sim/kernel/units.gd")
const ACTIONS: Array[String] = ["talk", "trade", "request_help", "learn", "study", "practice"]
var completed: Dictionary = {}


func initialize(world: RefCounted) -> void:
	if not world.actor_slots.has(2):
		return
	world.release(2)
	var page: RefCounted = world.pages[0]
	page.positions[1] = Vector2(177.5, 187.5)
	page.modes[1] = Units.Mode.IDLE
	var teacher: Dictionary = world.objects.records[2]
	teacher.autonomous = false
	teacher["name"] = "旅居修士"
	teacher["methods"] = {"wood_breath": {"teacher": 0, "learned_ms": 0}}
	world.objects.add(2, "breath_manual", 1)
	world.objects.add(2, "meal", 4)
	world.livelihood.observe(world, 2, 0)


func available(world: RefCounted, actor: int, action: Dictionary) -> bool:
	var rec: Dictionary = world.objects.records[action.target]
	if action.kind == "practice":
		return rec.kind == "plant" and rec.definition == "old_tree" and rec.stage == world.nature.Stage.MATURE
	if action.kind == "study":
		return actor == action.target and world.objects.amount(actor, "breath_manual") > 0
	return (rec.kind == "actor" and actor != action.target) or (rec.kind == "plant" and rec.get("sapient", false))


func invite(world: RefCounted, actor: int, action: Dictionary) -> void:
	var target: int = action.target
	if target == actor or not world.actor_slots.has(target) or action.kind not in ["talk", "trade", "learn", "request_help"]:
		return
	var slot: int = world.actor_slots[target]
	var page: RefCounted = world.pages[slot / 256]
	if world.actions.has(target) or world.combat.orders.has(target) or page.health[slot % 256] < 30:
		return # A busy/unwilling partner need not stop; contact can fail normally.
	action["partner_waiting"] = true
	action["partner_resume"] = world.objects.records[target].get("autonomous", false)
	world.release(target)
	page.modes[slot % 256] = Units.Mode.IDLE


func interrupt(world: RefCounted, action: Dictionary, now: int) -> void:
	if not action.get("partner_waiting", false) or not world.actor_slots.has(action.target):
		return
	var slot: int = world.actor_slots[action.target]
	var page: RefCounted = world.pages[slot / 256]
	# Never overwrite a newer player command or a defensive combat response.
	if action.get("partner_resume", false) and world.objects.records[action.target].get("autonomous", false) and page.health[slot % 256] > 0 and page.modes[slot % 256] == Units.Mode.IDLE and not world.actions.has(action.target) and not world.combat.orders.has(action.target):
		world.livelihood.after_action(world, action.target, now)


func finish(world: RefCounted, actor: int, action: Dictionary, now: int) -> String:
	var person: Dictionary = world.objects.records[actor]
	var other: Dictionary = world.objects.records[action.target]
	var slot: int = world.actor_slots[actor]
	var page: RefCounted = world.pages[slot / 256]
	var row: int = slot % 256
	match action.kind:
		"talk":
			if not person.has("known"):
				person["known"] = {}
			for subject: int in other.get("known", {}):
				var clue: Dictionary = other.known[subject]
				if not person.known.has(subject) or int(person.known[subject].seen_ms) < int(clue.seen_ms):
					var copy: Dictionary = State.copy(clue)
					copy["source"] = action.target
					copy["hops"] = int(clue.get("hops", 0)) + 1
					person.known[subject] = copy
					_count(action.kind)
					return "shared_clue_%d" % subject
			return "no_new_clue"
		"trade":
			var give: String = str(action.get("give_item", "potion"))
			var want: String = str(action.get("want_item", "breath_manual"))
			var given: int = int(action.get("give_amount", 1))
			var wanted: int = int(action.get("want_amount", 1))
			if not world.objects.definitions.has(give) or not world.objects.definitions.has(want) or given <= 0 or wanted <= 0:
				return "invalid_offer"
			var value: Dictionary = {"wood": 1, "grain": 2, "water": 2, "meal": 5, "potion": 12, "breath_manual": 10}
			if given * int(value.get(give, 1)) < wanted * int(value.get(want, 1)):
				return "refused_value"
			if world.actor_slots.has(action.target):
				var other_slot: int = world.actor_slots[action.target]
				var other_page: RefCounted = world.pages[other_slot / 256]
				if want == "potion" and other_page.health[other_slot % 256] < 60 and world.objects.amount(action.target, want) <= wanted:
					return "refused_need"
			if not world.objects.exchange(actor, action.target, give, given, want, wanted):
				return "missing_items_or_capacity"
			world._sync_inventory(actor)
			if world.actor_slots.has(action.target):
				world._sync_inventory(action.target)
		"request_help":
			var target: int = int(action.get("task_target", 0))
			if not world.actor_slots.has(action.target) or other.has("commitment"):
				return "refused_busy_or_body"
			if world.objects.records.get(target, {}).get("kind", "") != "blueprint":
				return "invalid_task"
			if not person.get("known", {}).has(target) and world.combat.position(world, actor).distance_to(world.combat.position(world, target)) > 24:
				return "unknown_task"
			var other_slot: int = world.actor_slots[action.target]
			var other_page: RefCounted = world.pages[other_slot / 256]
			if other_page.hunger[other_slot % 256] < 3000 or other_page.energy[other_slot % 256] < 2500:
				return "refused_need"
			other["commitment"] = {"kind": "construct", "target": target, "requester": actor, "expires_ms": now + 300000,
				"was_autonomous": other.get("autonomous", false)}
			world.livelihood.remember(world, action.target, target, now)
			other.autonomous = true
			action["partner_resume"] = true
		"learn", "study":
			if action.kind == "learn" and not other.get("methods", {}).has("wood_breath"):
				return "teacher_does_not_know"
			if action.kind == "study" and world.objects.amount(actor, "breath_manual") <= 0:
				return "missing_book"
			if not person.has("methods"):
				person["methods"] = {}
			person.methods["wood_breath"] = {"teacher": action.target if action.kind == "learn" else 0, "learned_ms": now}
		"practice":
			if not available(world, actor, action):
				return "plant_not_mature"
			if not person.get("methods", {}).has("wood_breath"):
				return "method_not_known"
			if page.energy[row] < 800 or page.hunger[row] < 800 or page.body_heat[row] < 0 or page.body_heat[row] > 50:
				return "body_not_ready"
			var qi: int = int(other.get("qi", 0))
			if qi < 100:
				return "insufficient_stored_qi"
			other.qi = qi - 100 # Actual stored qi; environmental wood is not consumed.
			page.energy[row] -= 300
			page.hunger[row] -= 100
			person["qi"] = int(person.get("qi", 0)) + 60
			person["practice"] = int(person.get("practice", 0)) + 350
			if person.practice >= 1000:
				person["abilities"] = {"wood_mend": true}
	_count(action.kind)
	return "completed"


func _count(kind: String) -> void:
	completed[kind] = int(completed.get(kind, 0)) + 1


func use_ability(world: RefCounted, actor: int) -> String:
	var rec: Dictionary = world.objects.records[actor]
	if not rec.get("abilities", {}).get("wood_mend", false):
		return "ability_not_mastered"
	var slot: int = world.actor_slots[actor]
	var page: RefCounted = world.pages[slot / 256]
	var row: int = slot % 256
	if int(rec.get("qi", 0)) < 20 or page.energy[row] < 500 or page.health[row] >= 100:
		return "insufficient_qi_energy_or_full"
	rec.qi -= 20
	page.energy[row] -= 500
	page.health[row] = mini(100, page.health[row] + 25)
	return "ability_used"
