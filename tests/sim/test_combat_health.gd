extends RefCounted
## Contract-level consequences over committed conflict hits. The conflict
## authority, not this health API or its UI, proves how each impact occurred.

const Health = preload("res://scripts/sim/health.gd")
const RULES: String = "res://data/definitions/health.json"


class EmbodimentStub extends RefCounted:
	func carrier_for_source(kind: String, id: String) -> String:
		return "body:" + id if kind == "village_actor" and id in ["player", "su_zhi"] else ""


class ArtifactStub extends RefCounted:
	var next_id: int = 1
	var events: Array[Dictionary] = []


class ConflictStub extends RefCounted:
	var next_hit_id: int = 1
	var sources: Dictionary = {}


	func wound_sources() -> Dictionary:
		return sources.duplicate(true)


	func owns_actor(_id: String) -> bool:
		return false


class RegionStub extends RefCounted:
	var actors: Dictionary = {
		"player": {"definition_id": "player", "alive": true, "active": {}, "autonomous": false, "position": [64.0, 64.0], "qi": 20, "stamina": 100},
		"su_zhi": {"definition_id": "su_zhi", "alive": true, "active": {}, "autonomous": true, "position": [64.0, 64.0], "qi": 20, "stamina": 100},
	}
	var config: Dictionary = {"decision_interval": 1}
	var inventory: SimInventory = SimInventory.new()
	func has_actor(id: Variant) -> bool:
		return actors.has(id)
	func actor_state(id: String) -> Dictionary:
		return actors.get(id, {})
	func synchronize_actor(id: String) -> Dictionary:
		return actor_state(id)


class WorldStub extends RefCounted:
	var elapsed_ms: int = 0
	var target_ms: int = 0
	var regions: Dictionary = {"home": RegionStub.new()}
	var artifacts: RefCounted = ArtifactStub.new()
	var conflicts: RefCounted = ConflictStub.new()
	var embodiment: RefCounted = EmbodimentStub.new()
	var resting: RefCounted
	var services: RefCounted
	var invalidated: Array[String] = []


	func _sorted_keys(data: Dictionary) -> Array:
		var keys: Array = data.keys()
		keys.sort()
		return keys


	func invalidate_region(id: String) -> void:
		invalidated.append(id)


	func synchronize_region(_id: String) -> void:
		pass


	func native_action_allowed(_id: String) -> bool:
		return true


	func actor_controls(_id: String, _channel: String) -> bool:
		return true


	func autonomous_decision(_id: String) -> bool:
		return false


func run(runner: Object) -> void:
	_sourced_impacts(runner)
	_recovery_and_continuation(runner)
	_specific_consequences(runner)
	_candidates_and_legacy(runner)
	print("SCENARIO combat consequences: committed impacts, gradual burden and retreat, original meridian care, typed recovery, legacy activation and atomic candidate rejection")


func _fixture(runner: Object) -> Dictionary:
	var world := WorldStub.new()
	var health := Health.new()
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RULES))
	runner.assert_true(health.initialize(world, rules), "actual health content supports specific combat consequences")
	return {"world": world, "health": health}


func _commit(fixture: Dictionary, impact: int = 12, actor: String = "player") -> String:
	var world: WorldStub = fixture.world
	var id: String = "conflict:hit:%d" % int(world.conflicts.next_hit_id)
	world.conflicts.next_hit_id += 1
	world.conflicts.sources[id] = {"id": id, "actor": actor, "region": "home", "type": "contusion", "at_ms": world.elapsed_ms, "impact": impact}
	return id


func _step(fixture: Dictionary, now: int) -> void:
	fixture.world.elapsed_ms = now
	fixture.world.target_ms = now
	fixture.health.settle_at_ms(now)


func _state(health: RefCounted) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(health.to_dict()))


