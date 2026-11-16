extends "res://tests/institution_matters_smoke.gd"

func provenance_and_competing_claims() -> void:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	w.institutions.admit(w, f.org, 3, Array(w.institutions.PURPOSES))
	w.objects.add(f.source, "grain", 2, Stock.right(0, f.org))
	w.objects.add(f.destination, "grain", 2, Stock.right(0, f.org))
	var matter: int = w.institutions.create_matter(w, 1, delivery_spec(f, 2, 2))
	var share: int = w.institutions.accept_share(w, 3, matter, 2)
	manual_transfer(w, 3, f.destination, "grain", 1, "take", {"purpose": "supply"})
	manual_transfer(w, 3, f.destination, "grain", 1, "put")
	check(w.institutions.shares[share].fulfilled == 0, "Destination withdrawal/redeposit became new delivery")
	w.objects.add(3, "grain", 1, Stock.right(3))
	manual_transfer(w, 3, f.destination, "grain", 1, "put")
	check(w.institutions.shares[share].fulfilled == 0 and w.objects.amount(f.destination, "grain", Stock.right(3)) == 1, "Private custody became organizational supply")
	manual_transfer(w, 3, f.source, "grain", 1, "take", {"purpose": "cook"})
	manual_transfer(w, 3, f.destination, "grain", 1, "put")
	check(w.institutions.shares[share].fulfilled == 0, "Cooking surplus return became a supply obligation")
	var competing: int = w.institutions.create_matter(w, 1, delivery_spec(f, 2, 2))
	var second: int = w.institutions.accept_share(w, 3, competing, 2)
	manual_transfer(w, 3, f.source, "grain", 1, "take", {"purpose": "supply"})
	var result: Dictionary = manual_transfer(w, 3, f.destination, "grain", 1, "put")
	check(w.institutions.shares[share].fulfilled + w.institutions.shares[second].fulfilled == 1, "One actual delivery credited overlapping obligations twice")
	w.institutions.outcome(w, result)
	check(w.institutions.shares[share].fulfilled + w.institutions.shares[second].fulfilled == 1, "Replay redirected old goods into a competing uncredited obligation")
	check(w.institutions.release_share(w, 3, share) and w.institutions.Matters.occupied(w.institutions, w.institutions.matters[matter]) == 1, "Releasing a partly fulfilled share erased delivered evidence or held unused quota")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Provenance or released partial work did not restore")

func construction_pause_death_and_deadline() -> void:
	var w: RefCounted = peaceful()
	w.objects.add(1, "wood", 3, Stock.right(1))
	move_actor(w, 1, Vector2(123.5, 120.5)); move_actor(w, 2, Vector2(124.5, 120.5))
	w.pages[0].energy[1] = 10000; w.pages[0].hunger[1] = 10000
	var site: Dictionary = w.facilities.blueprint(w, 1, "wood_wall", w.Terrain.index(Vector2i(127, 122)))
	check(site.reason == "accepted", "Formal help blueprint fixture failed")
	if site.reason != "accepted": return
	w.objects.records[site.target].remaining_ms = 3000 # Exercise handoff, not three minutes of content labor.
	w.flush_topology()
	check(w.execute_operation(1, {"kind": "request_help", "target": 2, "task_target": int(site.target)}) == "accepted", "Formal help contact refused")
	w.settle_action(1, 0)
	advance(w, 1800)
	var result: Dictionary = w.activity_results.view(1).back()
	check(result.operation == "request_help" and result.status == "completed" and result.facts.has("share"), "Actual help contact never accepted a normative share")
	if not result.facts.has("share"): return
	var share: int = result.facts.share
	var matter: int = result.facts.matter
	w.command({"kind": "interrupt", "actor": 2})
	check(w.institutions.shares[share].state == "accepted" and not w.objects.records[2].has("commitment"), "Manual pause erased responsibility or retained duplicate commitment")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Paused helper responsibility could not restore")
	if restored == null: return
	w = restored
	w.command({"kind": "work", "actor": 2})
	advance(w, w.elapsed_ms + 12000)
	check(w.objects.records[site.target].kind == "wall" and w.institutions.matters[matter].state == "completed" and w.institutions.shares[share].fulfilled == 1, "Resuming did not complete the original materials/work and obligation: " + str({"site": w.objects.records[site.target], "share": w.institutions.shares[share], "agency": w.livelihood.describe(2), "results": w.activity_results.view(2)}))
	var f: Dictionary = commission_fixture()
	w = f.world
	var spec: Dictionary = delivery_spec(f, 2, 2); spec["deadline_ms"] = 100
	matter = w.institutions.create_matter(w, 1, spec)
	share = w.institutions.accept_share(w, 3, matter, 2)
	advance(w, 200)
	check(w.operation_actor(3).responsibilities[share].overdue and w.institutions.accept_share(w, 4, matter, 1) == 0 and w.institutions.Matters.occupied(w.institutions, w.institutions.matters[matter]) == 2, "Deadline automatically freed and reassigned an unresolved obligation")
	w.kill(3); w.remove_actor(3)
	check(w.institutions.shares[share].state == "accepted" and w.institutions.Matters.occupied(w.institutions, w.institutions.matters[matter]) == 2 and Persistence.candidate(Persistence.capture(w), 0) != null, "Absent/dead obligor was silently replaced or made history invalid")

func _run() -> void:
	provenance_and_competing_claims()
	construction_pause_death_and_deadline()
	print("INSTITUTION_OBLIGATIONS_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
