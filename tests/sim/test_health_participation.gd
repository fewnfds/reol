extends RefCounted
## The same participant mechanism must follow real owner commits, retain
## historical facts, and rebuild from the validated current world.

const CombatFixture = preload("res://tests/sim/test_combat_health.gd")
const HealthFixture = preload("res://tests/sim/test_health.gd")
const Health = preload("res://scripts/sim/health.gd")


func run(runner: Object) -> void:
	_wound_membership_and_restore(runner)
	_care_lifecycle_and_restore(runner)
	print("SCENARIO health participation: real consequences and care register, finish, cancel and rebuild without treating history as active work")


func _wound_membership_and_restore(runner: Object) -> void:
	var helper := CombatFixture.new()
	var fixture: Dictionary = helper._fixture(runner)
	var health: RefCounted = fixture.health
	var world: RefCounted = fixture.world
	for unused: int in 12:
		var id: String = helper._commit(fixture, 1)
		runner.assert_true(health.record_conflict_effect(id), "only committed original impacts register recovery work")
	runner.assert_eq(health.participation_summary().active_wounds, 12, "all unresolved impacts participate")
	runner.assert_eq(health.source_of_type("player", "contusion"), "conflict:hit:1", "actor-specific lookup keeps the original lexical source choice")
	runner.assert_eq(health.next_boundary_ms(), 60000, "unresolved recovery keeps the original next-minute boundary")
	for minute: int in range(1, 7):
		helper._step(fixture, minute * 60000)
	runner.assert_eq(health.participation_summary().active_wounds, 0, "resolved effects leave the active set")
	runner.assert_eq(health.wounds.size(), 12, "resolved impacts remain real historical facts")
	runner.assert_true(health.source_of_type("player", "contusion").is_empty(), "history alone does not act as an unresolved consequence")
	runner.assert_eq(health.next_boundary_ms(), SimInventory.MAX_COUNT, "resolved history schedules no health work")
	var player_id: String = helper._commit(fixture, 1, "player")
	var other_id: String = helper._commit(fixture, 1, "su_zhi")
	runner.assert_true(health.record_conflict_effect(player_id) and health.record_conflict_effect(other_id), "new commits enter the same mechanism after history accumulates")
	runner.assert_eq(health.participation_summary().active_wounds, 2, "only new unresolved effects re-enter")
	runner.assert_eq(health.source_of_type("player", "contusion"), player_id, "player query sees only that actor's active consequence")
	runner.assert_eq(health.source_of_type("su_zhi", "contusion"), other_id, "a second actor has a separate active candidate set")
	var saved: Dictionary = JSON.parse_string(helper._state(health))
	var restored := Health.new()
	runner.assert_true(restored.initialize(world, health.definitions) and restored.restore(saved), "validated restore rebuilds from original consequences")
	runner.assert_eq(restored.participation_summary().active_wounds, 2, "restore excludes resolved history from active work")
	runner.assert_eq(restored.source_of_type("su_zhi", "contusion"), other_id, "actor membership is rebuilt on restore")
	var invalid: Dictionary = saved.duplicate(true)
	invalid.wounds[other_id].actor = "nobody"
	runner.assert_true(not restored.restore(invalid), "bad original state is rejected")
	runner.assert_eq(restored.participation_summary().active_wounds, 2, "rejected restore leaves the live derived participants intact")


func _care_lifecycle_and_restore(runner: Object) -> void:
	var helper := HealthFixture.new()
	var world: RegionalSimulation = helper._injured(runner)
	if world == null:
		return
	helper._doctor(world)
	var started: Dictionary = world.health.request("player", "su_zhi", "diagnose")
	runner.assert_true(started.ok, "actual care registers a job")
	if not started.ok:
		return
	var id: String = str(started.id)
	var due_ms: int = int(world.health.jobs[id].due_ms)
	runner.assert_eq(world.health.participation_summary().active_care, 1, "started care is active work")
	runner.assert_eq(world.health.participation_summary().care_candidates, 1, "an untreated actual consequence can solicit care")
	runner.assert_true(world.health.owns_actor("player") and world.health.owns_actor("su_zhi"), "both original participants remain occupied")
	var saved: Dictionary = JSON.parse_string(helper._state(world))
	var resumed: RegionalSimulation = helper._world(runner)
	runner.assert_true(resumed.restore(saved), "ordinary world restores the in-progress care")
	runner.assert_eq(resumed.health.participation_summary().active_care, 1, "in-progress care membership is rebuilt")
	runner.assert_true(resumed.health.owns_actor("player") and resumed.health.owns_actor("su_zhi"), "restored actor membership preserves original ownership")
	runner.assert_true(resumed.health.cancel("su_zhi"), "either participant can cancel a restored job")
	runner.assert_eq(resumed.health.participation_summary().active_care, 0, "cancelled care leaves active work")
	runner.assert_true(not resumed.health.owns_actor("player") and not resumed.health.owns_actor("su_zhi"), "cancel releases both actor memberships")
	runner.assert_true(world.advance_to_ms(due_ms), "original world reaches the actual completion boundary")
	runner.assert_eq(world.health.jobs[id].status, "completed", "completion remains in the original job history")
	runner.assert_eq(world.health.participation_summary().active_care, 0, "completed care leaves active work")
	var inventory: SimInventory = world.regions.home.inventory
	runner.assert_true(inventory.transfer("test:care-material", "garden", "actor:player", "herb", 1), "actual inventory supplies the treatment material")
	var treatment: Dictionary = world.health.request("player", "su_zhi", "treat")
	runner.assert_true(treatment.ok, "diagnosis and real material allow treatment")
	if treatment.ok:
		runner.assert_true(world.advance_to_ms(int(world.health.jobs[treatment.id].due_ms)), "treatment completes at its real boundary")
		runner.assert_eq(world.health.participation_summary().care_candidates, 0, "completed treatment stops soliciting duplicate care")
		runner.assert_eq(world.health.participation_summary().active_wounds, 1, "a treated consequence still participates in gradual recovery")
