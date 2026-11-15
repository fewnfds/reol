extends RefCounted
## Named domain operations own their conservation and completion semantics.
## No generic transaction: combat and manual hosts call the same real operation.
static func check(world: RefCounted, actor: int, target: int, operation: String) -> String:
	match operation:
		"tend": return world.nature.tend_check(world, actor, target)
	return "unknown_operation"

static func commit(world: RefCounted, actor: int, target: int, operation: String, at: int) -> Dictionary:
	var reason: String = check(world, actor, target, operation)
	if reason.is_empty():
		match operation:
			"tend": reason = world.nature.tend(world, actor, target, at)
	var result: Dictionary = {"kind": "domain_result", "operation": operation, "actor": actor, "target": target,
		"at_ms": at, "ok": reason == "completed", "amount": 1 if reason == "completed" else 0, "reason": reason}
	world.emit(result)
	return result
