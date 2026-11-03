extends RefCounted

const Inventory = preload("res://scripts/sim/inventory_ledger.gd")
const InstitutionBook = preload("res://scripts/sim/institution_book.gd")
const SaveStore = preload("res://scripts/persistence/save_store.gd")


func run(runner: Object) -> void:
	_test_competing_reservations_and_cancel(runner)
	_test_transfer_conservation_and_idempotency(runner)
	_test_consume_and_failed_transfer(runner)
	_test_inventory_snapshot_validation(runner)
	_test_permissions_and_succession(runner)
	_test_institution_snapshot_validation(runner)
	_test_empty_operations_and_incomplete_snapshots(runner)
	_test_save_store(runner)


func _test_competing_reservations_and_cancel(runner: Object) -> void:
	var inventory := Inventory.new()
	runner.assert_true(inventory.create_container("store", {"medicine": 3}), "create store")
	runner.assert_true(inventory.reserve("job_a", "store", "medicine", 2, "a"), "first reserve")
	runner.assert_true(
		inventory.reserve("job_a", "store", "medicine", 2, "a"), "reservation retry is idempotent"
	)
	runner.assert_true(
		not inventory.reserve("job_a", "store", "medicine", 1, "a"), "reject reservation conflict"
	)
	runner.assert_true(
		not inventory.reserve("job_b", "store", "medicine", 2, "b"), "cannot double reserve stock"
	)
	runner.assert_true(
		not inventory.consume("steal_reserved", "store", "medicine", 2), "consume respects reservations"
	)
	runner.assert_eq(inventory.available("store", "medicine"), 1, "one medicine remains available")
	inventory.release("job_a")
	inventory.release("job_a")
	runner.assert_eq(inventory.available("store", "medicine"), 3, "cancel returns availability")
	runner.assert_eq(inventory.quantity("store", "medicine"), 3, "cancel does not duplicate stock")
	runner.assert_true(
		inventory.reserve("job_b", "store", "medicine", 2, "b"), "other worker reserves after cancel"
	)


func _test_transfer_conservation_and_idempotency(runner: Object) -> void:
	var inventory := Inventory.new()
	inventory.create_container("store", {"medicine": 3})
	inventory.create_container("patient", {})
	inventory.reserve("dose", "store", "medicine", 2, "patient")
	runner.assert_true(
		inventory.transfer("deliver", "store", "patient", "medicine", 2, "dose"), "reserved transfer"
	)
	runner.assert_eq(inventory.quantity("store", "medicine"), 1, "source loses transferred goods")
	runner.assert_eq(inventory.quantity("patient", "medicine"), 2, "target receives transferred goods")
	runner.assert_eq(
		inventory.quantity("store", "medicine") + inventory.quantity("patient", "medicine"),
		3,
		"transfer preserves total quantity"
	)
	runner.assert_eq(inventory.reservations.size(), 0, "delivery completes its reservation")
	runner.assert_true(
		inventory.transfer("deliver", "store", "patient", "medicine", 2, "dose"),
		"delivery retry succeeds"
	)
	runner.assert_true(
		not inventory.transfer("deliver", "store", "patient", "medicine", 1, "dose"),
		"reject changed retry"
	)
	runner.assert_true(
		not inventory.consume("deliver", "patient", "medicine", 2), "operation ids span operation kinds"
	)
	runner.assert_eq(inventory.quantity("patient", "medicine"), 2, "retries do not duplicate delivery")
	runner.assert_eq(inventory.operations.size(), 1, "successful delivery retains one record")


func _test_consume_and_failed_transfer(runner: Object) -> void:
	var inventory := Inventory.new()
	inventory.create_container("bag", {"food": 2})
	var before: Dictionary = inventory.to_dict()
	runner.assert_true(
		not inventory.transfer("missing", "bag", "unknown", "food", 1), "reject missing destination"
	)
	runner.assert_true(
		not inventory.transfer("self", "bag", "bag", "food", 1), "reject self transfer"
	)
	runner.assert_eq(inventory.to_dict(), before, "failed transfers leave entire ledger unchanged")
	runner.assert_true(inventory.consume("eat", "bag", "food", 2), "consume unreserved stock")
	runner.assert_true(inventory.consume("eat", "bag", "food", 2), "consume retry after depletion")
	runner.assert_true(not inventory.consume("eat", "bag", "food", 1), "consume conflict rejected")
	runner.assert_eq(inventory.quantity("bag", "food"), 0, "consume removes goods exactly once")
	runner.assert_true(
		not inventory.consume("eat_again", "bag", "food", 1), "cannot consume absent goods"
	)


