extends RefCounted
## Opt-in bounded release workload; normal actions in the sole World, not a simulator.
const Scenarios = preload("res://scripts/sim/kernel/scenarios.gd")
var _last_action: int = -1
var actions: int = 0
var accepted: int = 0
var peak_bolts: int = 0
var peak_effects: int = 0

func setup(world: RefCounted) -> void:
	# v1 deliberately retains the default-to-ranged equipment transition used
	# by the recorded comparison. Keep fixture assembly entirely in this helper.
	Scenarios.combat_lab(world, "mixed", "bloodblade")
	Scenarios.combat_lab(world, "mixed", "barrage")
	# Explicit durability fixture so the measured work cannot vanish through death.
	for actor: int in [1, world.actor_count, world.actor_count - 1, world.actor_count - 2]:
		var stats: Dictionary = world.objects.records[actor].get("base_stats", {}).duplicate()
		stats["max_hp"] = 1000000.0
		world.objects.records[actor]["base_stats"] = stats
		world.Equipment.rebuild(world, actor)
		var slot: int = world.actor_slots[actor]
		world.pages[slot / 256].health[slot % 256] = 1000000

func advance(world: RefCounted) -> void:
	var now: int = world.elapsed_ms
	var phase: int = now % 2400
	var point: Vector2 = world.combat.position(world, world.actor_count)
	var aim: Vector2 = world.combat.position(world, 1).direction_to(point)
	if aim.is_zero_approx(): aim = Vector2.RIGHT
	world.combat.set_control(world, {"enabled": true, "primary": phase < 700 or phase >= 1700, "move": Vector2.ZERO, "aim": aim, "point": point})
	var index: int = now / 2400 * 2 + int(phase >= 1200)
	if phase >= 700 and phase < 1700 and index != _last_action:
		_last_action = index
		var result: Dictionary = world.command({"kind": "action", "actor": 1, "button": "skill" if phase < 1200 else "skill2", "aim": aim, "point": point})
		actions += 1
		accepted += int(result.ok)
	peak_bolts = maxi(peak_bolts, world.combat.bolts.size())
	peak_effects = maxi(peak_effects, world.effects.records.size())

func report(world: RefCounted) -> Dictionary:
	# Peaks are observations at main-step boundaries since setup, not in-slice
	# maxima or a difference of warm-up/capture peaks.
	return {"fixture": "framework-combat-v1", "actions": actions, "accepted_actions": accepted, "peak_bolts": peak_bolts, "peak_effects": peak_effects,
		"intervals": world.intervals, "preparation_usec": world.preparation_usec, "units_usec": world.units_usec, "effects_usec": world.effects_usec,
		"environment_usec": world.environment_usec, "perception_usec": world.perception.work_usec, "step_usec": world.step_usec,
		"index_calls": world.combat.scan.index_calls, "index_rebuilds": world.combat.scan.index_rebuilds, "index_usec": world.combat.scan.index_usec}
