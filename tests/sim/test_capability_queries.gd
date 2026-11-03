extends RefCounted
## A personal sourced view must never become the source of knowledge itself.

const Queries = preload("res://scripts/sim/capability_queries.gd")
const Fixtures = preload("res://tests/sim/test_method_records.gd")
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_definitions_and_identity(runner)
	_real_teaching_and_read_only_views(runner)
	_hearing_is_not_embodied_learning(runner)
	_private_versions_and_written_steps(runner)
	_real_mobile_practice(runner)
	print("SCENARIO capability queries: seven personal sourced projections, original completed lessons and artifact learning, unread/read/practiced separation, private immutable versions, actual paid/cancelled/completed walking practice, typed evidence and mutation-free browsing")


func _make(runner: Object) -> RegionalSimulation:
	return _fixtures._world(runner)


func _node(world: RegionalSimulation, actor: String, id: String) -> Dictionary:
	for row: Dictionary in Queries.project(world, actor).nodes:
		if row.id == id:
			return row
	return {}


func _canonical(world: RegionalSimulation) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(world.to_dict()))


func _definitions_and_identity(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	if world == null:
		return
	var definitions: Dictionary = world._content.capability_network
	runner.assert_true(Queries.valid_definitions(definitions), "seven display definitions validate independently of any learned-state mirror")
	for fault: String in ["extra", "missing_node", "unknown_kind", "bad_edge", "duplicate_edge", "untyped_summary"]:
		var bad: Dictionary = definitions.duplicate(true)
		match fault:
			"extra": bad["learned"] = {}
			"missing_node": bad.nodes.erase("sword")
			"unknown_kind": bad.nodes.sword.kind = "universal_skill"
			"bad_edge": bad.edges[0].to = "nonexistent"
			"duplicate_edge": bad.edges.append(bad.edges[0].duplicate(true))
			"untyped_summary": bad.nodes.mobile_guard.summary = true
		runner.assert_true(not Queries.valid_definitions(bad), "bounded personal view definition rejects " + fault)
	var before: String = _canonical(world)
	var view: Dictionary = Queries.project(world, "player")
	runner.assert_true(view.allowed and view.nodes.size() == 7, "ordinary current human can inspect exactly seven bounded display categories")
	runner.assert_eq(view.at_ms, world.elapsed_ms, "projection reports the original committed world time without its own clock")
	runner.assert_eq(_node(world, "player", "sword").state, "unknown", "merely standing beside a swordsman never grants sword knowledge")
	runner.assert_eq(_node(world, "player", "stone_channeling").state, "unknown", "merely seeing a warm stone does not grant its method")
	var experienced: Dictionary = _node(world, "chen_shouzhuo", "sword")
	runner.assert_eq(experienced.state, "learned", "original capable background is projected without a new learned table")
	runner.assert_eq(experienced.sources[0].kind, "background", "background knowledge has an explicitly typed original domain source")
	runner.assert_eq(experienced.sources[0].at_ms, -1, "undated original background does not invent a historical zero-millisecond lesson")
	var denied: Dictionary = Queries.project(world, "player", "chen_shouzhuo")
	runner.assert_true(not denied.allowed and denied.nodes.is_empty() and denied.edges.is_empty(), "requesting another person's graph reveals no private methods, histories or current resources")
	# Denial precedes even world-shape access: no opponent query is necessary.
	denied = Queries.project(RefCounted.new(), "player", "chen_shouzhuo")
	runner.assert_true(not denied.allowed and denied.nodes.is_empty(), "foreign private graph is denied before reading any target authority")
	runner.assert_eq(_canonical(world), before, "identity, definitions and opening queries write no evidence, randomness or bodily state")
	view.edges.clear()
	view.nodes[0].sources.append({"invented": true})
	runner.assert_eq(Queries.project(world, "player").edges.size(), definitions.edges.size(), "mutating a disposable graph cannot edit static links or later views")
	runner.assert_eq(_canonical(world), before, "mutating a returned private view cannot create original learned evidence")


func _real_teaching_and_read_only_views(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	if world == null:
		return
	runner.assert_true(world.conflicts.teach("chen_shouzhuo", "player").ok, "query scenario begins the original actual paired demonstration")
	if world.conflicts.lessons.is_empty():
		return
	var lesson: Dictionary = world.conflicts.lessons.values()[0]
	world.advance_to_ms(int(lesson.due_ms) - 1)
	runner.assert_eq(_node(world, "player", "qi_guard").state, "unknown", "accepted but unfinished demonstration does not project premature mastery")
	world.advance_to_ms(int(lesson.due_ms))
	for id: String in ["sword", "qi_bolt", "qi_guard"]:
		var node: Dictionary = _node(world, "player", id)
		runner.assert_eq(node.state, "learned", "only original completed lesson projects the actual learned method: " + id)
		runner.assert_eq(node.sources[0].domain, "conflicts", "method source retains its original owning domain")
		runner.assert_eq(node.sources[0].id, lesson.id, "learned method references the original completed lesson identity")
		runner.assert_eq(node.sources[0].at_ms, lesson.finished_ms, "learned method uses the real completion time rather than query time")
		runner.assert_eq(node.sources[0].source, "chen_shouzhuo", "learned method names the actual original teacher")
		runner.assert_true(not bool(node.actions[0].enabled), "mastery alone does not authorize casting outside an actual conflict")
	runner.assert_true("手中尚无实际保管的可用木剑。" in _node(world, "player", "sword").missing, "actual weapon absence remains distinct from having learned the sword technique")
	runner.assert_eq(_node(world, "su_zhi", "qi_bolt").state, "unknown", "an unrelated nearby resident never inherits another pupil's completed lesson")
	var before: String = _canonical(world)
	var first: String = SnapshotValues.canonical_json(Queries.project(world, "player"))
	for _index: int in 4:
		runner.assert_eq(SnapshotValues.canonical_json(Queries.project(world, "player")), first, "reopening the graph preserves the exact same sourced view")
	runner.assert_eq(_canonical(world), before, "opening learned-method views never progresses, pays, syncs or rerolls any original process")
	world = _make(runner)
	runner.assert_true(world.conflicts.teach("chen_shouzhuo", "player").ok, "interrupted query comparison begins another actual original lesson")
	world.conflicts.cancel("player")
	world.advance_to_ms(60000)
	runner.assert_eq(_node(world, "player", "qi_guard").state, "unknown", "cancelled demonstration remains an unlearned original method after its abandoned deadline")


func _hearing_is_not_embodied_learning(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	if world == null:
		return
	runner.assert_true(world.artifacts.request_check("player", "chen_shouzhuo", "study", "hearth_stone").ok, "actual experienced person agrees to examine and explain the original stone")
	world.advance_to_ms(240000)
	var reported: Dictionary = _node(world, "player", "stone_channeling")
	runner.assert_eq(reported.state, "reported", "a personally received method explanation is reported knowledge rather than embodied mastery")
	runner.assert_eq(reported.sources[0].kind, "reported", "reported source is typed distinctly from personally completed study")
	runner.assert_eq(reported.sources[0].source, "chen_shouzhuo", "the explanation preserves the actual original speaker")
	runner.assert_eq(_node(world, "su_zhi", "stone_channeling").state, "unknown", "someone else's privately received explanation is not a local shared knowledge pool")
	runner.assert_true(world.artifacts.begin("player", "study", "hearth_stone").ok, "actual recipient must still perform the original bodily study")
	world.advance_to_ms(world.elapsed_ms + 240000 - 1)
	runner.assert_eq(_node(world, "player", "stone_channeling").state, "reported", "querying one millisecond before actual study completion cannot grant the foundation")
	world.advance_to_ms(world.elapsed_ms + 1)
	var learned: Dictionary = _node(world, "player", "stone_channeling")
	runner.assert_eq(learned.state, "learned", "real personally completed original study supplies the foundation")
	var has_personal: bool = false
	for source: Dictionary in learned.sources:
		if source.kind == "artifact_event" and source.actor == "player" and source.object == "hearth_stone":
			has_personal = true
			runner.assert_eq(source.at_ms, world.elapsed_ms, "foundation source carries the original actual study completion time")
	runner.assert_true(has_personal, "learned foundation exposes an exact original object and personal event reference")


func _private_versions_and_written_steps(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	if world == null:
		return
	var record: String = _fixtures._write(runner, world)
	var method: String = str(world.method_records.objects[record].method)
	var other: Dictionary = world.heat_methods.compose("chen_shouzhuo", "hearth_stone", "未传的隐秘长火", 2, 2, method)
	runner.assert_true(other.ok, "original author creates an actual distinct private revision")
	var private_id: String = str(other.method)
	runner.assert_true(_node(world, "player", "heat_methods").instances.is_empty(), "visible other person's record never exposes their executable private version directory")
	runner.assert_true(world.method_records.begin("chen_shouzhuo", "place", record, "", "home/kitchen").ok, "actual author places the existing written carrier on a public work surface")
	world.advance_to_ms(world.elapsed_ms + 60000)
	runner.assert_true(world.method_records.begin("player", "take", record).ok, "novice actually takes custody of the original unique carrier")
	world.advance_to_ms(world.elapsed_ms + 60000)
	var held: Dictionary = _node(world, "player", "record_steps")
	runner.assert_eq(held.instances[0].state, "held_unread", "actual possession has its own state without supplying the unperformed reading")
	runner.assert_eq(held.instances[0].content_id, "", "unread custody does not reveal the hidden method identity")
	runner.assert_true(_node(world, "player", "heat_methods").instances.is_empty(), "holding unread steps does not project a known method version")
	runner.assert_true(world.method_records.begin("player", "read", record).ok, "novice undertakes actual original reading labor")
	world.advance_to_ms(world.elapsed_ms + 60000 - 1)
	runner.assert_true(_node(world, "player", "heat_methods").instances.is_empty(), "unfinished reading still exposes no exact private method version")
	world.advance_to_ms(world.elapsed_ms + 1)
	var versions: Dictionary = _node(world, "player", "heat_methods")
	runner.assert_eq(versions.instances.size(), 1, "only the single actually read original immutable version is projected")
	runner.assert_eq(versions.instances[0].content_id, method, "read method identity is tied to the exact original record")
	runner.assert_eq(versions.instances[0].state, "read", "reading is not counted as successful embodied trial")
	runner.assert_true(not str(versions).contains(private_id) and not str(versions).contains("未传的隐秘长火"), "reading one record cannot expose the author's later private revision or its title")
	runner.assert_eq(_node(world, "player", "stone_channeling").state, "unknown", "textual reading alone does not award original stone-channeling foundation")
	var read: Dictionary = _node(world, "player", "record_steps")
	runner.assert_eq(read.instances[0].sources[0].domain, "method_records", "actual reading exposes the original evidence owner")
	runner.assert_eq(read.instances[0].sources[0].object, record, "reading evidence retains the unique actual physical carrier")
	runner.assert_true(world.artifacts.begin("player", "study", "hearth_stone").ok, "reader really learns the original interface before a version can be tested")
	world.advance_to_ms(world.elapsed_ms + 240000)
	runner.assert_true(world.heat_methods.start("player", "hearth_stone", method, "record").ok, "reader with actual foundation starts the original source-backed version trial")
	world.advance_to_ms(world.elapsed_ms + 60000)
	versions = _node(world, "player", "heat_methods")
	runner.assert_eq(versions.instances[0].state, "learned", "only real successful stored heat promotes that exact original version to practiced")
	var found: bool = false
	for source: Dictionary in versions.instances[0].sources:
		found = found or source.kind == "artifact_event" and source.object == "hearth_stone"
	runner.assert_true(found, "practiced version keeps the actual artifact output evidence distinct from its reading source")
	var before: String = _canonical(world)
	for actor: String in ["player", "chen_shouzhuo", "su_zhi"]:
		Queries.project(world, actor)
	runner.assert_eq(_canonical(world), before, "viewing each person's own versions and reading does not grant anybody else knowledge or mutate the simulation")


func _real_mobile_practice(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	if world == null:
		return
	var mobile: Dictionary = _node(world, "player", "mobile_guard")
	runner.assert_eq(mobile.state, "conditions_missing", "opening personal view cannot sell a use whose original guard prerequisite was never learned")
	runner.assert_true(not mobile.actions[0].enabled and mobile.sources.is_empty(), "missing foundation leaves practice disabled without invented proof")
	var answer: Dictionary = world.conflicts.teach("chen_shouzhuo", "player")
	runner.assert_true(answer.ok, "mobile projection scenario starts the original willing paired lesson")
	if not answer.ok:
		return
	var lesson: Dictionary = world.conflicts.lessons.values()[0]
	runner.assert_true(world.advance_to_ms(int(lesson.due_ms)), "original personal guard demonstration actually finishes")
	mobile = _node(world, "player", "mobile_guard")
	runner.assert_eq(mobile.state, "can_practice", "completed original prerequisite permits a real future practice without counting as its completion")
	runner.assert_true(mobile.actions[0].enabled and mobile.sources.is_empty(), "readiness enables only the original domain action and supplies no learned record")
	var before: String = _canonical(world)
	for _index: int in 3:
		_node(world, "player", "mobile_guard")
	runner.assert_eq(_canonical(world), before, "browsing practice readiness cannot pay costs, roll a route, advance time or learn the use")
	answer = world.capability_practice.begin("player", "mobile_guard")
	runner.assert_true(answer.ok, "prepared original person really commits to the paid body process")
	if not answer.ok:
		return
	var cancelled_id: String = str(answer.id)
	mobile = _node(world, "player", "mobile_guard")
	runner.assert_eq(mobile.state, "practicing", "accepted original practice projects only its unfinished process")
	runner.assert_true(mobile.sources.is_empty() and mobile.actions[0].verb == "cancel_practice", "unfinished stages grant no learned proof and expose the actual cancellation action")
	var due: int = int(world.capability_practice.active.player.complete_ms)
	runner.assert_true(world.advance_to_ms(int(world.capability_practice.active.player.started_ms) + 15000), "original process really starts its physical walking stage")
	before = _canonical(world)
	_node(world, "player", "mobile_guard")
	runner.assert_eq(_canonical(world), before, "inspecting actual walking neither projects motion into the body nor settles a stage")
	runner.assert_true(world.capability_practice.cancel("player"), "original unfinished process is explicitly interrupted")
	runner.assert_eq(world.capability_practice.records[cancelled_id].status, "cancelled", "cancelled practice remains an actual terminal paid record")
	mobile = _node(world, "player", "mobile_guard")
	runner.assert_true(mobile.state != "learned" and mobile.sources.is_empty(), "interruption cannot masquerade as a completed learned source")
	runner.assert_true(world.advance_to_ms(due), "world passes the original abandoned practice deadline")
	runner.assert_true(_node(world, "player", "mobile_guard").state != "learned", "waiting past an abandoned deadline never supplies retroactive mastery")
	answer = world.capability_practice.begin("player", "mobile_guard")
	runner.assert_true(answer.ok, "same person can choose a separate real retry with its own original cost and route")
	if not answer.ok:
		return
	var completed_id: String = str(answer.id)
	due = int(world.capability_practice.active.player.complete_ms)
	runner.assert_true(world.advance_to_ms(due - 1), "real retry reaches one millisecond before its final bodily stage completes")
	runner.assert_eq(_node(world, "player", "mobile_guard").state, "practicing", "last unfinished millisecond still has no completed learned source")
	runner.assert_true(world.advance_to_ms(due), "all original paid walking and settling stages actually finish")
	mobile = _node(world, "player", "mobile_guard")
	runner.assert_eq(mobile.state, "learned", "only original successful completed practice projects the new learned use")
	runner.assert_eq(mobile.sources.size(), 1, "cancelled and completed records are never collapsed into two mastery sources")
	var proof: Dictionary = mobile.sources[0]
	runner.assert_true(proof.kind == "practice" and proof.domain == "capability_practice", "new use identifies the actual original practice authority")
	runner.assert_eq(proof.id, completed_id, "new use cites its exact successful process rather than the failed earlier attempt")
	runner.assert_eq(proof.at_ms, due, "new use carries its actual completed stage time")
	runner.assert_true(_node(world, "chen_shouzhuo", "mobile_guard").state != "learned", "a knowledgeable teacher never inherits the pupil's separately completed walking use")
	before = _canonical(world)
	var repeat: Dictionary = _node(world, "player", "mobile_guard")
	repeat.sources[0].id = "invented"
	runner.assert_eq(_node(world, "player", "mobile_guard").sources[0].id, completed_id, "editing a returned graph cannot alter the original successful practice identity")
	runner.assert_eq(_canonical(world), before, "reading completed practice changes no original proof, resource or motion state")
