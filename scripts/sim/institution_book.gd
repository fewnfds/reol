class_name SimInstitutionBook
extends RefCounted
## Institutional accounts outlive an office holder. Entries retain who signed
## and which office authorized the signature at the time of the decision.

const MAX_COUNT: int = 9007199254740991  # Largest exact integer in JSON numbers.

var institutions: Dictionary = {}
var entries: Array[Dictionary] = []
var operations: Dictionary = {}


func add_institution(id: String, offices: Dictionary) -> bool:
	if not _nonempty(id) or institutions.has(id) or not _valid_offices(offices):
		return false
	institutions[id] = {"offices": offices.duplicate(true)}
	return true


func appoint(institution_id: String, office: String, holder: String) -> bool:
	if not institutions.has(institution_id):
		return false
	var offices: Dictionary = institutions[institution_id]["offices"]
	if not offices.has(office) or (not holder.is_empty() and not _nonempty(holder)):
		return false
	offices[office]["holder"] = holder
	return true


func has_permission(institution_id: String, actor: String, permission: String) -> bool:
	return not _office_for_permission(institution_id, actor, permission).is_empty()


func issue(
	operation_id: String,
	institution_id: String,
	issuer: String,
	subject: String,
	amount: int,
	evidence: String
) -> bool:
	return _post(operation_id, institution_id, issuer, subject, amount, evidence, "issue")


func balance(institution_id: String, subject: String) -> int:
	var result: int = 0
	for entry: Dictionary in entries:
		if entry["institution_id"] == institution_id and entry["subject"] == subject:
			var amount: int = int(entry["amount"])
			result += amount if entry["kind"] == "issue" else -amount
	return result


func debit(
	operation_id: String,
	institution_id: String,
	issuer: String,
	subject: String,
	amount: int,
	evidence: String
) -> bool:
	return _post(operation_id, institution_id, issuer, subject, amount, evidence, "debit")


func to_dict() -> Dictionary:
	return {
		"institutions": institutions.duplicate(true),
		"entries": entries.duplicate(true),
		"operations": operations.duplicate(true),
	}


func restore(data: Dictionary) -> bool:
	var raw_institutions: Variant = data.get("institutions")
	var raw_entries: Variant = data.get("entries")
	var raw_operations: Variant = data.get("operations")
	if (
		not raw_institutions is Dictionary
		or not raw_entries is Array
		or not raw_operations is Dictionary
	):
		return false
	var next_institutions: Dictionary = {}
	for id: Variant in raw_institutions:
		if not _nonempty(id) or not raw_institutions[id] is Dictionary:
			return false
		var institution: Dictionary = raw_institutions[id]
		if institution.size() != 1 or not institution.get("offices") is Dictionary:
			return false
		if not _valid_offices(institution["offices"]):
			return false
		next_institutions[id] = institution.duplicate(true)
	var next_entries: Array[Dictionary] = []
	var next_operations: Dictionary = {}
	var balances: Dictionary = {}
	for value: Variant in raw_entries:
		if not value is Dictionary:
			return false
		var entry: Dictionary = value
		if not _valid_entry(entry, next_institutions):
			return false
		var id: String = entry["operation_id"]
		if next_operations.has(id) or not raw_operations.get(id) is Dictionary:
			return false
		var request: Dictionary = _request_from_entry(entry)
		var recorded_request: Dictionary = raw_operations[id].duplicate(true)
		if not _valid_count(recorded_request.get("amount")):
			return false
		recorded_request["amount"] = int(recorded_request["amount"])
		if recorded_request != request:
			return false
		var institution_id: String = entry["institution_id"]
		var subject: String = entry["subject"]
		var institution_balances: Dictionary = balances.get(institution_id, {})
		var previous: int = int(institution_balances.get(subject, 0))
		var amount: int = int(entry["amount"])
		if entry["kind"] == "debit":
			if previous < amount:
				return false
			institution_balances[subject] = previous - amount
		else:
			if amount > MAX_COUNT - previous:
				return false
			institution_balances[subject] = previous + amount
		balances[institution_id] = institution_balances
		var normalized_entry: Dictionary = entry.duplicate(true)
		normalized_entry["amount"] = amount
		next_entries.append(normalized_entry)
		next_operations[id] = request
	if next_operations.size() != raw_operations.size():
		return false
	institutions = next_institutions
	entries = next_entries
	operations = next_operations
	return true


