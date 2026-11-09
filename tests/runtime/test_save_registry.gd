extends RefCounted
## One owner for participant extension, candidate isolation and scope grants.
const Participant = preload("res://tests/runtime/helpers/save_participant.gd")

class Host extends RefCounted:
	var first: RefCounted
	var second: RefCounted


func run(runner: Object) -> void:
	var registry := SimSaveRegistry.new()
	var loader: Callable = func(owner: RefCounted, data: Dictionary, _context: Dictionary) -> bool:
		return owner.restore(data)
	var checker: Callable = func(owner: RefCounted, context: Dictionary) -> bool:
		return owner.amount >= context.owners.first.amount
	runner.assert_true(registry.add(&"first", &"one", Participant, loader), "register the first persistent owner with its wire key")
	runner.assert_true(not registry.add(&"first", &"other", Participant, loader), "duplicate owner registration is rejected")
	runner.assert_true(not registry.add(&"other", &"one", Participant, loader), "duplicate wire key is rejected")
	var host := Host.new()
	host.first = Participant.new()
	host.first.amount = 3
	host.first.note = "new ordinary field"
	var saved: Dictionary = registry.capture(host)
	runner.assert_eq(saved.one.note, host.first.note, "a new owner field travels through the unchanged capture loop")
	host.first.amount = -1
	runner.assert_true(registry.capture(host).is_empty(), "an incomplete owner capture cannot masquerade as a save record")
	host.first.amount = 3
	runner.assert_true(registry.add(&"second", &"two", Participant, loader, checker), "a new domain needs one adapter registration")
	host.second = Participant.new()
	host.second.amount = 7
	saved = registry.capture(host)
	var original: RefCounted = host.first
	var context: Dictionary = {}
	runner.assert_true(registry.stage(saved, context), "the same pipeline stages both registered owners")
	runner.assert_true(host.first == original and context.owners.first != original, "staging creates independent owners before live installation")
	runner.assert_true(registry.install(host, context), "a fully checked candidate installs")
	runner.assert_eq([host.first.bound_total, host.second.bound_total], [10, 10], "all owners are installed before any bind callback runs")
	runner.assert_eq(host.first.note, "new ordinary field", "owner fields survive staging and installation")
	runner.assert_true(not registry.install(host, context), "a consumed candidate cannot be installed twice")
	var live: RefCounted = host.first
	var bad: Dictionary = saved.duplicate(true)
	bad.two.amount = 1
	context = {}
	runner.assert_true(not registry.stage(bad, context), "cross-owner validation rejects an inconsistent candidate")
	runner.assert_true(not registry.install(host, context) and host.first == live, "failed staging cannot replace a live owner")
	bad = saved.duplicate(true)
	bad.erase("two")
	runner.assert_true(not registry.stage(bad, {}), "missing domain data is rejected before construction")
	for strict_first: bool in [true, false]:
		var scopes := SimSaveRegistry.new()
		var scope: Callable = func(_data: Variant, _region: String, _content: RefCounted) -> Dictionary:
			return {"containers": {"original": true}}
		scopes.add(&"first", &"one", Participant, loader, Callable(), Callable(), Callable(), scope, strict_first)
		scopes.add(&"second", &"two", Participant, loader, Callable(), Callable(), Callable(), scope, not strict_first)
		runner.assert_true(scopes.inventory_scope(saved, "home", null).is_empty(), "protected custody IDs cannot be overwritten in either registration order")
	print("SCENARIO save registry: field/domain extension, independent validation, all-owner bind and protected custody scope")
