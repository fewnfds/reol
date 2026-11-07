extends RefCounted
## Actual original people seek a unique physical object, without a quest copy.

const Fixtures = preload("res://tests/sim/test_settlement_services.gd")
const Schema = preload("res://scripts/sim/field_opportunity_schema.gd")
const ACTOR: String = "river_shi_tou"
const SITE: String = "broken_stele"
const RING: String = "stele_drawing_ring"
const CENTERS: Dictionary = {"home": Vector2i(100, 100), "river": Vector2i(150, 100)}
var _fixtures := Fixtures.new()


class FieldMap extends WorldMapData:
	var cover: Dictionary = {}
	var levels: Dictionary = {}

	func get_terrain(cell: Vector2i) -> int:
		return TERRAIN_ROCK if cover.has(cell) else TERRAIN_GRASS if in_bounds(cell) else -1

	func get_elevation(cell: Vector2i) -> int:
		return int(levels.get(cell, 0)) if in_bounds(cell) else -1

	func independent_copy() -> WorldMapData:
		var copy := FieldMap.new()
		copy.cover = cover.duplicate(true)
		copy.levels = levels.duplicate(true)
		return copy


func run(runner: Object) -> void:
	_definitions_and_single_origin(runner)
	_personal_clues_and_real_discovery(runner)
	_original_npc_and_actual_take(runner)
	_player_first_and_empty_observation(runner)
	_existing_action_and_interruption(runner)
	_inflight_and_sparse_future(runner)
	_reject_bad_candidates(runner)
	print("SCENARIO field opportunities: one reachable wild landmark, attributed clues and genuine discovery, original NPC travel and actual unique-object take, player-first empty-slot knowledge, native needs and body exclusion, fine/sparse and independent saved futures, atomic bad-candidate rejection")


func _world(runner: Object, autonomous: bool = false, opening: bool = true) -> RegionalSimulation:
	var world: RegionalSimulation = _fixtures._make_world(runner)
	if world == null: return null
	world.bind_map_data(FieldMap.new())
	if not world.artifacts.spawn_opening(JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/artifacts.json"))):
		runner.assert_true(false, "field fixture creates the original declared hearth object")
		return null
	# Isolate this purpose from the separate paid-livelihood scenario. Ordinary
	# untouched opening/NPC priorities are exercised by the runtime acceptance.
	world.autonomous_livelihood.plans.erase(ACTOR)
	world.regions.river.actors[ACTOR].autonomous = autonomous
	world.regions.river.actors[ACTOR].retry_ms = int(world.field_opportunities.definitions.purpose.delay_ms)
	if opening and not world.field_opportunities.spawn_opening(CENTERS):
		runner.assert_true(false, "field fixture installs one reachable real landmark and original ring")
		return null
	return world


func _canonical(world: RegionalSimulation) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(world.to_dict()))


func _site(world: RegionalSimulation) -> Vector2i:
	return SimRouteTravel.cell(world.field_opportunities.sites[SITE].cell)


func _put(world: RegionalSimulation, actor: String, cell: Vector2i) -> void:
	var region: String = world.field_opportunities.home(actor)
	world.regions[region].set_actor_cell(actor, cell)
	world.invalidate_region(region)


func _start(runner: Object, world: RegionalSimulation) -> bool:
	var delay: int = int(world.field_opportunities.definitions.purpose.delay_ms)
	runner.assert_true(world.advance_to_ms(delay), "original native retry reaches its scheduled personal decision")
	var started: bool = world.field_opportunities.owns_actor(ACTOR)
	runner.assert_true(started, "the original resident personally starts the bounded real route")
	return started


func _restored(runner: Object, world: RegionalSimulation, autonomous: bool = true) -> RegionalSimulation:
	var saved: String = _canonical(world)
	# Saved sites and original objects come from restore, not a second opening
	# search. Opening placement remains covered by the new-game cases below.
	var candidate: RegionalSimulation = _world(runner, autonomous, false)
	if candidate == null: return null
	candidate.bind_map_data(world.map_data.independent_copy())
	var accepted: bool = candidate.restore(JSON.parse_string(saved))
	runner.assert_true(accepted, "independent candidate restores the actual complete field world")
	if not accepted: return null
	runner.assert_eq(_canonical(candidate), saved, "JSON restore retains all original bodies, social sources and unfinished work")
	return candidate


