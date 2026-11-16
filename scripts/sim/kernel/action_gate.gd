extends RefCounted
## Rebuildable occupation index. Phase, deadlines and paid facts stay in each host.
const Defs = preload("res://scripts/sim/kernel/action_defs.gd")
const Beings = preload("res://scripts/sim/kernel/being_defs.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
var bindings: Dictionary = {}

func current(actor: int) -> Dictionary:
	return bindings.get(actor, {}).duplicate()

func matches(actor: int, expected: Dictionary) -> bool:
	return current(actor) == expected

func bind(actor: int, domain: String, run_id: int) -> void:
	assert(not bindings.has(actor))
	bindings[actor] = {"domain": domain, "run_id": run_id}

func unbind(actor: int, domain: String, run_id: int) -> bool:
	if bindings.get(actor, {}) != {"domain": domain, "run_id": run_id}: return false
	bindings.erase(actor)
	return true

func check(world: RefCounted, actor: int, now: int, button: String = "") -> String:
	if not world.objects.records.has(actor): return "dead"
	if not world.actor_slots.has(actor): return "unsupported_carrier"
	if not world.combat.alive(world, actor): return "dead"
	if now < int(world.combat.status.get(actor, {}).get("stun_until", 0)): return "stunned"
	var state: Dictionary = world.combat.states.get(actor, {})
	if not state.is_empty() and now < (Defs.end_ms(state) if button.is_empty() else Defs.cancel_ms(state, button)): return "action_committed"
	return ""

func rebuild(world: RefCounted) -> bool:
	bindings.clear()
	if world.next_run < 1: return false
	var seen: Dictionary = {}
	for actor: Variant in world.work_runs:
		var host: Variant = world.work_runs[actor]
		if not host is Dictionary or host.size() != 2 or not host.get("run_id") is int or not host.get("purpose") is String or (not host.purpose.is_empty() and host.purpose not in world.institutions.ISSUE_PURPOSES): return false
		var run: Variant = host.run_id
		if not actor is int or not world.actor_slots.has(actor) or not run is int or run < 1 or run >= world.next_run or seen.has(run): return false
		if not world.combat.alive(world, actor): return false
		var slot: int = world.actor_slots[actor]
		if world.pages[slot / 256].modes[slot % 256] in [world.Units.Mode.RESOURCE, world.Units.Mode.HARVEST] and not Beings.has(world.objects.records[actor], "work"): return false
		if world.pages[slot / 256].modes[slot % 256] in [world.Units.Mode.RESOURCE, world.Units.Mode.HARVEST] and host.purpose.is_empty(): return false
		if world.pages[slot / 256].modes[slot % 256] not in [world.Units.Mode.RESOURCE, world.Units.Mode.HARVEST, world.Units.Mode.REST, world.Units.Mode.MANUAL, world.Units.Mode.EXPLORE]: return false
		seen[run] = true
		bind(actor, "work", run)
	for actor: int in world.actions:
		var run: Variant = world.actions[actor].get("run_id")
		if not run is int or run < 1 or run >= world.next_run or seen.has(run) or bindings.has(actor): return false
		if not world.combat.alive(world, actor): return false
		var slot: int = world.actor_slots[actor]
		if world.pages[slot / 256].modes[slot % 256] not in [world.Units.Mode.APPROACH, world.Units.Mode.ACTION]: return false
		for key: String in ["waiting", "autonomous", "partner_waiting", "partner_resume"]:
			if world.actions[actor].has(key) and not world.actions[actor][key] is bool: return false
		if world.actions[actor].has("started_ms") and (not world.actions[actor].started_ms is int or world.actions[actor].started_ms < 0 or world.actions[actor].started_ms > world.elapsed_ms): return false
		var action: Dictionary = world.actions[actor]
		if action.has("started_ms") and (world.pages[slot / 256].modes[slot % 256] != world.Units.Mode.ACTION or action.get("waiting", false)): return false
		if not action.get("participants") is Array or action.participants.is_empty() or action.participants.size() > 2 or action.participants[0] != actor: return false
		if action.participants.size() == 2 and (action.participants[1] != action.target or action.target == actor or Operations.OPERATIONS[action.kind].executor != "society" or not action.has("started_ms")): return false
		if action.participants.size() == 2 and action.target != 1 and world.actor_slots.has(action.target) and not action.get("partner_waiting", false): return false
		if action.has("worked_ms") and (not action.worked_ms is int or action.worked_ms < 0): return false
		seen[run] = true
		bind(actor, "interaction", run)
	for actor: int in world.combat.states:
		if bindings.has(actor): return false
		bind(actor, "combat", world.combat.states[actor].activation)
	for actor: Variant in world.society.waits:
		var wait: Variant = world.society.waits[actor]
		if not actor is int or not world.actor_slots.has(actor) or not world.combat.alive(world, actor) or bindings.has(actor) or not wait is Dictionary: return false
		if not Beings.has(world.objects.records[actor], "contact"): return false
		if not wait.get("run_id") is int or wait.run_id < 1 or wait.run_id >= world.next_run or seen.has(wait.run_id): return false
		if not wait.get("actor") is int or not wait.get("owner_run") is int or world.actions.get(wait.actor, {}).get("run_id") != wait.owner_run or world.actions[wait.actor].target != actor: return false
		if not world.actions[wait.actor].get("partner_waiting", false): return false
		seen[wait.run_id] = true
		bind(actor, "partner", wait.run_id)
	for actor: int in world.actions:
		var action: Dictionary = world.actions[actor]
		if action.get("partner_waiting", false) and (Operations.OPERATIONS[action.kind].executor != "society" or world.society.waits.get(action.target, {}).get("owner_run") != action.run_id or world.society.waits[action.target].actor != actor): return false
	for target: int in world.reservations:
		var actor: int = world.reservations[target]
		if not world.combat.alive(world, actor): return false
		if world.actions.has(actor) and world.actions[actor].target == target and Operations.OPERATIONS[world.actions[actor].kind].exclusive: continue
		if not world.work_runs.has(actor): return false
		var slot: int = world.actor_slots[actor]
		var page: RefCounted = world.pages[slot / 256]
		if page.modes[slot % 256] not in [world.Units.Mode.RESOURCE, world.Units.Mode.HARVEST] or world.source_objects[page.source_ids[slot % 256]] != target: return false
	for actor: int in world.actor_slots:
		var slot: int = world.actor_slots[actor]
		if world.pages[slot / 256].modes[slot % 256] in [world.Units.Mode.APPROACH, world.Units.Mode.ACTION] and not world.actions.has(actor): return false
		if world.pages[slot / 256].modes[slot % 256] in [world.Units.Mode.RESOURCE, world.Units.Mode.HARVEST, world.Units.Mode.REST, world.Units.Mode.MANUAL, world.Units.Mode.EXPLORE] and not world.work_runs.has(actor): return false
	return true
