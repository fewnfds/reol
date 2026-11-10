extends RefCounted
## Primary contract owner for host admission/rate control. The tiny combat
## example specifies scheduling, not Reol's health or consumable game rules.
const Kernel = preload("res://scripts/sim/execution/settlement_kernel.gd")

class Timeline extends RefCounted:
	var now: int = 0
	var heal_ms: int = 990
	var health: int = 5
	var dead: bool = false
	var used: bool = false
	var hit: bool = false
	var work_budget: int = 100
	var trace: Array[String] = []
	var kernel: SimSettlementKernel
	func _init(at: int, budget: int) -> void:
		heal_ms = at
		work_budget = budget
		kernel = Kernel.new([&"effects"])
		kernel.add_step(&"heal", &"effects", heal)
		kernel.add_step(&"attack", &"effects", attack, Kernel.CallMode.TIMED, [&"heal"])
		kernel.compile()
	func heal(at: int) -> void:
		if at == heal_ms and not used:
			used = true
			if not dead:
				health += 10
			trace.append("heal:%d" % at)
	func attack(at: int) -> void:
		if at == 1000 and not hit:
			hit = true
			health -= 12
			dead = health <= 0
			trace.append("attack:%d" % at)
	func execute(_from: int, end: int) -> int:
		while now < end or kernel.is_pending():
			if not kernel.is_pending():
				var next: int = end
				if not used:
					next = mini(next, heal_ms)
				if not hit:
					next = mini(next, 1000)
				kernel.begin(now, next)
			if kernel.resume(work_budget) != Kernel.Status.COMPLETE:
				return now
			now = kernel.at_ms
		return now


func run(runner: Object) -> void:
	_admission_and_retained_work(runner)
	_rate_and_restore(runner)
	_short_boundary_cost(runner)
	for heal_at: int in [990, 1000, 1010]:
		var fast: Dictionary = _future(heal_at, false)
		var slow: Dictionary = _future(heal_at, true)
		runner.assert_eq(fast, slow, "host rate and split phases cannot invert healing/attack at %d" % heal_at)
		runner.assert_eq(fast.health, -7 if heal_at > 1000 else 3, "explicit same-time healing-before-attack rule is stable")
	print("SCENARIO simulation pacing: bounded admission, retained debt, gradual recovery and identical event futures")


func _admission_and_retained_work(runner: Object) -> void:
	var clock := ReolGameClock.new()
	var executor := Timeline.new(990, 0)
	clock.bind_interval_executor(executor.execute)
	clock.advance_frame(0.05)
	for _frame in 100:
		clock.advance_frame(1.0)
	runner.assert_true(clock.elapsed_ms == 0 and is_equal_approx(clock._accumulator, 250.0), "a blocked world cannot accumulate beyond the finite admitted horizon")
	runner.assert_true(clock.has_pending_advance() and executor.trace.is_empty(), "old accepted work is retained without speculative effects")
	executor.work_budget = 100
	clock.advance_frame(0.0)
	runner.assert_eq(clock.elapsed_ms, 250, "recovery finishes exactly the accepted old intervals")
	clock.advance_frame(0.0)
	runner.assert_eq(clock.elapsed_ms, 250, "the deliberately slowed wall time is not replayed after recovery")
	clock.free()


func _rate_and_restore(runner: Object) -> void:
	var clock := ReolGameClock.new()
	clock.set_speed(4.0)
	clock.pacing.observe(0.016, 8000, 1, true, clock.speed)
	var slow_rate: float = clock.pacing.rate
	runner.assert_true(slow_rate < 0.1 and clock.speed == 4.0, "load changes admission rate while retaining the player's selected speed")
	clock.pacing.observe(0.016, 1, 50, false, clock.speed)
	runner.assert_true(clock.pacing.rate <= slow_rate + 0.00401, "a cheap frame cannot instantly restore full speed")
	for _frame in 800:
		clock.pacing.observe(0.016, 1, 50, false, clock.speed)
	runner.assert_true(is_equal_approx(clock.pacing.rate, 1.0), "sustained available capacity gradually restores selected speed")
	clock._accumulator = 17.25
	clock.pacing.observe(0.016, 8000, 1, true, clock.speed)
	var saved: Dictionary = clock.to_dict()
	var restored := ReolGameClock.new()
	runner.assert_true(restored.restore_state(saved), "existing clock schema accepts admitted fractional debt")
	runner.assert_eq(restored.to_dict(), saved, "restoring preserves causal time, pause and requested speed")
	runner.assert_eq(restored.pacing.rate, 1.0, "machine-specific performance history is rebuilt rather than saved as a world rule")
	restored.set_paused(true)
	restored.advance_frame(1000.0)
	runner.assert_eq(restored.to_dict().frame_debt_ms, 17.25, "paused host time does not become new simulation debt")
	clock.free()
	restored.free()


func _short_boundary_cost(runner: Object) -> void:
	var pacing := ReolSimulationPacing.new()
	for _sample: int in 60:
		pacing.observe(1.0 / 60.0, 2000, 50, false, 1.0)
	# An exact action/weather boundary can split an otherwise ordinary frame
	# into one millisecond. Its fixed publication cost is not sustained cost
	# per millisecond across the whole already measured workload.
	pacing.observe(1.0 / 60.0, 2000, 1, false, 1.0)
	runner.assert_true(pacing.rate > 0.9, "one cheap short boundary cannot turn spare capacity into prolonged severe slowdown")
	for _sample: int in 120:
		pacing.observe(1.0 / 60.0, 12000, 10, false, 1.0)
	runner.assert_true(pacing.rate < 0.5, "sustained expensive work still throttles future admission")
	var before: float = pacing.rate
	pacing.observe(1.0 / 60.0, 1, 50, false, 1.0)
	runner.assert_true(pacing.rate <= before + ReolSimulationPacing.RECOVERY_PER_SECOND / 60.0 + 0.00001, "windowed cost estimation preserves gradual recovery")


func _future(heal_at: int, overloaded: bool) -> Dictionary:
	var clock := ReolGameClock.new()
	var executor := Timeline.new(heal_at, 1 if overloaded else 100)
	clock.bind_interval_executor(executor.execute)
	clock.time_advanced.connect(func(_from: int, to: int) -> void:
		if to >= 1100:
			clock.set_paused(true)
	)
	for _frame in 10000:
		var before: int = clock.elapsed_ms
		clock.advance_frame(0.05 if overloaded else 0.1)
		clock.pacing.observe(0.05, 6000 if overloaded else 10, clock.elapsed_ms - before, clock.has_pending_advance(), clock.speed)
		if clock.paused:
			break
	var result: Dictionary = {"at_ms": clock.elapsed_ms, "health": executor.health, "dead": executor.dead, "used": executor.used, "hit": executor.hit, "trace": executor.trace.duplicate()}
	clock.free()
	return result