func _definitions_and_single_origin(runner: Object) -> void:
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/field_opportunities.json"))
	runner.assert_true(SimFieldOpportunities.valid_definitions(rules), "bounded wild-site definitions are valid")
	for fault: String in ["extra", "boolean_radius", "free_retry", "missing_knower", "unknown_slot", "empty_budget", "free_sample"]:
		var bad: Dictionary = rules.duplicate(true)
		match fault:
			"extra": bad["holder"] = "player"
			"boolean_radius": bad.navigation_radius = true
			"free_retry": bad.purpose.retry_ms = 0
			"missing_knower": bad.opening_knowers = ["chen_shouzhuo"]
			"unknown_slot": bad.site.container = "records"
			"empty_budget": bad.max_trips = 0
			"free_sample": bad.observation_ms = 0
		runner.assert_true(not SimFieldOpportunities.valid_definitions(bad), "wild-site definition rejects " + fault)
	var world: RegionalSimulation = _world(runner)
	if world == null: return
	for boolean_value: bool in [false, true]:
		var empty: Dictionary = SimFieldOpportunities.empty_state()
		empty.next_observation_ms = boolean_value
		runner.assert_true(not Schema.validate(empty, world.field_opportunities), "empty field state rejects a boolean observation clock")
	runner.assert_eq(world.regions.size(), 2, "wild landmark creates no third Village or institutional inventory")
	runner.assert_true(world.field_opportunities.valid_slot("home", "site:broken_stele"), "one physical artifact slot exists at the site")
	runner.assert_true(not world.regions.home.inventory.containers.has("site:broken_stele"), "wild artifact slot is not a second stack inventory")
	for center: Vector2i in CENTERS.values():
		runner.assert_true(_site(world).distance_to(center) >= float(rules.site.minimum_separation), "landmark is genuinely outside both settlement centers")
	runner.assert_true(not world.field_opportunities._find_path(SimRouteTravel.cell(world.regions.river.actors[ACTOR].cell), _site(world)).is_empty(), "original distant resident has a real terrain route to the site")
	var before: String = _canonical(world)
	runner.assert_true(not world.field_opportunities.spawn_opening(CENTERS), "opening origin cannot be replayed to replenish a ring")
	runner.assert_eq(_canonical(world), before, "rejected repeated opening leaves every authority intact")
	runner.assert_true(world.field_opportunities.cross_valid(), "opening ring, individual testimony and site origins agree")
	var terrain: FieldMap = world.map_data as FieldMap
	terrain.cover[_site(world)] = true
	runner.assert_true(not Schema.validate(world.field_opportunities.to_dict(), world.field_opportunities), "candidate landmark cannot rest on impossible immutable rock terrain")
	terrain.cover.erase(_site(world))
	runner.assert_true(world.field_opportunities.cross_valid(), "restoring real terrain preserves the genuine opening")