func _test_inventory_snapshot_validation(runner: Object) -> void:
	var inventory := Inventory.new()
	inventory.create_container("store", {"medicine": 3})
	inventory.create_container("bag", {})
	inventory.transfer("delivery", "store", "bag", "medicine", 1)
	inventory.reserve("pending", "store", "medicine", 2, "worker")
	var snapshot: Dictionary = inventory.to_dict()
	var restored := Inventory.new()
	var json_snapshot: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	runner.assert_true(restored.restore(json_snapshot), "inventory JSON snapshot restores")
	runner.assert_eq(
		restored.to_dict(), snapshot, "inventory roundtrip keeps records and reservations"
	)
	runner.assert_true(
		restored.transfer("delivery", "store", "bag", "medicine", 1), "idempotency survives load"
	)
	var damaged: Dictionary = snapshot.duplicate(true)
	damaged["containers"]["store"]["medicine"] = -1
	runner.assert_true(not restored.restore(damaged), "reject negative snapshot quantity")
	damaged = snapshot.duplicate(true)
	damaged["reservations"]["pending"]["amount"] = 3
	runner.assert_true(not restored.restore(damaged), "reject over-reserved snapshot")
	damaged = snapshot.duplicate(true)
	damaged["reservations"]["pending"]["container"] = "missing"
	runner.assert_true(not restored.restore(damaged), "reject orphan reservation")
	damaged = snapshot.duplicate(true)
	damaged["operations"]["delivery"]["target"] = "missing"
	runner.assert_true(not restored.restore(damaged), "reject orphan transfer record")
	damaged = snapshot.duplicate(true)
	damaged["containers"]["store"]["medicine"] = 1.5
	runner.assert_true(not restored.restore(damaged), "reject fractional item quantity")
	runner.assert_eq(restored.to_dict(), snapshot, "bad snapshots never replace valid inventory")
	snapshot["containers"]["store"]["medicine"] = 99
	runner.assert_eq(inventory.quantity("store", "medicine"), 2, "snapshot does not alias inventory")


func _test_permissions_and_succession(runner: Object) -> void:
	var book := InstitutionBook.new()
	book.add_institution(
		"sect",
		{
			"recorder": {"holder": "old_elder", "permissions": ["record"]},
			"treasurer": {"holder": "keeper", "permissions": ["pay"]},
		}
	)
	runner.assert_true(
		not book.issue("unauthorized", "sect", "stranger", "disciple", 4, "job"),
		"reject unauthorized issue"
	)
	runner.assert_true(
		not book.issue("no_evidence", "sect", "old_elder", "disciple", 4, ""), "require issue evidence"
	)
	runner.assert_true(
		book.issue("award", "sect", "old_elder", "disciple", 4, "job_1"), "record award"
	)
	runner.assert_true(
		not book.debit("wrong_role", "sect", "old_elder", "disciple", 1, "request"),
		"recording is not payment authority"
	)
	runner.assert_true(
		not book.debit("overspend", "sect", "keeper", "disciple", 5, "request"),
		"cannot debit above balance"
	)
	runner.assert_true(book.appoint("sect", "recorder", "new_elder"), "replace recorder")
	runner.assert_eq(
		book.balance("sect", "disciple"), 4, "office succession keeps institutional balance"
	)
	runner.assert_eq(book.entries[0]["issuer"], "old_elder", "old signature remains attributable")
	runner.assert_eq(book.entries[0]["office"], "recorder", "entry retains signing office")
	runner.assert_true(
		not book.has_permission("sect", "old_elder", "record"), "old holder loses current authority"
	)
	runner.assert_true(
		not book.issue("old_new_award", "sect", "old_elder", "disciple", 1, "job_2"),
		"former office holder cannot sign anew"
	)
	runner.assert_true(
		book.issue("award", "sect", "old_elder", "disciple", 4, "job_1"),
		"completed award retries after succession"
	)
	runner.assert_true(
		not book.issue("award", "sect", "new_elder", "disciple", 4, "job_1"),
		"reject altered award signature"
	)
	runner.assert_true(
		book.debit("redeem", "sect", "keeper", "disciple", 3, "medicine"), "authorized debit"
	)
	runner.assert_true(
		book.debit("redeem", "sect", "keeper", "disciple", 3, "medicine"), "debit retry"
	)
	runner.assert_eq(book.balance("sect", "disciple"), 1, "debit applies once")
	runner.assert_eq(book.entries.size(), 2, "only successful operations create entries")
	book.appoint("sect", "treasurer", "")
	runner.assert_true(
		not book.has_permission("sect", "", "pay"), "vacant offices grant nobody permission"
	)


