extends "res://tests/abilities_smoke.gd"
const State = preload("res://scripts/sim/kernel/state.gd")
const Opening = preload("res://scripts/sim/scenarios/settlement_opening.gd")
const SETUP = preload("res://data/openings/qinghe_sect.tres")

func container_isolation() -> void:
	var typed: Array[int] = [1, 2]
	var typed_map: Dictionary[String, int] = {"v": 3}
	var shared: Dictionary = {"nested": [5, {"packed": PackedInt32Array([6, 7])}]}
	var original: Dictionary = {"one": shared, "two": shared, "typed": typed, "map": typed_map}
	original.make_read_only(); shared.make_read_only()
	var copied: Dictionary = State.copy(original)
	check(copied == original and not copied.is_read_only() and not copied.one.is_read_only(), "A detached data view retained owner read-only flags or changed values")
	copied.one.nested[1].packed[0] = 30
	copied.typed[0] = 40; copied.map.v = 50
	check(original.one.nested[1].packed[0] == 6 and original.typed[0] == 1 and original.map.v == 3, "A copied nested or typed container mutated source data")
	copied.two.nested[0] = 60
	check(original.two.nested[0] == 5, "Repeated subcontainer copies still share source ownership")
	var packed := PackedVector2Array([Vector2(1, 2)])
	var copied_packed: PackedVector2Array = State.copy(packed)
	copied_packed[0] = Vector2.ZERO
	check(packed[0] == Vector2(1, 2), "A root packed array was not detached")
	var decoded: Dictionary = bytes_to_var(var_to_bytes(State.copy(original)))
	decoded.one.nested[0] = 99
	check(original.one.nested[0] == 5, "Serialized pure data retained an owner alias")

func real_consumers() -> void:
	var w := World.new()
	check(w.initialize(SETUP.population(), 0, false, "empty") and Opening.assemble(w, SETUP).is_empty(), "Normal opening failed before copy consumers")
	while w.elapsed_ms < 5000: w.step(250)
	var target: int = w.knowledge.records[1].subjects.keys()[0]
	var first: Dictionary = w.knowledge.view(1, target, w.elapsed_ms)
	var known: Dictionary = w.knowledge.known(1, w.elapsed_ms)
	first["owner"] = 99999; known[target]["organization"] = 99999
	check(w.knowledge.records[1].subjects[target].view.owner != 99999 and w.knowledge.records[1].subjects[target].view.organization != 99999, "A public knowledge consumer mutated canonical memories")
	var captured: Dictionary = Persistence.capture(w)
	var candidate: RefCounted = Persistence.candidate(captured, 0)
	check(candidate != null, "Native containers did not reconstruct the actual running world")
	if candidate == null: return
	while candidate.elapsed_ms < 7000: candidate.step(250)
	check(w.elapsed_ms == 5000 and candidate.elapsed_ms == 7000, "A restored candidate advanced the original owner")
	check(Persistence.candidate(Persistence.capture(candidate), 0) != null, "The running candidate could not capture and restore again")

func _run() -> void:
	container_isolation()
	real_consumers()
	print("STATE_COPY_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
