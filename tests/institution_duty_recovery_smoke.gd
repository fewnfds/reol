extends "res://tests/institution_duties_smoke.gd"

func worker_share(w: RefCounted, actor: int) -> Dictionary:
	var shares: Array = w.institutions.Matters.shares_for(w.institutions, actor)
	return shares[0] if not shares.is_empty() else {}

func exhausted_materials_report_return_and_resume() -> void:
	var f: Dictionary = duties_fixture()
	var w: RefCounted = f.world
	# An administrator can inspect/post without the physical labor capability.
	check(w.set_capability_overrides(3, {"work": false}), "Administrative capability fixture failed")
	w.decisions.prepare(w, 0)
	while w.elapsed_ms < 15000 and (w.objects.amount(4, "grain") == 0 or w.objects.amount(4, "water") > 0): advance(w, w.elapsed_ms + 16)
	check(w.objects.amount(4, "grain") == 2 and not worker_share(w, 4).is_empty(), "Worker never actually fetched its first entrusted ingredient")
	var share: Dictionary = worker_share(w, 4)
	w.objects.add(f.source, "water", -w.objects.amount(f.source, "water"))
	advance(w, w.elapsed_ms + 25000)
	var posted: Dictionary = w.institutions.channels[f.board].posts[int(share.matter)]
	check(w.institutions.shares[share.id].state == "released" and posted.signatures[share.id].status == "blocked" and posted.state == "closed" and w.objects.amount(4, "grain") == 0 and w.objects.amount(f.source, "grain") == 12, "Exhausted prerequisite caused hoarding, repeated issue or unreported silent release")
	check(w.institutions.matters.values().filter(func(value: Dictionary): return value.state == "active").is_empty(), "Source exhaustion caused administrative reissue without a real source")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Reported shortage and returned entrusted materials failed restore")
	w.objects.add(f.source, "water", 6, Stock.right(0, f.org))
	advance(w, w.elapsed_ms + 50000)
	check(w.objects.amount(f.destination, "meal", Stock.right(0, f.org)) >= 3 and w.facilities.completed.get("cook", 0) > 0, "Observed replenishment failed to restart ordinary duty production/supply")

func absence_keeps_allocation_until_real_expiry_review() -> void:
	var f: Dictionary = duties_fixture()
	var w: RefCounted = f.world
	w.set_capability_overrides(3, {"work": false})
	w.decisions.prepare(w, 0)
	while w.elapsed_ms < 15000 and worker_share(w, 4).is_empty(): advance(w, w.elapsed_ms + 16)
	var share: Dictionary = worker_share(w, 4)
	check(not share.is_empty(), "Absence fixture did not really accept a posted responsibility")
	if share.is_empty(): return
	var matter: int = share.matter
	var deadline: int = share.deadline_ms
	w.kill(4); w.remove_actor(4)
	advance(w, deadline - 1)
	check(w.institutions.shares[share.id].state == "accepted" and w.institutions.Matters.occupied(w.institutions, w.institutions.matters[matter]) == 3 and w.institutions.channels[f.board].posts[matter].signatures[share.id].status == "accepted" and w.institutions.matters.size() == 1, "Remote death wirelessly freed capacity or triggered replacement")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Historical absent worker/board signature failed restore")
	advance(w, deadline + 30000)
	check(w.institutions.shares[share.id].state == "released" and w.institutions.channels[f.board].posts[matter].state == "closed" and w.institutions.matters.size() > 1, "Actual expiry/site/desk review never renewed an unfulfilled shortage")
	check(w.institutions.channels[f.board].posts[matter].signatures[share.id].status == "accepted" and Persistence.candidate(Persistence.capture(w), 0) != null, "Expiry fabricated a returned death report or broke historical recovery")

func _run() -> void:
	exhausted_materials_report_return_and_resume()
	absence_keeps_allocation_until_real_expiry_review()
	print("INSTITUTION_DUTY_RECOVERY_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
