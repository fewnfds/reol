extends RefCounted
## Minimal persistent owner for registry contract tests, without world setup.
var amount: int = 0
var note: String = ""
var bound_total: int = -1


func to_dict() -> Dictionary:
	if amount < 0:
		return {}
	return {"amount": amount, "note": note}


func restore(data: Dictionary) -> bool:
	if not data.get("amount") is int or not data.get("note") is String:
		return false
	amount = data.amount
	note = data.note
	return true


func bind_world(host: Object) -> void:
	bound_total = host.first.amount + host.second.amount