func _personal_clues_and_real_discovery(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null: return
	var before: String = _canonical(world)
	runner.assert_true(world.field_opportunities.known_sites("player").is_empty(), "distant player receives no automatic location clue")
	runner.assert_true(world.field_opportunities.destination("player", SITE).is_empty(), "unknown world landmark is not a travel radar")
	world.field_opportunities.nearby_visible_sites("player")
	runner.assert_eq(_canonical(world), before, "querying visible or known places produces no memories or randomness")
	runner.assert_true(not world.field_opportunities.learn_from("player", ACTOR).ok, "remote known resident cannot transmit a clue through distance")
	_put(world, "player", SimRouteTravel.cell(world.regions.home.actors.chen_shouzhuo.cell))
	runner.assert_true(world.field_opportunities.learn_from("player", "chen_shouzhuo").ok, "actual idle knowledgeable resident can share his sourced old testimony")
	var source: String = str(world.field_opportunities.sites[SITE].source_events.chen_shouzhuo)
	var heard: Dictionary = world.services.social.knowledge.player[source]
	runner.assert_true(not bool(heard.direct) and heard.source == "chen_shouzhuo", "player's location memory preserves its named personal source")
	runner.assert_eq(world.field_opportunities.destination("player", SITE).cell, world.field_opportunities.sites[SITE].cell, "only actual heard clue authorizes the original location projection")
	runner.assert_true(world.field_opportunities.cross_valid(), "shared decision, geometry and attributed source restore consistently")
	var walker: RegionalSimulation = _world(runner)
	if walker == null: return
	_put(walker, "player", _site(walker) + Vector2i(2, 0))
	before = _canonical(walker)
	runner.assert_eq(walker.field_opportunities.nearby_visible_sites("player").size(), 1, "an unbriefed passer-by can genuinely see the landmark")
	runner.assert_eq(_canonical(walker), before, "nearby affordance browsing remains read-only")
	runner.assert_true(walker.advance_to_ms(int(walker.field_opportunities.definitions.observation_ms)), "shared deterministic perception boundary reaches the actual passer-by")
	runner.assert_eq(walker.field_opportunities.known_sites("player").size(), 1, "actual visit discovers the place without asking anyone or accepting a quest")
	var map: FieldMap = walker.map_data as FieldMap
	map.cover[_site(walker) + Vector2i(1, 0)] = true
	runner.assert_true(not walker.field_opportunities.observe_site("player", SITE).ok, "solid intervening terrain blocks a fresh direct inspection")
	map.cover.clear()
	map.levels[SimRouteTravel.cell(walker.regions.home.actors.player.cell)] = 1
	runner.assert_true(not walker.field_opportunities.observe_site("player", SITE).ok, "different height blocks direct field inspection")


func _original_npc_and_actual_take(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner, true)
	if world == null or not _start(runner, world): return
	var person: Dictionary = world.regions.river.actors[ACTOR]
	var origin: Array = person.position.duplicate()
	var qi: int = int(person.qi)
	var energy: float = float(person.energy)
	runner.assert_true(not bool(person.autonomous) and person.active.is_empty(), "field route owns the same original body without an additional native action")
	runner.assert_eq(world.artifacts.objects[RING].container, "site:broken_stele", "intention and departure do not award or duplicate the sought object")
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + 137), "original millisecond travel projects an unfinished physical segment")
	runner.assert_true(person.position != origin, "resident travels continuously through actual space while player is absent")
	runner.assert_true(float(person.energy) < energy and int(person.qi) == qi, "original work energy pays for travel without fabricated qi charges")
	var deadline: int = world.elapsed_ms + 180000
	while world.artifacts.objects[RING].container != "actor:" + ACTOR and world.elapsed_ms < deadline:
		if not world.advance_to_ms(mini(deadline, world.elapsed_ms + 2000)): break
	runner.assert_eq(world.artifacts.objects[RING].container, "actor:" + ACTOR, "resident's original artifact take moves the one same real ring")
	var actual: Dictionary = world.field_opportunities._artifact_result(str(world.field_opportunities.purposes[ACTOR].artifact_action))
	runner.assert_eq(actual.get("kind"), "taken", "successful search points to an actual completed artifact transaction")
	runner.assert_true(world.field_opportunities.known_sites("player").is_empty(), "absent observer never learns the NPC's private expedition or holder automatically")
	runner.assert_true(world.field_opportunities.cross_valid(), "actual NPC route, private observation and unique custody remain causally valid")


func _player_first_and_empty_observation(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner, true)
	if world == null: return
	_put(world, "player", _site(world))
	runner.assert_true(world.field_opportunities.observe_site("player", SITE).ok, "unbriefed player may personally inspect the original wild object")
	runner.assert_true(world.artifacts.begin("player", "take", RING).ok, "player first arrival uses the original artifact operation")
	var due: int = int(world.artifacts.active.player.due_ms)
	runner.assert_true(world.advance_to_ms(due), "player's original take consumes its real duration")
	_put(world, "player", CENTERS.home)
	if not _start(runner, world): return
	var deadline: int = world.elapsed_ms + 60000
	while world.field_opportunities.purposes[ACTOR].observed_event == "" and world.elapsed_ms < deadline:
		if not world.advance_to_ms(mini(deadline, world.elapsed_ms + 2000)): break
	var id: String = str(world.field_opportunities.purposes[ACTOR].observed_event)
	runner.assert_true(not id.is_empty(), "later resident actually reaches and observes the old slot")
	if id.is_empty(): return
	var known: Dictionary = world.services.social.knowledge[ACTOR][id]
	runner.assert_eq(known.details.outcome, "empty", "late arrival learns the place is empty rather than finding a reset reward")
	runner.assert_true(not known.details.has("holder"), "empty-site observation conveys no distant holder identity")
	runner.assert_eq(world.artifacts.objects[RING].container, "actor:player", "later NPC search never confiscates or regenerates the player's ring")
	runner.assert_true(world.field_opportunities.cross_valid(), "player-first and late empty observation have consistent original custody history")


