extends "res://tests/custody_smoke.gd"
const Departments = preload("res://scripts/sim/kernel/department_rules.gd")

func departments() -> void:
	var w: RefCounted = peaceful()
	var org: int = organization(w, [1, 2, 3])
	var root: int = Departments.create(w.institutions, org, "总务")
	var kitchen: int = Departments.create(w.institutions, org, "东院厨房", root)
	var stove: int = facility(w, "cook_stove", 124, 124, org)
	check(Departments.attach(w.institutions, w, kitchen, stove), "Department facility rejected")
	w.institutions.departments[kitchen].groups = {"一组": {"facilities": [stove]}, "二组": {"facilities": [stove]}}
	check(Departments.grant(w.institutions, root, 1, "自定义掌事", Array(Departments.CAPABILITIES), true), "Custom authority rejected")
	check(Departments.assign(w.institutions, kitchen, 3, ["haul", "produce"], ["一组", "二组"]), "Overlapping work groups rejected")
	check(Departments.worker_targets(w.institutions, 3) == [stove], "Shared group facilities counted twice")
	check(Departments.allowed(w.institutions, 1, kitchen, "people") and not Departments.allowed(w.institutions, 3, kitchen, "people"), "Labor became management authority")
	check(Departments.command(w.institutions, w, 3, {"op": "assign", "department": kitchen, "worker": 2, "duties": ["haul"], "groups": []}) == "not_authorized", "Worker forged management command")
	var manager: Dictionary = Departments.view(w.institutions, w, 1, kitchen)
	var employee: Dictionary = Departments.view(w.institutions, w, 3, kitchen)
	check(manager.selected.facilities.size() == 1 and employee.selected.facilities.size() == 1 and employee.selected.capabilities.is_empty() and employee.selected.workers.size() == 1, "Workspace scope leaked management or duplicated assets")
	check(Departments.command(w.institutions, w, 1, {"op": "assign", "department": kitchen, "revision": -1, "worker": 3, "duties": [], "groups": []}) == "configuration_changed", "Stale management configuration was adopted")
	var binding: Dictionary = w.gate.current(1).duplicate()
	check(Departments.command(w.institutions, w, 1, {"op": "assign", "department": kitchen, "worker": 3, "duties": ["haul"], "groups": ["一组"]}) == "management_updated" and w.gate.current(1) == binding, "Management took body action gate")
	var state: Dictionary = Persistence.capture(w)
	var restored: RefCounted = Persistence.candidate(state, 0)
	check(restored != null, "Department facts did not restore")
	if restored != null: check(Departments.worker_targets(restored.institutions, 3) == [stove], "Restored department index missing")
	state.domains.institutions.departments[root].parent = kitchen
	check(Persistence.candidate(state, 0) == null, "Cyclic departmental hierarchy restored")

func _run() -> void:
	departments()
	print("DEPARTMENTS_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
