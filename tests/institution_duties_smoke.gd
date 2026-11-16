extends "res://tests/institution_matters_smoke.gd"
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")

func duties_fixture() -> Dictionary:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	f.board = workshop(w, f.org, "notice_desk", Vector2i(121, 124))
	w.flush_topology()
	w.objects.add(f.source, "grain", 12, Stock.right(0, f.org)); w.objects.add(f.source, "water", 6, Stock.right(0, f.org))
	resident(w, 3, [f.source, f.destination, f.stove, f.board])
	resident(w, 4, [f.board])
	Growth.seed(w.objects.records[4], "cooking", 0, false)
	f.kitchen = w.institutions.appoint(w, f.org, 3, "kitchen_steward", [f.source, f.stove, f.board], {"target": int(f.stove), "sources": [int(f.source)], "channel": int(f.board)})
	f.meals = w.institutions.appoint(w, f.org, 3, "meal_steward", [f.destination, f.stove, f.board], {"target": int(f.destination), "sources": [int(f.stove)], "channel": int(f.board)})
	check(f.kitchen > 0 and f.meals > 0, "Authored duties did not bind to real places")
	return f

func autonomous_two_stage_supply() -> void:
	var f: Dictionary = duties_fixture()
	var w: RefCounted = f.world
	check(w.institutions.matters.is_empty() and w.institutions.channels.is_empty(), "Appointment injected ready-made work or remote board contents")
	w.decisions.prepare(w, 0)
	advance(w, 60000)
	var meals: int = w.objects.amount(f.destination, "meal", Stock.right(0, f.org))
	check(meals >= 3 and w.objects.amount(f.source, "grain") < 12 and w.facilities.completed.get("cook", 0) > 0, "Autonomous inspection/post/read/accept/production/delivery failed: " + str({"world_ms": w.elapsed_ms, "meals": meals, "stove": w.objects.inventory_summary(f.stove), "board": w.institutions.channels, "manager": w.livelihood.describe(3), "worker": w.livelihood.describe(4)}))
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Actual duty/channel/production state failed restoration")
	# Consume real public food, then require another autonomous replenishment.
	w.institutions.admit(w, f.org, 1, Array(w.institutions.PURPOSES))
	var eaten: int = mini(meals, 6)
	for index: int in eaten: check(w.institutions.consume_at(w, 1, f.destination, "meal", 1, "eat"), "Public meal did not actually leave stock")
	var before: int = w.facilities.completed.get("cook", 0)
	advance(w, w.elapsed_ms + 60000)
	check(w.objects.amount(f.destination, "meal", Stock.right(0, f.org)) >= 3 and int(w.facilities.completed.get("cook", 0)) > before, "Second depletion did not restart real upstream production and supply")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Repeated duty cycle did not restore")

func _run() -> void:
	check(Roles.ERRORS.is_empty() and Operations.ERRORS.is_empty() and Agency.ERRORS.is_empty(), "Authored duty/operation/agency catalogs failed: " + str(Roles.ERRORS) + str(Operations.ERRORS) + str(Agency.ERRORS))
	autonomous_two_stage_supply()
	print("INSTITUTION_DUTIES_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
