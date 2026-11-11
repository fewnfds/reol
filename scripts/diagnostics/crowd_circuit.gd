class_name ReolCrowdCircuit
extends RefCounted
## Temporary load producer on the same owner thread as the world. It issues
## original commands at route deadlines; no host-frame polling or fake motion.
const CIRCUIT: Array[String] = ["rest", "inspect", "check_store", "check_well"]
var _world: WeakRef
var world: RegionalSimulation:
	get: return _world.get_ref()
var complex: RefCounted
var starts: Dictionary = {}
var moved: Dictionary = {}
var orders: Dictionary = {}
var legs: Dictionary = {}
var due := SimParticipationIndex.new()
var regions: Dictionary[String, String] = {}
var last_ms: int = 0
var travel_actor_ms: int = 0
var sampled_world_ms: int = 0
var last_travelling: int = 0
var next_count_ms: int = 0
var redirects: int = 0
var work_usec: int = 0


func configure(authority: RegionalSimulation) -> void:
	_world = weakref(authority)
	last_ms = world.elapsed_ms


func sample() -> void:
	if not world.accepts_commands() or world.elapsed_ms == last_ms:
		return
	var began: int = Time.get_ticks_usec()
	var span: int = world.elapsed_ms - last_ms
	sampled_world_ms += span
	travel_actor_ms += last_travelling * span
	last_ms = world.elapsed_ms
	if complex != null and world.elapsed_ms == world.target_ms:
		complex.sample()
	for id: String in due.due_ids(&"circuit", world.elapsed_ms):
		var region: String = regions[id]
		var sim: VillageSimulation = world.regions[region]
		if not moved.has(id) and sim.projected_actor_position(id) != starts[id]:
			moved[id] = true
		var person: Dictionary = sim.actor_state(id)
		if legs.has(id) and bool(person.alive):
			var ready: bool = person.active.is_empty() or (person.active.get("id", "") == orders.get(id, "") and person.active.get("phase") == "work")
			if ready and not world.advance_region_to_world(region):
				continue
			if person.active.get("id", "") == orders.get(id, "") and person.active.get("phase") == "work":
				sim.cancel_action(id, "stress_circuit")
				world.invalidate_region(world.clothing.home(id), id)
				legs[id] = (int(legs[id]) + 1) % CIRCUIT.size()
				redirects += 1
			if person.active.is_empty() and sim.submit_action(id, CIRCUIT[int(legs[id])]):
				orders[id] = str(person.active.id)
				world.invalidate_region(world.clothing.home(id), id)
		var completion: Dictionary = sim.native_route_projections().get(id, {})
		due.set_due(&"circuit", id, maxi(sim.elapsed_ms + 1, int(completion.get("at_ms", sim.elapsed_ms + 250))))
	if world.elapsed_ms >= next_count_ms:
		next_count_ms = world.elapsed_ms + 500
		last_travelling = 0
		for sim: VillageSimulation in world.regions.values():
			for id: String in sim.actors:
				if sim.actor_state(id).active.get("phase") == "travel":
					last_travelling += 1
				if not moved.has(id) and sim.projected_actor_position(id) != starts.get(id, Vector2.ZERO):
					moved[id] = true
	work_usec += Time.get_ticks_usec() - began
