extends RefCounted
## The live environmental view may cache ground stock only while its original
## inventory owner confirms that every ground write has been accounted for.

const Services = preload("res://scripts/sim/services/settlement_services.gd")
const LifecycleFixture = preload("res://tests/sim/test_object_lifecycle.gd")

var _fixture := LifecycleFixture.new()


func run(runner: Object) -> void:
	_ledger_epoch(runner)
	_artifact_generation(runner)
	_direct_transfer_guards(runner)
	print("SCENARIO ground inventory epoch: actual writes, idempotent retries, restore and cross-domain bypass guards")


func _ledger_epoch(runner: Object) -> void:
	var inventory := SimInventory.new()
	runner.assert_eq(inventory.ground_revision, 0, "a fresh inventory starts with a zero runtime ground epoch")
	runner.assert_true(inventory.create_container("store", {"wood": 10}) and inventory.create_container("bag", {}), "ordinary containers can be created")
	runner.assert_true(inventory.transfer("ordinary_move", "store", "bag", "wood", 2), "ordinary inventory transfer works")
	runner.assert_true(inventory.consume("ordinary_consume", "bag", "wood", 1), "ordinary consumption works")
	runner.assert_eq(inventory.ground_revision, 0, "ordinary changes do not invalidate ground sources")
	runner.assert_true(inventory.create_container("ground:pile", {}), "ground container can be created")
	runner.assert_eq(inventory.ground_revision, 1, "creating a ground container advances the epoch")
	runner.assert_true(not inventory.create_container("ground:pile", {}), "duplicate ground creation is rejected")
	runner.assert_eq(inventory.ground_revision, 1, "rejected creation leaves the epoch unchanged")
	runner.assert_true(inventory.transfer("pile_fill", "store", "ground:pile", "wood", 4), "ground stock comes from the real store")
	runner.assert_eq(inventory.ground_revision, 2, "a real transfer involving ground advances once")
	runner.assert_true(inventory.transfer("pile_fill", "store", "ground:pile", "wood", 4), "identical historical transfer replays")
	runner.assert_eq(inventory.ground_revision, 2, "a replay cannot manufacture an extra ground epoch")
	runner.assert_true(not inventory.transfer("impossible", "ground:pile", "store", "wood", 99), "an insufficient transfer is refused")
	runner.assert_eq(inventory.ground_revision, 2, "failed transfer leaves the epoch unchanged")
	runner.assert_true(inventory.reserve("ground_reservation", "ground:pile", "wood", 1, "player"), "ground material can be reserved")
	inventory.release("ground_reservation")
	runner.assert_eq(inventory.ground_revision, 2, "reservation alone does not change source quantity")
	runner.assert_true(inventory.consume("pile_consume", "ground:pile", "wood", 1), "a direct ledger consumer changes ground quantity")
	runner.assert_eq(inventory.ground_revision, 3, "direct consumption is observable to the cache")
	runner.assert_true(inventory.consume("pile_consume", "ground:pile", "wood", 1), "ground consumption receipt replays")
	runner.assert_eq(inventory.ground_revision, 3, "consumption replay does not advance the epoch")
	runner.assert_true(inventory.transform("pile_transform", "ground:pile", {"wood": 1}, {"ash": 1}), "a direct transform changes original ground stock")
	runner.assert_eq(inventory.ground_revision, 4, "direct transform also advances the ground epoch")
	runner.assert_true(inventory.transform("pile_transform", "ground:pile", {"wood": 1}, {"ash": 1}), "transform receipt replays")
	runner.assert_eq(inventory.ground_revision, 4, "transform replay does not advance the epoch")
	var saved: Dictionary = inventory.to_dict()
	runner.assert_true(not saved.has("ground_revision"), "the ground epoch is derived runtime state and does not alter the save schema")
	runner.assert_true(not inventory.restore({}), "invalid same-instance restoration is rejected")
	runner.assert_eq(inventory.ground_revision, 4, "rejected restoration does not change the epoch")
	runner.assert_eq(inventory.to_dict(), saved, "rejected restoration does not change original stock or receipts")
	runner.assert_true(inventory.restore(saved), "validated same-instance restoration succeeds")
	runner.assert_eq(inventory.ground_revision, 5, "same-instance restoration invalidates previous ground readers")
	runner.assert_true(inventory.restore(saved), "the same validated snapshot can be restored again")
	runner.assert_eq(inventory.ground_revision, 6, "even equal restored contents receive a new runtime epoch")

	# Refuse impossible epoch overflow without breaking an existing receipt.
	var snapshot: Dictionary = inventory.to_dict()
	inventory.ground_revision = SimInventory.MAX_COUNT
	runner.assert_true(not inventory.create_container("ground:overflow", {}), "ground creation cannot wrap its epoch")
	runner.assert_true(not inventory.transfer("overflow_move", "ground:pile", "store", "wood", 1), "new ground transfer is refused at epoch capacity")
	runner.assert_true(not inventory.consume("overflow_consume", "ground:pile", "wood", 1), "new ground consumption is refused at epoch capacity")
	runner.assert_true(not inventory.transform("overflow_transform", "ground:pile", {"wood": 1}, {"ash": 1}), "new ground transform is refused at epoch capacity")
	runner.assert_true(not inventory.restore(saved), "restore cannot reuse a saturated epoch")
	runner.assert_eq(inventory.to_dict(), snapshot, "all epoch-capacity failures leave actual stock and receipts unchanged")
	runner.assert_true(inventory.transfer("pile_fill", "store", "ground:pile", "wood", 4), "prior ground transfer remains replayable at capacity")
	runner.assert_true(inventory.transfer("ordinary_after_capacity", "store", "bag", "wood", 1), "unrelated non-ground operations remain usable")


