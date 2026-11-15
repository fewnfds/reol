@tool
class_name ActionReactionDef
extends Resource
const Bundle = preload("res://scripts/sim/definitions/actions/effect_bundle_def.gd")
@export var id: String = ""
@export_enum("hit", "damaged", "killed", "blocked", "shield_broken", "gathered", "timer", "expired", "stack_max") var event: String = "hit"
@export_enum("bundle", "emit", "request", "spread", "script") var mode: String = "bundle"
@export_enum("source", "target") var recipient: String = "source"
@export var bundle: Bundle = Bundle.new()
@export var template: String = ""
@export_enum("owned_marks") var script_id: String = "owned_marks"
@export_range(0.0, 1.0) var chance: float = 1.0
@export_range(1, 100) var every: int = 1
@export_range(0, 60000) var interval_ms: int = 0
@export_range(0, 15000) var delay_ms: int = 0
@export_range(1, 16) var count: int = 1
@export_range(0.0, 6.283185) var spread: float = 0.3
@export_range(0.0, 20.0) var radius: float = 3.0
@export_range(0.0, 5.0) var scale: float = 1.0
@export_range(0.0, 1.0) var health_leech: float = 0.0
@export_range(1, 32) var chain_limit: int = 8
@export_range(1, 6) var max_depth: int = 3
@export var consume_delivery: bool = false
@export var status_id: String = ""
func values() -> Dictionary:
	return {"id": id, "event": event, "mode": mode, "recipient": recipient, "bundle": bundle.values() if bundle != null else [], "template": template,
		"script_id": script_id, "chance": chance, "every": every, "interval_ms": interval_ms, "delay_ms": delay_ms, "count": count, "spread": spread,
		"radius": radius, "scale": scale, "health_leech": health_leech, "chain_limit": chain_limit, "max_depth": max_depth, "status_id": status_id, "consume_delivery": consume_delivery}
func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if not id.is_valid_identifier() or event not in ["hit", "damaged", "killed", "blocked", "shield_broken", "gathered", "timer", "expired", "stack_max"] or mode not in ["bundle", "emit", "request", "spread", "script"] or recipient not in ["source", "target"]: result.append("reaction: invalid identity/event/mode/recipient")
	if bundle == null: result.append("bundle: required")
	else:
		for error: String in bundle.errors("contact"): result.append(error)
	if every < 1 or every > 100 or interval_ms < 0 or interval_ms > 60000 or delay_ms < 0 or delay_ms > 15000 or count < 1 or count > 16 or chain_limit < 1 or chain_limit > 32 or max_depth < 1 or max_depth > 6: result.append("reaction: invalid limits")
	for pair: Array in [[chance, 1.0], [spread, TAU], [radius, 20.0], [scale, 5.0], [health_leech, 1.0]]:
		if not is_finite(pair[0]) or pair[0] < 0 or pair[0] > pair[1]: result.append("reaction: invalid probability/geometry/scale")
	if mode in ["emit", "request"] and template.is_empty(): result.append("template: required")
	if mode == "script" and script_id != "owned_marks": result.append("script_id: unregistered trusted script")
	if mode == "spread" and status_id.is_empty(): result.append("status_id: required")
	return result

## The same template policy applies to authoring and restored reaction rules.
static func template_error(rule: Dictionary, actions: Dictionary) -> String:
	if rule.mode not in ["emit", "request"]: return ""
	if not actions.has(rule.template): return "unknown template " + rule.template
	if rule.mode == "emit" and actions[rule.template].delivery.kind not in ["projectile", "area"]: return "emit requires projectile/area; use request for a full action"
	return ""
