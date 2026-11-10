extends RefCounted
## Primary owner for causal ordering and continuation. Small original owners
## make duplicate effects, starvation and invalid dependency plans observable.
const Kernel = preload("res://scripts/sim/execution/settlement_kernel.gd")

class Owner extends RefCounted:
	var effects: Array[String] = []
	var count: int = 0
	var due: int = 17
	var allowance: int = 0
	func exhausted() -> bool:
		if allowance <= 0:
			return true
		allowance -= 1
		return false
	func effect(_at_ms: int, id: String) -> void:
		effects.append(id)
	func boundary() -> int:
		return due
	func many(_at_ms: int, budget: int) -> Vector2i:
		var work: int = mini(10000 - count, budget)
		count += work
		return Vector2i(work, Kernel.Status.COMPLETE if count == 10000 else Kernel.Status.PENDING)
	func fail(_at_ms: int) -> bool:
		return false
	func invalid_receipt(_at_ms: int, budget: int) -> Vector2i:
		return Vector2i(budget + 1, Kernel.Status.COMPLETE)
	func many_cooperative(_at_ms: int, budget: int, source: WeakRef) -> Vector2i:
		var used: int = 0
		while used < budget and count < 10000:
			count += 1
			used += 1
			if (source.get_ref() as SimSettlementKernel).should_yield_work():
				break
		return Vector2i(used, Kernel.Status.COMPLETE if count == 10000 else Kernel.Status.PENDING)


func run(runner: Object) -> void:
	_order_and_continuation(runner)
	_rejected_plans(runner)
	_budgeted_owner(runner)
	_host_yield(runner)
	_failure_stops_dependents(runner)
	print("SCENARIO settlement kernel: compiled dependencies, stable ties, exact continuation, bounded work and failure barrier")


func _plan(owner: Owner, reversed: bool) -> SimSettlementKernel:
	var kernel := Kernel.new([&"past", &"effects", &"decisions"])
	var ids: Array[String] = ["heat", "weather", "wound", "choice"]
	if reversed:
		ids.reverse()
	for id: String in ids:
		var phase: StringName = &"past" if id in ["heat", "weather"] else &"effects" if id == "wound" else &"decisions"
		kernel.add_step(StringName(id), phase, owner.effect.bind(id), Kernel.CallMode.TIMED, ["weather"] if id == "heat" else [], ["wound"] if id == "heat" else [])
	kernel.add_boundary(&"heat", owner.boundary, true)
	kernel.compile()
	return kernel


func _order_and_continuation(runner: Object) -> void:
	var a := Owner.new()
	var b := Owner.new()
	var one: SimSettlementKernel = _plan(a, false)
	var split: SimSettlementKernel = _plan(b, true)
	runner.assert_eq(one.contract(), split.contract(), "registration order does not decide causal ordering")
	runner.assert_eq(one.next_boundary_ms(30, true), 17, "registered runtime boundaries read the original owner")
	a.due = 9
	runner.assert_eq(one.next_boundary_ms(30), 9, "a changed owner deadline is not hidden by stale kernel predictions")
	runner.assert_true(one.begin(0, 20) and split.begin(0, 20), "both kernels accept the same forward interval")
	runner.assert_eq(split.resume(0), Kernel.Status.PENDING, "zero budget preserves the exact unstarted boundary")
	runner.assert_true(b.effects.is_empty() and not split.begin(20, 21), "pending execution cannot be overwritten")
	runner.assert_eq(one.resume(100), Kernel.Status.COMPLETE, "unlimited work settles all registered phases")
	for index: int in 4:
		var result: int = split.resume(1)
		runner.assert_eq(result, Kernel.Status.COMPLETE if index == 3 else Kernel.Status.PENDING, "single-step work retains the next causal stage")
		runner.assert_eq(split.last_work, 1, "each continuation consumes only its declared allowance")
	runner.assert_eq(a.effects, ["weather", "heat", "wound", "choice"], "past conditions precede effects and future choices")
	runner.assert_eq(a.effects, b.effects, "splitting a boundary neither repeats nor loses an effect")
	runner.assert_true(not one.add_step(&"late", &"effects", a.effect.bind("late")), "running models cannot mutate the compiled plan")
	var detached: Dictionary = one.contract()
	detached.steps.clear()
	runner.assert_eq(one.contract().steps.size(), 4, "diagnostics cannot rewrite the compiled plan")


