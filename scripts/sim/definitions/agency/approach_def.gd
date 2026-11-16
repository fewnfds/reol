@tool
class_name LifeApproachDef
extends Resource
## A finite way of pursuing a goal. Actual actions remain Operations/hosts.
@export var id: String = ""
@export var title: String = ""
@export_enum("perform", "produce", "develop", "deliver", "return", "responsibility", "duty", "service", "reporting") var pattern: String = "perform"
@export var handler: String = ""
@export var product: String = ""
@export_enum("self", "known", "either", "goal") var targets: String = "known"
@export_range(0.1, 1.0) var confidence: float = 1.0
@export var prerequisites: bool = true

func values() -> Dictionary:
	return {"id": id, "title": title, "pattern": pattern, "handler": handler, "product": product,
		"targets": targets, "confidence": confidence, "prerequisites": prerequisites}

func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if not id.is_valid_identifier() or title.is_empty(): result.append("approach id/title: required")
	if pattern not in ["perform", "produce", "develop", "deliver", "return", "responsibility", "duty", "service", "reporting"]: result.append("approach pattern: unsupported")
	if targets not in ["self", "known", "either", "goal"]: result.append("approach target source: unsupported")
	if not is_finite(confidence) or confidence < 0.1 or confidence > 1.0: result.append("approach confidence: out of range")
	if pattern == "perform" and not handler.is_valid_identifier() and not (handler.is_empty() and targets == "goal"): result.append("perform: handler or explicit goal operation required")
	if pattern != "perform" and not handler.is_empty(): result.append("handler: only used by perform")
	if pattern == "produce":
		if not preload("res://scripts/sim/kernel/items.gd").valid(product): result.append("produce: known item required")
	elif not product.is_empty(): result.append("product: only used by produce")
	return result