func _sourced_impacts(runner: Object) -> void:
	var fixture: Dictionary = _fixture(runner)
	var health: RefCounted = fixture.health
	var world: WorldStub = fixture.world
	var original: String = _state(health)
	runner.assert_true(not health.record_conflict_effect("conflict:hit:999"), "uncommitted text or arbitrary source IDs create no wound")
	runner.assert_eq(_state(health), original, "rejected invented impact changes no injury state")
	var source: String = _commit(fixture)
	runner.assert_true(health.record_conflict_effect(source), "committed current conflict impact creates its specific injury")
	runner.assert_eq(health.combat_burden("player"), 12, "actual impact starts a bounded recoverable physical burden")
	runner.assert_true(health.can_fight("player"), "one modest impact does not impose blanket incapacitation")
	runner.assert_eq(health.wounds[source].remaining, 72, "actual content determines recovery work per impact")
	var once: String = _state(health)
	runner.assert_true(not health.record_conflict_effect(source), "repeated commit cannot multiply the same impact")
	runner.assert_eq(_state(health), once, "duplicate delivery preserves the original injury and history")
	var next: String = _commit(fixture)
	runner.assert_true(health.record_conflict_effect(next), "a different committed impact has its own persistent consequence")
	runner.assert_eq(health.combat_burden("player"), 24, "two actual impacts accumulate without a second HP pool")
	runner.assert_true(not health.can_fight("player"), "explicit nonlethal encounter can stop at the defined retreat burden")
	runner.assert_eq(world.regions.home.actors.player.qi, 20, "injury recording never creates or spends a second qi value")
	runner.assert_eq(world.regions.home.actors.player.stamina, 100, "injury domain does not duplicate the actor's action costs")
	runner.assert_true(world.regions.home.actors.player.alive, "recoverable contusion does not misuse the death flag")
	runner.assert_true(not health.can_fight("unregistered"), "unknown bodies cannot gain eligibility by having no wounds")
	world.regions.home.actors.player.alive = false
	runner.assert_true(not health.can_fight("player"), "a genuinely dead body cannot fight through the burden check")
	world.regions.home.actors.player.alive = true
	var early: String = _commit(fixture)
	world.elapsed_ms = 1
	runner.assert_true(not health.record_conflict_effect(early), "late callbacks cannot backfill an unrecorded past hit")
	runner.assert_true(health.describe("player").contains("退开休养"), "affected body receives a qualitative retreat consequence")


func _recovery_and_continuation(runner: Object) -> void:
	var fixture: Dictionary = _fixture(runner)
	var health: RefCounted = fixture.health
	var world: WorldStub = fixture.world
	world.elapsed_ms = 100
	world.target_ms = 100
	var source: String = _commit(fixture)
	health.record_conflict_effect(source)
	_step(fixture, 60000)
	runner.assert_eq(health.wounds[source].remaining, 72, "partial minute before a full exposure interval does not heal")
	_step(fixture, 120000)
	runner.assert_eq(health.wounds[source].remaining, 71, "a complete ordinary minute advances specific injury recovery")
	_step(fixture, 120000)
	runner.assert_eq(health.wounds[source].remaining, 71, "repeated settlement at one boundary never repeats healing")
	var saved: Dictionary = JSON.parse_string(_state(health))
	var resumed := Health.new()
	runner.assert_true(resumed.initialize(world, health.definitions) and resumed.restore(saved), "a real partial recovery JSON record restores against committed sources")
	world.regions.home.actors.player.active = {"action": "rest", "phase": "work", "segment_started_ms": 120000}
	for now: int in range(180000, 1620000 + 1, 60000):
		world.elapsed_ms = now
		world.target_ms = now
		health.settle_at_ms(now)
		resumed.settle_at_ms(now)
	runner.assert_eq(_state(health), _state(resumed), "continued recovery and JSON-resumed recovery produce the exact same history")
	runner.assert_eq(health.combat_burden("player"), 0, "time with actual rest resolves the physical burden")
	runner.assert_true(health.can_fight("player"), "recovery permits later fighting without reloading to reset health")
	runner.assert_true(health.source_of_type("player", "contusion").is_empty(), "resolved injury is no longer an active effect")
	runner.assert_true(int(health.wounds[source].recovered_ms) > 0 and not health.wounds[source].recovery.is_empty(), "resolution retains the actual injury provenance and spent recovery time")
	runner.assert_true(resumed.restore(health.to_dict()), "fully recovered source remains a valid candidate with its history")