func _post(
	operation_id: String,
	institution_id: String,
	issuer: String,
	subject: String,
	amount: int,
	evidence: String,
	kind: String
) -> bool:
	if not _nonempty(operation_id):
		return false
	var request: Dictionary = {
		"kind": kind,
		"institution_id": institution_id,
		"issuer": issuer,
		"subject": subject,
		"amount": amount,
		"evidence": evidence,
	}
	if operations.has(operation_id):
		return operations[operation_id] == request
	if not _nonempty(subject) or not _nonempty(evidence) or not _valid_count(amount):
		return false
	var permission: String = "record" if kind == "issue" else "pay"
	var office: String = _office_for_permission(institution_id, issuer, permission)
	if office.is_empty():
		return false
	var current: int = balance(institution_id, subject)
	if kind == "debit" and current < amount:
		return false
	if kind == "issue" and amount > MAX_COUNT - current:
		return false
	var entry: Dictionary = request.duplicate(true)
	entry["operation_id"] = operation_id
	entry["office"] = office
	entries.append(entry)
	operations[operation_id] = request
	return true


func _office_for_permission(institution_id: String, actor: String, permission: String) -> String:
	if not institutions.has(institution_id) or not _nonempty(actor) or not _nonempty(permission):
		return ""
	var offices: Dictionary = institutions[institution_id]["offices"]
	var names: Array = offices.keys()
	names.sort()
	for name: String in names:
		var office: Dictionary = offices[name]
		if office["holder"] == actor and office["permissions"].has(permission):
			return name
	return ""


static func _nonempty(value: Variant) -> bool:
	return value is String and not String(value).strip_edges().is_empty()


static func _valid_count(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number == floorf(number) and number >= 1 and number <= MAX_COUNT


static func _valid_offices(offices: Dictionary) -> bool:
	for id: Variant in offices:
		if not _nonempty(id) or not offices[id] is Dictionary:
			return false
		var office: Dictionary = offices[id]
		if (
			office.size() != 2
			or not office.get("holder") is String
			or not office.get("permissions") is Array
		):
			return false
		var holder: String = office["holder"]
		if not holder.is_empty() and not _nonempty(holder):
			return false
		var seen: Dictionary = {}
		for permission: Variant in office["permissions"]:
			if not _nonempty(permission) or seen.has(permission):
				return false
			seen[permission] = true
	return true


static func _valid_entry(entry: Dictionary, known_institutions: Dictionary) -> bool:
	if entry.size() != 8 or not _nonempty(entry.get("operation_id")):
		return false
	if entry.get("kind") != "issue" and entry.get("kind") != "debit":
		return false
	if (
		not _nonempty(entry.get("institution_id"))
		or not known_institutions.has(entry["institution_id"])
		or not _nonempty(entry.get("issuer"))
		or not _nonempty(entry.get("subject"))
		or not _nonempty(entry.get("evidence"))
		or not _nonempty(entry.get("office"))
		or not _valid_count(entry.get("amount"))
	):
		return false
	var offices: Dictionary = known_institutions[entry["institution_id"]]["offices"]
	return offices.has(entry["office"])


static func _request_from_entry(entry: Dictionary) -> Dictionary:
	return {
		"kind": entry["kind"],
		"institution_id": entry["institution_id"],
		"issuer": entry["issuer"],
		"subject": entry["subject"],
		"amount": int(entry["amount"]),
		"evidence": entry["evidence"],
	}
