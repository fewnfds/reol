extends "res://tests/institution_matters_smoke.gd"

func elapsed_help_can_be_explicitly_reassigned() -> void:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	w.objects.add(1, "wood", 3)
	var site: int = w.facilities.blueprint(w, 1, "wood_wall", w.Terrain.index(Vector2i(129, 124))).target
	w.flush_topology(); w.knowledge.seed(w, 1, w.operation_target(site), 0)
	var matter: int = w.institutions.create_matter(w, 1, {"kind": "operation", "target": site, "operation": "construct", "deadline_ms": 100})
	var share: int = w.institutions.accept_share(w, 3, matter, 1)
	advance(w, 200)
	check(w.institutions.release_share(w, 3, share), "Explicit reassignment did not release the elapsed obligation")
	move_actor(w, 1, w.pages[0].positions[3] + Vector2(-1, 0))
	check(w.execute_operation(1, {"kind": "request_help", "target": 4, "task_target": site}) == "accepted", "Renewed help could not enter the real contact host")
	w.settle_action(1, w.elapsed_ms); advance(w, w.elapsed_ms + 1100)
	var accepted: Array = w.institutions.Matters.shares_for(w.institutions, 4)
	check(accepted.size() == 1 and accepted[0].matter != matter and w.institutions.shares[share].state == "released", "Released elapsed help permanently blocked a new concrete request")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Old and renewed help failed restore")

func revoked_source_releases_only_the_original_host() -> void:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	var source: int = w.source_objects[0]
	w.objects.records[source].organization = f.org
	w.objects.retitle(source, "stock", Stock.right(), Stock.right(0, f.org))
	w.knowledge.seed(w, 1, w.operation_target(source), 0)
	var spec: Dictionary = delivery_spec(f, 1, 1); spec.item = "wood"; spec.sources = [source]
	var matter: int = w.institutions.create_matter(w, 1, spec)
	var share: int = w.institutions.accept_share(w, 3, matter)
	move_actor(w, 3, w.Terrain.center(w.objects.records[source].tile))
	check(w.execute_operation(3, {"kind": "harvest", "target": source, "purpose": "supply"}) == "accepted", "Revocation fixture failed shared source admission")
	advance(w, 200)
	check(w.pages[0].modes[2] == w.Units.Mode.HARVEST and w.institutions.release_share(w, 3, share), "Harvest revocation did not reach its reserved phase")
	check(w.gate.current(3).is_empty() and not w.reservations.has(source) and w.objects.amount(3, "wood") == 0 and Persistence.candidate(Persistence.capture(w), 0) != null, "Revoked source permission left a live harvest reservation or fabricated yield")
	var completed: int = w.institutions.create_matter(w, 1, {"kind": "operation", "organization": f.org, "target": source, "operation": "harvest"})
	check(completed > 0 and w.institutions.accept_share(w, 3, completed, 1) > 0, "Single harvest completion could not be commissioned")
	check(w.execute_operation(3, {"kind": "harvest", "target": source}) == "accepted", "Single obligated harvest did not enter work host")
	advance(w, w.elapsed_ms + 700)
	check(w.institutions.matters[completed].state == "completed" and w.objects.amount(3, "wood") == 1 and Persistence.candidate(Persistence.capture(w), 0) != null, "Harvest completion re-entered the already erased work binding")

func cancelled_temporary_search_stops() -> void:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	w.knowledge.record(4).subjects.clear(); w.knowledge.set_observation_due(w, 4, 5000)
	var matter: int = w.institutions.create_matter(w, 1, delivery_spec(f, 2, 2))
	check(w.institutions.accept_share(w, 4, matter, 2, true) > 0, "Temporary responsibility could not enable an idle helper")
	w.decisions.resume(w, 4, 0)
	decide(w, 0)
	check(w.pages[0].modes[3] == w.Units.Mode.EXPLORE, "Unknown-site helper did not really start an autonomous search")
	check(w.institutions.cancel_matter(w, 1, matter) and not w.objects.records[4].autonomous and w.gate.current(4).is_empty() and w.pages[0].modes[3] == w.Units.Mode.IDLE, "Cancelled borrowed autonomy retained an unrelated future search")
	advance(w, 1000)
	check(not w.objects.records[4].autonomous and w.gate.current(4).is_empty() and Persistence.candidate(Persistence.capture(w), 0) != null, "Completed cancellation restarted the idle helper")

func _run() -> void:
	elapsed_help_can_be_explicitly_reassigned()
	revoked_source_releases_only_the_original_host()
	cancelled_temporary_search_stops()
	print("INSTITUTION_MATTERS_HANDOFFS_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
