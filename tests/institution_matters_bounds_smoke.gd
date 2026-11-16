extends "res://tests/institution_matters_smoke.gd"

func closed_matters_compact() -> void:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	for index: int in w.institutions.Matters.MATTER_LIMIT + 2:
		var matter: int = w.institutions.create_matter(w, 1, delivery_spec(f, 1, 1))
		check(matter > 0, "Closed matter capacity did not release reusable space")
		if matter == 0: break
		var share: int = w.institutions.accept_share(w, 3, matter, 1)
		check(share > 0 and w.institutions.cancel_matter(w, 1, matter), "Normative history fixture could not close accepted work")
	check(w.institutions.matters.size() <= w.institutions.Matters.MATTER_LIMIT and w.institutions.matter_ledger[f.org].cancelled > 0, "Closed normative history grew without its bounded summary")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "History compression left an active dangling personal goal")

func active_matter_shares_compact() -> void:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	var closed: int = w.institutions.create_matter(w, 1, delivery_spec(f))
	w.institutions.cancel_matter(w, 1, closed)
	var matter: int = w.institutions.create_matter(w, 1, delivery_spec(f))
	for index: int in w.institutions.Matters.SHARE_LIMIT + 1:
		var share: int = w.institutions.accept_share(w, 3, matter, 1)
		check(share > 0, "Active matter history prevented another lawful acceptance")
		if share == 0: break
		w.institutions.release_share(w, 3, share)
	check(w.institutions.matters.has(closed) and w.institutions.shares.size() <= w.institutions.Matters.SHARE_LIMIT and w.institutions.matters[matter].archived == 0, "Share pressure needlessly deleted unrelated matter history or invented fulfilment")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Compacted active matter left a dangling personal reference")

func _run() -> void:
	closed_matters_compact()
	active_matter_shares_compact()
	print("INSTITUTION_MATTERS_BOUNDS_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