func _artifact_generation(runner: Object) -> void:
	var world: RegionalSimulation = _fixture._world(runner)
	if world == null:
		return
	var artifacts: SimArtifacts = world.artifacts
	var saved: Dictionary = artifacts.to_dict()
	var original: int = artifacts.state_generation
	runner.assert_true(original > 0, "initialized original artifact owner has a runtime generation")
	runner.assert_true(not saved.has("state_generation"), "artifact generation is absent from the existing save schema")
	runner.assert_true(not artifacts.restore({}), "malformed artifact restore is rejected")
	runner.assert_eq(artifacts.state_generation, original, "failed artifact restore does not change generation")
	runner.assert_eq(artifacts.to_dict(), saved, "failed artifact restore leaves original object state unchanged")
	runner.assert_true(artifacts.restore(saved), "validated artifacts may be restored on the same owner")
	runner.assert_eq(artifacts.state_generation, original + 1, "same-owner artifact restore invalidates cached projections")
	var definitions: Dictionary = artifacts.definitions.duplicate(true)
	runner.assert_true(artifacts.initialize(world, definitions), "a valid same-owner initialization remains supported")
	runner.assert_eq(artifacts.state_generation, original + 2, "same-owner definitions replacement changes generation")
	var detached := SimArtifacts.new()
	runner.assert_true(detached.initialize(world, definitions), "a fresh artifact owner can bind its definitions")
	var before_opening: int = detached.state_generation
	runner.assert_true(detached.spawn_opening({"version": 1, "objects": [], "experiences": {}}), "a validated empty opening is accepted")
	runner.assert_eq(detached.state_generation, before_opening + 1, "whole-opening object replacement changes generation")
	artifacts.state_generation = SimInventory.MAX_COUNT
	runner.assert_true(not artifacts.restore(saved), "artifact restore cannot wrap its generation")
	runner.assert_true(not artifacts.initialize(world, definitions), "artifact initialization cannot wrap its generation")
	runner.assert_eq(artifacts.to_dict(), saved, "generation-capacity refusal leaves object state unchanged")


func _direct_transfer_guards(runner: Object) -> void:
	var world: RegionalSimulation = _fixture._world(runner)
	if world == null:
		return
	var inventory: SimInventory = world.regions.home.inventory
	var placement: Dictionary = world.object_lifecycle.execute(_fixture._transfer("epoch_pile", _fixture._location("store"), _fixture._ground(120, 120), "wood", 2))
	runner.assert_true(bool(placement.get("ok", false)), "real lifecycle places a ground stock pile")
	if not bool(placement.get("ok", false)):
		return
	var ground: String = str(placement.to.container)
	var original: Dictionary = inventory.to_dict()
	var epoch: int = inventory.ground_revision
	var service: SettlementServices = Services.new()
	service.bind_world(world)
	runner.assert_true(not service.transfer("service_from_ground", "home", ground, "home", "store", "wood", 1), "settlement service cannot directly withdraw from a ground pile")
	runner.assert_true(not service.transfer("service_to_ground", "home", "store", "home", ground, "wood", 1), "settlement service cannot directly deposit into a ground pile")
	runner.assert_true(not world._move_goods("route_from_ground", inventory, ground, inventory, "store", "wood", 1, "home", "home"), "regional route helper cannot bypass ground placement ownership")
	runner.assert_true(not world._move_goods("route_to_ground", inventory, "store", inventory, ground, "wood", 1, "home", "home"), "regional route helper cannot write into a ground pile")
	var avian := SimAvianLife.new()
	runner.assert_true(not avian._exchange("bird_from_ground", inventory, ground, inventory, "store", "wood", 1, "home", "home"), "avian exchange cannot directly withdraw from a ground pile")
	runner.assert_true(not avian._exchange("bird_to_ground", inventory, "store", inventory, ground, "wood", 1, "home", "home"), "avian exchange cannot directly add to a ground pile")
	runner.assert_eq(inventory.to_dict(), original, "rejected bypasses preserve stock, reservations and receipts")
	runner.assert_eq(inventory.ground_revision, epoch, "rejected bypasses do not change the ground epoch")
	runner.assert_true(service.operations.is_empty() and avian.exchanges.is_empty(), "rejected bypasses do not create unrelated receipts")
	var signature: Dictionary = {"from": "home", "source": ground, "to": "home", "target": "store", "item": "wood", "amount": 1}
	service.operations["service_legacy"] = signature.duplicate(true)
	world.operations["route_legacy"] = signature.duplicate(true)
	avian.exchanges["avian_legacy"] = signature.duplicate(true)
	runner.assert_true(service.transfer("service_legacy", "home", ground, "home", "store", "wood", 1), "an already committed historical service receipt still replays")
	runner.assert_true(world._move_goods("route_legacy", inventory, ground, inventory, "store", "wood", 1, "home", "home"), "an already committed historical route receipt still replays")
	runner.assert_true(avian._exchange("avian_legacy", inventory, ground, inventory, "store", "wood", 1, "home", "home"), "an already committed historical avian receipt still replays")
	runner.assert_eq(inventory.to_dict(), original, "historical receipt replay performs no new ground writes")
	runner.assert_eq(inventory.ground_revision, epoch, "historical replay keeps the same epoch")
