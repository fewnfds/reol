extends "res://tests/abilities_smoke.gd"
const Opening = preload("res://scripts/sim/scenarios/settlement_opening.gd")
const SETUP = preload("res://data/openings/qinghe_sect.tres")
const Frame = preload("res://scripts/sim/kernel/frame.gd")
const Subject = preload("res://scripts/presentation/ui/subject_view.gd")
const Runner = preload("res://scripts/sim/kernel/runner.gd")

func snapshot(w: RefCounted, selected: int) -> RefCounted:
	var f := Frame.new()
	f.actor_slots = w.actor_slots.duplicate(); f.visible = w.perception.visible.duplicate()
	f.objects = w.objects.layout()
	f.perception = {"tiles": w.perception.tiles.duplicate(), "memories": w.State.copy(w.perception.memories)}
	f.player = w.describe(1); f.inspected = w.describe(selected)
	f.inspected_id = selected
	f.inspected_clue = w.knowledge.account_view(1, selected, w.elapsed_ms)
	f.inspected_social = w.institutions.public_profile(1, selected)
	return f

func personal_and_observed() -> void:
	var w := World.new()
	check(w.initialize(SETUP.population(), 0, false, "empty") and Opening.assemble(w, SETUP).is_empty(), "Subject views could not use the actual product opening")
	var frame: RefCounted = snapshot(w, 8)
	check(Subject.visible(frame, 8, true), "The actual initial teacher is not visible")
	var knowledge_before: PackedByteArray = var_to_bytes(w.knowledge.records)
	var own: Dictionary = Subject.observed(frame, 1, true)
	check(own.has("energy") and own.has("events") and own.get("service_targets", {}).get("rest", []).size() == 1, "The player's own details or allocated rest place were hidden")
	frame.inspected["future_private_field"] = {"secret": true}
	frame.inspected.activity = {"phase": "approaching", "operation": "cook", "target": 123456}
	var observed: Dictionary = Subject.observed(frame, 8, true)
	for field: String in ["events", "methods", "qi", "aptitudes", "agency", "decision", "inventory", "bundles", "responsibilities", "reports", "route_preview", "destination", "future_private_field"]:
		check(not observed.has(field), "Visible body exposed private detail: " + field)
	check(observed.name == w.objects.records[8].name and observed.teaches.has("wood_breath") and observed.teaches.has("cooking"), "A fellow member lost explicitly public teacher/identity information")
	check(not observed.activity.has("operation") and not observed.activity.has("target"), "Travel revealed another person's hidden destination or intended action")
	check(observed.service_targets.rest.size() == 1, "Visible fellow member's public allocated rest place was missing")
	check(observed.memberships.size() == 1 and observed.memberships[0].name == SETUP.title and w.objects.records[8].organization == 0, "Institutional membership was confused with an actor's asset attribution")
	frame.inspected_social.id = 9
	check(not Subject.observed(frame, 8, true).has("memberships"), "A different inspected identity's institutional profile was adopted")
	frame.inspected_social.id = 8
	frame.inspected.activity = {"phase": "acting", "operation": "learn", "target": 1, "role": "teacher"}
	check(Subject.observed(frame, 8, true).activity.get("role") == "teacher", "Actually visible shared teaching lost its public action")
	frame.visible[frame.actor_slots[8]] = 0
	frame.inspected.name = "REMOTE SECRET RENAME"; frame.inspected.hp = 0
	var memory: Dictionary = Subject.observed(frame, 8, true)
	check(memory.get("memory", false) and memory.name != "REMOTE SECRET RENAME" and memory.name == w.objects.records[8].name, "Leaving sight erased acquired identity or refreshed it from remote truth")
	check(not memory.has("activity") and int(memory.hp) == 1, "Remote death or current activity leaked into remembered identity")
	frame.inspected_id = 1
	check(Subject.observed(frame, 8, true).get("pending", false), "A pending offscreen inspection erased previously acquired identity")
	frame.inspected_id = 8
	frame.inspected_clue = {}; check(Subject.observed(frame, 8, true).is_empty(), "An unknown offscreen body supplied its own identity")
	frame.visible[frame.actor_slots[8]] = 255; frame.inspected = w.describe(1)
	check(Subject.observed(frame, 8, true).get("pending", false), "A stale detail Frame was mistaken for an unknown person")
	frame.inspected = w.describe(8); frame.inspected.hp = 0
	check(Subject.observed(frame, 8, true).activity.phase == "dead", "A visible dead person was presented as idle")
	check(var_to_bytes(w.knowledge.records) == knowledge_before, "Opening/refreshing UI created, renewed or changed personal knowledge")
	var state: Dictionary = Persistence.capture(w)
	check(Persistence.candidate(state, 0) != null, "Acquired names/public teaching failed actual restoration")
	state.domains.knowledge.records[1].subjects[8].view.name = "x".repeat(257)
	check(Persistence.candidate(state, 0) == null, "Unbounded acquired identity text restored")
	var other: int = w.institutions.create("隐修会")
	check(w.institutions.admit(w, other, 8, []), "Second membership could not use the original organization owner")
	var private_bed: int = w.facilities.create_completed(w, "wood_bed", w.Terrain.index(Vector2i(200, 200)))
	w.objects.records[private_bed].organization = other
	check(w.institutions.arrange_service(w, private_bed, "rest", [8]), "Second institution could not allocate its own rest place")
	frame = snapshot(w, 8)
	observed = Subject.observed(frame, 8, true)
	check(observed.memberships.size() == 1 and not observed.service_targets.rest.has(private_bed), "A shared sect exposed another institution's membership or private rest allocation")
	check(w.institutions.public_profile(0, 8).memberships.is_empty(), "An outsider acquired member-only institutional information")
	var bed: int = int(observed.service_targets.rest[0])
	check(w.remove_static(bed), "The observed rest allocation could not be removed through the original lifecycle")
	check(Subject.observed(snapshot(w, 8), 8, true).service_targets.rest.is_empty(), "The public profile retained a removed bed as a second residence truth")
	# A reliable result may update detail between expensive map publications.
	# The latest observed body mask must accompany it, not the old slow frame.
	var runner := Runner.new()
	runner._world = w; runner._terrain_view = w.terrain.detached()
	runner._publish(false, 1.0, 8, -1)
	var old: RefCounted = runner.poll().frame
	w.perception.visible[w.actor_slots[8]] = 0
	w.outcomes.append({"kind": "completed", "actor": 1, "at_ms": w.elapsed_ms})
	runner._publish(false, 1.0, 8, -1)
	frame = runner.poll().frame
	check(runner._slow_frame == old and frame.visible[w.actor_slots[8]] == 0 and old.visible[w.actor_slots[8]] != 0, "A detail notification either mutated the held frame, forced a full map publication, or used stale body visibility")
	check(Subject.observed(frame, 8, true).get("memory", false), "A reliable outcome exposed a currently unseen person's new details")

func _run() -> void:
	personal_and_observed()
	print("SUBJECT_VIEW_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
