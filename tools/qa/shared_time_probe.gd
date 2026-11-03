extends SceneTree
## Isolated temporal-semantics spike. It does not change the live game's units.
## godot --headless --path . --script res://tools/qa/shared_time_probe.gd

const UNITS_PER_MINUTE: int = 60000

var failures: int = 0


class ProbeWorld extends RefCounted:
	var state: Dictionary = {
		"now": 0, "target": 0, "cursor": 0, "paused": false,
		"materials": 2, "output": 0, "hits": 0, "known_message": false,
		"trace": [],
	}
	# All times are absolute integer units on one timeline, including messages
	# and minute-only production. Ordinary life does not run ahead of a strike.
	var events: Array[Dictionary] = [
		{"at": 120, "kind": "pay_material"},
		{"at": 360, "kind": "impact"},
		{"at": 800, "kind": "recovery_end"},
		{"at": 21000, "kind": "distant_secret"},
		{"at": 42000, "kind": "message_received"},
		{"at": 60000, "kind": "minute_production"},
		{"at": 90000, "kind": "long_action_end"},
	]


	func advance(target: int, budget: int, interrupt_on_message: bool) -> bool:
		if target < int(state.now) or budget < 1:
			return false
		state.target = maxi(target, int(state.target))
		while int(state.cursor) < events.size():
			var event: Dictionary = events[int(state.cursor)]
			if int(event.at) > int(state.target):
				break
			if state.paused or budget == 0:
				return false
			state.now = event.at
			state.cursor = int(state.cursor) + 1
			budget -= 1
			state.trace.append(event.kind)
			match event.kind:
				"pay_material": state.materials = int(state.materials) - 1
				"impact": state.hits = int(state.hits) + 1
				"minute_production": state.output = int(state.output) + 1
				"message_received":
					state.known_message = true
					state.paused = interrupt_on_message
		if state.paused:
			return false
		state.now = state.target
		return true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var direct := ProbeWorld.new()
	_expect(direct.advance(90000, 100, false), "direct event timeline finishes")
	var budgeted := ProbeWorld.new()
	_expect(not budgeted.advance(90000, 2, false), "bounded work returns pending")
	_expect(budgeted.state.now == 360 and budgeted.state.target == 90000, "commit and requested horizon remain separate")
	_expect(budgeted.state.hits == 1 and budgeted.state.output == 0, "subminute impact cannot receive future minute output")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(budgeted.state))
	var resumed := ProbeWorld.new()
	resumed.state = saved
	while not resumed.advance(90000, 2, false):
		pass
	_expect(_canonical(resumed.state) == _canonical(direct.state), "JSON mid-action resume and budgets preserve the same result")
	resumed.advance(90000, 2, false)
	_expect(resumed.state.hits == 1 and resumed.state.output == 1 and resumed.state.materials == 1, "retrying a horizon cannot duplicate effects or refund costs")
	var interrupted := ProbeWorld.new()
	_expect(not interrupted.advance(90000, 100, true), "received message interrupts fast-forward")
	_expect(interrupted.state.now == 42000 and interrupted.state.known_message and interrupted.state.output == 0, "interruption is at actual receipt, before future production")
	_expect(interrupted.state.trace.has("distant_secret"), "distant secret occurs without leaking or interrupting")
	interrupted.state.paused = false
	_expect(interrupted.advance(90000, 100, false), "resume keeps previous cost and time")
	_expect(_canonical(interrupted.state) == _canonical(direct.state), "interrupted and direct runs converge on the same world")
	# Candidate A's (minute, phase) maps exactly to candidate B's scalar time.
	# This proves equivalence for this finite schedule, not whole-game migration.
	for time: int in [0, 360, 59999, 60000, 60001, 90000, 3153600000000]:
		var minute: int = floori(float(time) / UNITS_PER_MINUTE)
		var phase: int = time % UNITS_PER_MINUTE
		_expect(minute * UNITS_PER_MINUTE + phase == time, "minute plus phase agrees with integer scalar at %d" % time)
	var report: Dictionary = {"failures": failures, "units_per_minute": UNITS_PER_MINUTE,
		"subminute_impact": 360, "message_interrupt": 42000, "minute_output": 60000,
		"final_state": direct.state, "status": "isolated_probe_only"}
	var file: FileAccess = FileAccess.open("res://logs/shared_time_probe.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t", true, true))
	file.close()
	print("TIME PROBE %s" % JSON.stringify(report, "", true, true))
	quit(0 if failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL " + message)


func _canonical(data: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(data, "", true, true)), "", true, true)