func _test_institution_snapshot_validation(runner: Object) -> void:
	var book := InstitutionBook.new()
	book.add_institution("sect", {"elder": {"holder": "old", "permissions": ["record", "pay"]}})
	book.issue("award", "sect", "old", "disciple", 5, "job")
	book.debit("redeem", "sect", "old", "disciple", 2, "food")
	book.appoint("sect", "elder", "new")
	var snapshot: Dictionary = book.to_dict()
	var restored := InstitutionBook.new()
	var json_snapshot: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	runner.assert_true(
		restored.restore(json_snapshot), "institution JSON snapshot restores after succession"
	)
	runner.assert_eq(restored.to_dict(), snapshot, "institution roundtrip preserves history")
	runner.assert_true(
		restored.debit("redeem", "sect", "old", "disciple", 2, "food"), "debit idempotency survives load"
	)
	var damaged: Dictionary = snapshot.duplicate(true)
	damaged["entries"][0]["amount"] = -1
	runner.assert_true(not restored.restore(damaged), "reject negative institutional entry")
	damaged = snapshot.duplicate(true)
	damaged["entries"][0]["institution_id"] = "missing"
	runner.assert_true(not restored.restore(damaged), "reject orphan institutional entry")
	damaged = snapshot.duplicate(true)
	damaged["entries"][0]["office"] = "missing"
	runner.assert_true(not restored.restore(damaged), "reject missing signing office")
	damaged = snapshot.duplicate(true)
	damaged["operations"].erase("award")
	runner.assert_true(not restored.restore(damaged), "reject missing idempotency record")
	damaged = snapshot.duplicate(true)
	damaged["entries"][1]["amount"] = 6
	damaged["operations"]["redeem"]["amount"] = 6
	runner.assert_true(not restored.restore(damaged), "reject snapshot with account overdraft")
	runner.assert_eq(
		restored.to_dict(), snapshot, "damaged institutional snapshots do not mutate book"
	)


func _test_empty_operations_and_incomplete_snapshots(runner: Object) -> void:
	var inventory := Inventory.new()
	inventory.create_container("store", {"food": 3})
	inventory.create_container("bag", {})
	var inventory_before: Dictionary = inventory.to_dict()
	runner.assert_true(
		not inventory.transfer("", "store", "bag", "food", 1), "transfer requires operation id"
	)
	runner.assert_true(
		not inventory.consume(" ", "store", "food", 1), "consume rejects whitespace operation id"
	)
	runner.assert_eq(inventory.to_dict(), inventory_before, "invalid ids do not change inventory")
	var damaged: Dictionary = inventory_before.duplicate(true)
	damaged.erase("operations")
	runner.assert_true(not inventory.restore(damaged), "inventory rejects incomplete snapshot")
	damaged = inventory_before.duplicate(true)
	damaged["operations"][""] = {
		"kind": "consume", "container": "store", "item": "food", "amount": 1
	}
	runner.assert_true(not inventory.restore(damaged), "inventory rejects empty stored operation id")
	runner.assert_eq(
		inventory.to_dict(), inventory_before, "incomplete inventory cannot replace state"
	)
	var book := InstitutionBook.new()
	book.add_institution("sect", {"elder": {"holder": "elder", "permissions": ["record", "pay"]}})
	var book_before: Dictionary = book.to_dict()
	runner.assert_true(
		not book.issue("", "sect", "elder", "disciple", 1, "job"), "issue requires operation id"
	)
	runner.assert_true(
		not book.debit(" ", "sect", "elder", "disciple", 1, "food"),
		"debit rejects whitespace operation id"
	)
	damaged = book_before.duplicate(true)
	damaged.erase("entries")
	runner.assert_true(not book.restore(damaged), "institution rejects incomplete snapshot")
	runner.assert_eq(book.to_dict(), book_before, "invalid institutional input cannot change state")


