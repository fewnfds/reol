extends SceneTree
## Same normal opening, no gifts/teleports/shortened days. Optional long window:
## -- --duration=1260000. Writes a test-only checkpoint through SessionIO.
const World = preload("res://scripts/sim/kernel/world.gd")
const Opening = preload("res://scripts/sim/scenarios/settlement_opening.gd")
const Setup = preload("res://data/openings/qinghe_sect.tres")
const Persistence = preload("res://scripts/sim/kernel/persistence.gd")
const SessionIO = preload("res://scripts/sim/kernel/session_io.gd")
var errors: int = 0

func check(ok: bool, message: String) -> void:
	if not ok: errors += 1; push_error(message)

func configuration(w: RefCounted) -> Dictionary:
	var result: Dictionary = {}
	for id: int in w.institutions.departments:
		var d: Dictionary = w.institutions.departments[id]
		result[id] = {"workers": d.workers.duplicate(true), "groups": d.groups.duplicate(true), "grants": d.grants.duplicate(true), "supplier": d.supplier, "facilities": d.facilities.duplicate(), "recipes": {}}
		for target: int in d.production: result[id].recipes[target] = d.production[target].operation
	return result

func sample(w: RefCounted) -> Dictionary:
	var totals: Dictionary = {}; var active: Dictionary = {}
	for m: Dictionary in w.institutions.matters.values():
		if m.kind != "department" or m.parent_order > 0: continue
		totals[int(m.department)] = int(totals.get(int(m.department), 0)) + int(m.fulfilled)
		if m.repeat: active[int(m.department)] = {"id": m.id, "actual": m.fulfilled, "wip": w.institutions._order_wip.get(int(m.id), 0)}
	var states: Dictionary = {}
	var oldest: int = 0
	for s: Dictionary in w.institutions.shipments.values():
		states[s.state] = int(states.get(s.state, 0)) + 1
		if s.state in ["reserved", "carrying", "returning"]: oldest = maxi(oldest, w.elapsed_ms - int(s.created_ms))
	return {"at_ms": w.elapsed_ms, "production": totals, "current": active, "shipments": states, "oldest_active_ms": oldest, "grain": w.objects.total("grain"), "meal": w.objects.total("meal"), "generated": w.nature.generated_items, "activities": w.facilities.completed, "station_candidates": w.stations.candidates, "station_queries": w.stations.queries}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var duration: int = 120000
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--duration="): duration = int(arg.trim_prefix("--duration="))
	var w := World.new()
	w.initialize(100, 0, false, "empty")
	check(Opening.assemble(w, Setup).is_empty(), "Normal department assembly failed")
	var original: Dictionary = configuration(w)
	var restored: bool = false
	var path: String = "user://department-autonomy-fixture.reol"
	while w.elapsed_ms < duration and errors == 0:
		w.step(mini(250, duration - w.elapsed_ms))
		if w.elapsed_ms % 120000 == 0: print("DEPARTMENT_AUTONOMY ", JSON.stringify(sample(w)))
		if not restored and w.elapsed_ms >= 60000:
			var io := SessionIO.new(); io._notify = func(): pass
			io._run({"kind": "save", "path": path}, Persistence.capture(w), 0)
			check(io.poll().get("ok", false), "Normal department file save failed")
			io._run({"kind": "load", "path": path}, {}, 0)
			var loaded: Dictionary = io.poll()
			check(loaded.get("ok", false), "Normal in-flight department file restore failed")
			if not loaded.get("ok", false): break
			check(loaded.candidate.institutions.departments == w.institutions.departments and loaded.candidate.institutions.shipments == w.institutions.shipments, "Restore changed configuration/transport facts")
			w.deferred.close(); w = loaded.candidate; restored = true
			print("DEPARTMENT_CHECKPOINT ", JSON.stringify(sample(w)))
	check(configuration(w) == original, "NPC management rewrote player work/supply/authority configuration")
	check(restored, "Autonomy window did not exercise its actual file checkpoint")
	var result: Dictionary = sample(w)
	check(result.production.size() == 4, "Normal opening lost a kitchen objective")
	for amount: int in result.production.values(): check(amount > 0, "A normal kitchen never physically produced food")
	check(int(w.facilities.completed.get("eat", 0)) > 0 and int(result.shipments.get("completed", 0)) > 0, "No actual eating or material delivery occurred")
	if duration > w.institutions.Orders.DAY_MS:
		for current: Dictionary in result.current.values(): check(current.id > 4, "Daily production objective did not advance to a new identity")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Final normal department world rejected restoration")
	print("DEPARTMENT_AUTONOMY_FINISH errors=", errors, " ", JSON.stringify(result))
	w.deferred.close()
	for cleanup: String in [path, path + ".tmp", path + ".bak"]:
		if FileAccess.file_exists(cleanup): DirAccess.remove_absolute(cleanup)
	quit(0 if errors == 0 else 1)
