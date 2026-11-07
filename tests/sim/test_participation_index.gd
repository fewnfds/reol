extends RefCounted
## The index contains disposable participation/work hints, not domain state.

const Index = preload("res://scripts/sim/execution/participation_index.gd")


func run(runner: Object) -> void:
	_membership_and_dirty(runner)
	_due_work_and_order(runner)
	_due_updates_against_reference(runner)
	_sparse_limited_work(runner)
	print("SCENARIO participation index: independent membership, activity, dirty revisions, bounded due work and deterministic rebuild")


func _membership_and_dirty(runner: Object) -> void:
	var index: RefCounted = Index.new()
	runner.assert_true(not index.set_member(&"", "actor"), "an empty category is rejected")
	runner.assert_true(not index.set_member(&"sight", ""), "an empty subject is rejected")
	runner.assert_true(not index.set_active(&"sight", "actor", true), "an unregistered subject cannot become active")
	runner.assert_eq(index.mark_dirty(&"sight", "actor", &"moved"), 0, "an unregistered subject cannot receive pending work")
	runner.assert_true(index.set_member(&"sight", "b") and index.set_member(&"sight", "a") and index.set_member(&"sound", "a"), "independent categories can register the same subject")
	runner.assert_true(index.set_member(&"sight", "a") and index.set_active(&"sight", "b", true) and index.set_active(&"sight", "a", true), "repeat membership and activity transitions are valid")
	runner.assert_eq(index.member_ids(&"sight"), ["a", "b"], "member snapshots have stable id order")
	var active: Array[String] = index.active_ids(&"sight")
	active.clear()
	runner.assert_eq(index.active_ids(&"sight"), ["a", "b"], "mutating a returned snapshot cannot mutate the index")
	runner.assert_true(index.set_active(&"sight", "a", false), "a member can become inactive")
	var before: int = index.mark_dirty(&"sight", "a", &"moved")
	var after: int = index.mark_dirty(&"sight", "a", &"changed")
	runner.assert_true(before > 0 and after > before and not index.ack_dirty(&"sight", "a", before), "a new invalidation cannot be cleared by an old snapshot")
	var pending: Array[Dictionary] = index.pending_dirty(&"sight", 1)
	runner.assert_true(pending.size() == 1 and pending[0].id == "a" and int(pending[0].revision) == after, "inactive members can have pending wake-up work")
	runner.assert_true(pending[0].reasons.has(&"changed") and pending[0].reasons.has(&"moved"), "different reasons coalesce without losing either")
	pending[0].reasons.clear()
	runner.assert_eq(index.pending_dirty(&"sight")[0].reasons.size(), 2, "returned dirty reasons are detached from live work")
	runner.assert_true(index.ack_dirty(&"sight", "a", after) and index.pending_dirty(&"sight").is_empty(), "only a successfully processed current revision is acknowledged")
	var old: int = index.mark_dirty(&"sight", "a", &"again")
	runner.assert_true(index.set_member(&"sight", "a", false) and index.set_member(&"sight", "a"), "a subject can be removed and registered again")
	var replacement: int = index.mark_dirty(&"sight", "a", &"again")
	runner.assert_true(replacement > old and not index.ack_dirty(&"sight", "a", old), "remove and re-add cannot cause an old acknowledgement to clear new work")
	index.clear()
	index.set_member(&"sight", "a")
	var restored: int = index.mark_dirty(&"sight", "a", &"again")
	runner.assert_true(restored > replacement and not index.ack_dirty(&"sight", "a", replacement), "rebuilding the same index also preserves stale-ack protection")


func _due_work_and_order(runner: Object) -> void:
	var index: RefCounted = Index.new()
	for id: String in ["d", "b", "c", "a"]:
		index.set_member(&"work", id)
	index.set_due(&"work", "a", 100)
	index.set_due(&"work", "b", 100)
	index.set_due(&"work", "c", 50)
	index.set_due(&"work", "d", 150)
	runner.assert_true(not index.set_due(&"work", "a", -1) and not index.set_due(&"work", "missing", 1), "invalid deadlines leave existing work unchanged")
	runner.assert_eq(index.next_due_ms(&"work", 999), 50, "next deadline follows the earliest registered subject")
	runner.assert_eq(index.due_ids(&"work", 100, 10), ["c", "a", "b"], "equal deadlines have stable id order")
	runner.assert_eq(index.due_ids(&"work", 100, 1), ["c"], "the owner may limit work to its current budget")
	runner.assert_eq(index.due_ids(&"work", 100, 1), ["c"], "queries do not consume unprocessed work")
	index.set_due(&"work", "c", 200)
	index.set_due(&"work", "b", 20)
	runner.assert_eq(index.due_ids(&"work", 100, 10), ["b", "a"], "rescheduling earlier and later maintains the ordered deadline index")
	index.cancel_due(&"work", "b")
	index.set_member(&"work", "a", false)
	runner.assert_eq(index.due_ids(&"work", 200, 10), ["d", "c"], "cancellation and member removal remove their deadlines")
	index.set_member(&"work", "c", false)
	index.set_member(&"work", "d", false)
	runner.assert_eq(index.next_due_ms(&"work", 999), 999, "an empty queue returns the caller's fallback")


func _due_updates_against_reference(runner: Object) -> void:
	var index: RefCounted = Index.new()
	var reference: Dictionary = {}
	for value: int in 128:
		index.set_member(&"time", "entry:%03d" % value)
	for step: int in 384:
		var id: String = "entry:%03d" % ((step * 53 + 7) % 128)
		if step % 5 == 0:
			index.cancel_due(&"time", id)
			reference.erase(id)
		else:
			@warning_ignore("integer_division")
			var at_ms: int = (step * 37 + step / 7) % 91
			index.set_due(&"time", id, at_ms)
			reference[id] = at_ms
		if step % 32 == 0 or step == 383:
			var rows: Array[Dictionary] = []
			for key: String in reference:
				rows.append({"id": key, "time": int(reference[key])})
			rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return int(a.time) < int(b.time) or (int(a.time) == int(b.time) and str(a.id) < str(b.id)))
			var expected: Array[String] = []
			for row: Dictionary in rows:
				if int(row.time) <= 60:
					expected.append(str(row.id))
			runner.assert_eq(index.due_ids(&"time", 60), expected, "updated deadlines agree with an independent sorted reference")
			runner.assert_eq(index.diagnostics(&"time").due, reference.size(), "rescheduling does not accumulate stale heap entries")


func _sparse_limited_work(runner: Object) -> void:
	var index: RefCounted = Index.new()
	for value: int in 2048:
		var id: String = "due:%04d" % value
		index.set_member(&"jobs", id)
		index.set_due(&"jobs", id, value)
	for value: int in 2048:
		index.set_member(&"unrelated", "other:%04d" % value)
	var selected: Array[String] = index.due_ids(&"jobs", 2048, 2)
	var facts: Dictionary = index.diagnostics(&"jobs")
	runner.assert_eq(selected, ["due:0000", "due:0001"], "a small budget receives only its earliest due subjects")
	runner.assert_true(int(facts.last_due_examined) <= 5, "limited due queries inspect only the root and selected-node children, not the entire heap")
	runner.assert_eq(int(facts.due), 2048, "limited queries preserve the unprocessed backlog")
	index.cancel_due(&"jobs", selected[0])
	index.cancel_due(&"jobs", selected[1])
	runner.assert_eq(index.due_ids(&"jobs", 2048, 1), ["due:0002"], "the following owner step resumes from the remaining work")