func _test_save_store(runner: Object) -> void:
	var random := RandomNumberGenerator.new()
	random.randomize()
	var directory: String = "user://test_sim_ledgers_%d_%d" % [Time.get_ticks_usec(), random.randi()]
	var path: String = directory.path_join("snapshot.json")
	var first: Dictionary = {"version": 1, "tick": 7, "state": {"food": 3}}
	var second: Dictionary = {"version": 1, "tick": 8, "state": {"food": 2}}
	var first_json: Dictionary = JSON.parse_string(JSON.stringify(first))
	var second_json: Dictionary = JSON.parse_string(JSON.stringify(second))
	runner.assert_eq(
		SaveStore.save_file(path, first), OK, "save creates directory and writes snapshot"
	)
	var loaded: Dictionary = SaveStore.load_file(path)
	runner.assert_true(loaded["ok"], "load written snapshot succeeds")
	runner.assert_eq(loaded["data"], first_json, "JSON file roundtrip retains snapshot")
	runner.assert_eq(SaveStore.save_file(path, second), OK, "save replaces previous snapshot")
	runner.assert_eq(SaveStore.load_file(path)["data"], second_json, "primary holds newest state")
	runner.assert_eq(SaveStore.load_file(path + ".bak")["data"], first_json, "backup holds previous state")
	runner.assert_eq(
		SaveStore.save_file(path, {"bad": INF}), ERR_INVALID_DATA, "save rejects non-finite numbers"
	)
	runner.assert_eq(
		SaveStore.load_file(path)["data"], second_json, "invalid data leaves primary unchanged"
	)
	var temporary: String = ProjectSettings.globalize_path(path + ".tmp")
	runner.assert_eq(DirAccess.make_dir_absolute(temporary), OK, "create owned write failure fixture")
	runner.assert_true(SaveStore.save_file(path, first) != OK, "write failure returns an error")
	runner.assert_eq(SaveStore.load_file(path)["data"], second_json, "write failure preserves primary")
	runner.assert_eq(
		SaveStore.load_file(path + ".bak")["data"], first_json, "write failure preserves backup"
	)
	DirAccess.remove_absolute(temporary)
	var malformed_path: String = directory.path_join("malformed.json")
	var fixture: FileAccess = FileAccess.open(malformed_path, FileAccess.WRITE)
	runner.assert_not_null(fixture, "open owned malformed JSON fixture")
	if fixture != null:
		fixture.store_string("{broken")
		fixture.close()
		var malformed: Dictionary = SaveStore.load_file(malformed_path)
		runner.assert_true(not malformed["ok"], "malformed JSON cannot report success")
		runner.assert_true(malformed["error"] != OK, "malformed JSON includes error code")
		runner.assert_true(not String(malformed["message"]).is_empty(), "malformed JSON explains failure")
		fixture = FileAccess.open(malformed_path, FileAccess.WRITE)
		if fixture != null:
			fixture.store_string("[]")
			fixture.close()
			runner.assert_true(not SaveStore.load_file(malformed_path)["ok"], "array top level rejected")
	var absent: Dictionary = SaveStore.load_file(directory.path_join("absent.json"))
	runner.assert_true(not absent["ok"] and absent["error"] != OK, "missing file is not empty success")
	# Only this test's exact randomly named files and empty directory are removed.
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		var owned_path: String = ProjectSettings.globalize_path(path + suffix)
		if FileAccess.file_exists(owned_path):
			DirAccess.remove_absolute(owned_path)
	if FileAccess.file_exists(malformed_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(malformed_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