func _existing_action_and_interruption(runner: Object) -> void:
	var busy: RegionalSimulation = _world(runner, true)
	if busy == null: return
	runner.assert_true(busy.regions.river.submit_action(ACTOR, "deliver_water"), "resident has a genuine native commitment before the personal purpose")
	runner.assert_true(not busy.field_opportunities.wants_decision(ACTOR, int(busy.field_opportunities.definitions.purpose.delay_ms)), "personal wish cannot replace an already running original native action")
	var world: RegionalSimulation = _world(runner, true)
	if world == null or not _start(runner, world): return
	world.advance_to_ms(world.elapsed_ms + 113)
	var point: Array = world.regions.river.actors[ACTOR].position.duplicate()
	var qi: int = int(world.regions.river.actors[ACTOR].qi)
	runner.assert_true(world.field_opportunities.cancel(ACTOR, "manual_override"), "interrupting real travel releases only the field process")
	runner.assert_eq(world.regions.river.actors[ACTOR].position, point, "interrupted resident stays at the exact actual point")
	runner.assert_true(not world.field_opportunities.owns_actor(ACTOR) and bool(world.regions.river.actors[ACTOR].autonomous), "interruption restores the original resident's native autonomy")
	runner.assert_eq(world.regions.river.actors[ACTOR].qi, qi, "interruption creates no qi refund or new charge")
	runner.assert_eq(world.artifacts.objects[RING].container, "site:broken_stele", "cancelled trip transfers no treasure")
	runner.assert_true(world.field_opportunities.cross_valid(), "interrupted continuous geometry and original private journey record validate")
	var restored: RegionalSimulation = _restored(runner, world)
	if restored != null:
		runner.assert_eq(_canonical(restored), _canonical(world), "cancelled purpose and native continuation survive independent load")


func _inflight_and_sparse_future(runner: Object) -> void:
	var coarse: RegionalSimulation = _world(runner, true)
	if coarse == null or not _start(runner, coarse): return
	coarse.advance_to_ms(coarse.elapsed_ms + 137)
	var fine: RegionalSimulation = _restored(runner, coarse)
	if fine == null: return
	var target: int = coarse.elapsed_ms + 90000
	runner.assert_true(coarse.advance_to_ms(target), "absent coarse world continues the same expedition and original take")
	while fine.elapsed_ms < target:
		if not fine.advance_to_ms(mini(target, fine.elapsed_ms + 137)): break
	runner.assert_eq(_canonical(fine), _canonical(coarse), "fine observations and sparse absence retain exactly the same complete future")
	var arrived: RegionalSimulation = _restored(runner, coarse)
	if arrived != null:
		runner.assert_true(arrived.advance_to_ms(target + 5000) and coarse.advance_to_ms(target + 5000), "post-take independent worlds continue through later perception boundaries")
		runner.assert_eq(_canonical(arrived), _canonical(coarse), "unique custody and private discoveries do not cold restart after load")


func _reject_bad_candidates(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner, true)
	if world == null or not _start(runner, world): return
	world.advance_to_ms(world.elapsed_ms + 137)
	var saved: Dictionary = world.to_dict()
	for fault: String in ["boolean_sample", "wrong_slot", "untraced_source", "jumping_path", "unknown_actor", "wrong_region", "native_overlap", "double_ring", "missing_field_origin"]:
		var bad: Dictionary = saved.duplicate(true)
		var id: String = str(bad.field_opportunities.purposes[ACTOR].trip)
		match fault:
			"boolean_sample": bad.field_opportunities.next_observation_ms = true
			"wrong_slot": bad.field_opportunities.sites[SITE].container = "records"
			"untraced_source": bad.field_opportunities.sites[SITE].source_events.chen_shouzhuo = "event_999999"
			"jumping_path": bad.field_opportunities.trips[id].path[0][0] += 10
			"unknown_actor": bad.field_opportunities.trips[id].actor = "nonexistent_actor"
			"wrong_region": bad.field_opportunities.trips[id].region = "nonexistent_region"
			"native_overlap": bad.regions.river.actors[ACTOR].autonomous = true
			"double_ring": bad.artifacts.objects["untraced_second_ring"] = {"definition": "drawing_ring", "region": "home", "container": "actor:player"}
			"missing_field_origin": bad.field_opportunities = SimFieldOpportunities.empty_state()
		var candidate: RegionalSimulation = _world(runner, true, false)
		if candidate == null: return
		var before: String = _canonical(candidate)
		var input: String = SnapshotValues.canonical_json(SnapshotValues.normalized(bad))
		runner.assert_true(not candidate.restore(bad), "joint field candidate rejects " + fault)
		runner.assert_eq(_canonical(candidate), before, "rejected " + fault + " preserves the whole live world")
		runner.assert_eq(SnapshotValues.canonical_json(SnapshotValues.normalized(bad)), input, "rejected " + fault + " does not repair its supplied candidate")