func _specific_consequences(runner: Object) -> void:
	var fixture: Dictionary = _fixture(runner)
	var health: RefCounted = fixture.health
	var world: WorldStub = fixture.world
	var source: String = _commit(fixture)
	health.record_conflict_effect(source)
	runner.assert_true(not health.blocks_channeling("player"), "a blunt contusion does not pretend to be meridian damage")
	runner.assert_eq(health.current_source("player"), "", "existing meridian care queries do not select a new unrelated wound")
	runner.assert_true(not health.wants_decision("player", 0), "contusion does not automatically solicit the old meridian medicine")
	runner.assert_true(not health.request("player", "su_zhi", "diagnose").ok, "old herbal meridian experience is not universal medical expertise")
	var stone: Dictionary = {"id": "artifact:event:1", "actor": "player", "region": "home", "kind": "backlash", "at_ms": 0}
	world.artifacts.events.append(stone)
	world.artifacts.next_id = 2
	health.record_effect(stone)
	runner.assert_eq(health.current_source("player"), "artifact:event:1", "original committed stone effect still owns meridian care")
	runner.assert_true(health.blocks_channeling("player"), "actual meridian damage still blocks channeling")
	runner.assert_eq(health.combat_burden("player"), 12, "meridian consequence is not converted into a second blunt hit")
	runner.assert_true(health.describe("player").contains("灼涩") and health.describe("player").contains("碰撞"), "both concrete effects remain visible to the affected person")
	runner.assert_true(health.restore(health.to_dict()), "both original stone and conflict consequences validate together")


func _candidates_and_legacy(runner: Object) -> void:
	var fixture: Dictionary = _fixture(runner)
	var health: RefCounted = fixture.health
	var world: WorldStub = fixture.world
	var original: Dictionary = {"version": 1, "source_floor": 1, "next_id": 1, "wounds": {}, "jobs": {}}
	var old: String = JSON.stringify(original)
	var migrated: Dictionary = Health.upgrade_legacy(original)
	runner.assert_eq(JSON.stringify(original), old, "legacy upgrade leaves the caller's archive unchanged")
	runner.assert_eq(migrated.version, 2, "legacy health has an explicit new consequence format")
	runner.assert_eq(migrated.conflict_source_floor, 1, "new conflict era starts before its first source, without backfilled wounds")
	runner.assert_true(health.restore(original), "original empty pre-combat health still restores directly")
	var source: String = _commit(fixture)
	health.record_conflict_effect(source)
	var stable: String = _state(health)
	for kind: String in ["missing", "impact", "actor", "source_time", "remaining", "treated", "type", "skip_source", "early_recovery"]:
		var broken: Dictionary = JSON.parse_string(stable)
		match kind:
			"missing": broken.wounds.erase(source)
			"impact": broken.wounds[source].impact = 11
			"actor": broken.wounds[source].actor = "su_zhi"
			"source_time": broken.wounds[source].at_ms = 1
			"remaining": broken.wounds[source].remaining = 71
			"treated": broken.wounds[source].treated_ms = 0
			"type": broken.wounds[source].type = "meridian_irritation"
			"skip_source": broken.conflict_source_floor = 2; broken.wounds.clear()
			"early_recovery": broken.wounds[source].recovery = [{"at_ms": 0, "resting": false, "treated": false, "amount": 1}]
		runner.assert_true(not health.restore(broken), "candidate rejects unsupported combat consequence: " + kind)
		runner.assert_eq(_state(health), stable, "failed consequence restore leaves the live state unchanged: " + kind)
	world.conflicts.sources[source].impact = 0
	runner.assert_true(not health.restore(JSON.parse_string(stable)), "a malformed source cannot authorize a seemingly valid wound")
	world.conflicts.sources[source].impact = 12
	runner.assert_true(health.restore(JSON.parse_string(stable)), "original valid consequence remains loadable after rejected candidates")