func _rejected_plans(runner: Object) -> void:
	var owner := Owner.new()
	var cyclic := Kernel.new([&"effects"])
	cyclic.add_step(&"a", &"effects", owner.effect.bind("a"), Kernel.CallMode.TIMED, ["b"])
	cyclic.add_step(&"b", &"effects", owner.effect.bind("b"), Kernel.CallMode.TIMED, ["a"])
	runner.assert_true(not cyclic.compile() and not cyclic.begin(0, 1), "zero-time dependency cycles fail before any state is touched")
	var missing := Kernel.new([&"effects"])
	missing.add_step(&"a", &"effects", owner.effect.bind("a"), Kernel.CallMode.TIMED, ["missing"])
	runner.assert_true(not missing.compile(), "unknown dependencies cannot silently run in registration order")
	var backwards := Kernel.new([&"past", &"effects"])
	backwards.add_step(&"a", &"past", owner.effect.bind("a"), Kernel.CallMode.TIMED, ["b"])
	backwards.add_step(&"b", &"effects", owner.effect.bind("b"))
	runner.assert_true(not backwards.compile() and owner.effects.is_empty(), "a later effect cannot retroactively change its past input phase")
	var ties := Kernel.new([&"effects"])
	ties.add_step(&"b", &"effects", owner.effect.bind("b"))
	ties.add_step(&"a", &"effects", owner.effect.bind("a"))
	runner.assert_true(ties.compile() and ties.begin(0, 1), "independent same-time steps have a stable tie rule")
	ties.resume(2)
	runner.assert_eq(owner.effects, ["a", "b"], "only causally incomparable steps use the stable identifier tie")


func _budgeted_owner(runner: Object) -> void:
	var owner := Owner.new()
	var kernel := Kernel.new([&"effects"])
	kernel.add_step(&"many", &"effects", owner.many, Kernel.CallMode.BUDGETED)
	kernel.add_step(&"result", &"effects", owner.effect.bind("done"), Kernel.CallMode.TIMED, ["many"])
	runner.assert_true(kernel.compile() and kernel.begin(0, 10), "a domain may retain its own large-work cursor")
	var work: int = 0
	for _attempt: int in 100:
		var result: int = kernel.resume(127)
		work += kernel.last_work
		if result == Kernel.Status.COMPLETE:
			break
	runner.assert_true(not kernel.is_pending() and owner.count == 10000, "finite budgets eventually complete every original work item")
	runner.assert_eq(work, 10001, "work receipts account for each item once plus the dependent effect")
	runner.assert_eq(owner.effects, ["done"], "the dependent effect waits for the last item and runs once")
	var invalid := Kernel.new([&"effects"])
	invalid.add_step(&"bad", &"effects", owner.invalid_receipt, Kernel.CallMode.BUDGETED)
	invalid.compile()
	invalid.begin(0, 1)
	runner.assert_eq(invalid.resume(4), Kernel.Status.FAILED, "an owner cannot claim work beyond the accepted budget")


func _failure_stops_dependents(runner: Object) -> void:
	var owner := Owner.new()
	var kernel := Kernel.new([&"effects"])
	kernel.add_step(&"fail", &"effects", owner.fail, Kernel.CallMode.CHECKED)
	kernel.add_step(&"later", &"effects", owner.effect.bind("later"), Kernel.CallMode.TIMED, ["fail"])
	kernel.compile()
	kernel.begin(0, 1)
	runner.assert_eq(kernel.resume(10), Kernel.Status.FAILED, "a real owner failure is distinct from ordinary budget debt")
	runner.assert_true(owner.effects.is_empty() and kernel.is_pending(), "failed boundaries cannot publish dependent effects or completion")
	runner.assert_eq(kernel.resume(10), Kernel.Status.FAILED, "failed work is not retried with duplicated side effects")


func _host_yield(runner: Object) -> void:
	var owner := Owner.new()
	var kernel: SimSettlementKernel = _plan(owner, false)
	kernel.begin(0, 20)
	runner.assert_eq(kernel.resume(100, owner.exhausted), Kernel.Status.PENDING, "an exhausted host deadline changes no logical step")
	runner.assert_true(owner.effects.is_empty() and kernel.last_work == 0, "a deadline can yield before the first effect without publishing")
	for _index in 4:
		owner.allowance = 1
		kernel.resume(100, owner.exhausted)
	runner.assert_eq(owner.effects, ["weather", "heat", "wound", "choice"], "host deadline yields preserve the same complete causal order")
	runner.assert_true(not kernel.is_pending(), "fresh host budgets eventually complete the retained boundary")
	var batch := Owner.new()
	var cooperative := Kernel.new([&"effects"])
	cooperative.add_step(&"many", &"effects", batch.many_cooperative.bind(weakref(cooperative)), Kernel.CallMode.BUDGETED)
	cooperative.add_step(&"done", &"effects", batch.effect.bind("done"), Kernel.CallMode.TIMED, [&"many"])
	cooperative.compile()
	cooperative.begin(0, 1)
	batch.allowance = 3
	runner.assert_eq(cooperative.resume(10000, batch.exhausted), Kernel.Status.PENDING, "a domain can yield between its bounded units at the same host deadline")
	runner.assert_true(batch.count == 3 and cooperative.last_work == 3 and batch.effects.is_empty(), "intra-domain deadline retains the exact cursor and blocks dependents")
	runner.assert_true(not cooperative.should_yield_work(), "a completed resume does not retain a live host deadline")
	runner.assert_eq(cooperative.resume(10000), Kernel.Status.COMPLETE, "the next resume installs its own deadline policy")
	runner.assert_eq([batch.count, batch.effects], [10000, ["done"]], "cooperative domain continuation completes each original unit and dependent once")
