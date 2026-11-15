@tool
class_name ActionStatusDef
extends Resource
## Reusable state lifetime. Periods remain in the Effects host, never SceneTree timers.
@export var id: String = ""
@export_enum("slow", "dot", "root", "stun", "haste", "modifier", "mark", "suppression") var kind: String = "slow"
@export_range(1, 60000) var duration_ms: int = 2000
@export_range(0, 10000) var period_ms: int = 0
@export_range(0.0, 100.0) var magnitude: float = 0.65
@export_enum("refresh", "stack", "replace", "independent") var stacking: String = "refresh"
@export_range(1, 16) var max_stacks: int = 1
@export_range(1, 32) var max_instances: int = 8
@export_enum("max_hp", "melee", "ranged", "armor", "speed") var attribute: String = "armor"
@export_enum("add", "multiply") var modifier: String = "add"
@export_enum("source", "chain", "activation") var isolation: String = "source"
@export var dispellable: bool = true
@export var tags: PackedStringArray = PackedStringArray()
@export var suppressed_tags: PackedStringArray = PackedStringArray()
func values() -> Dictionary:
	return {"id": id, "kind": kind, "duration_ms": duration_ms, "period_ms": period_ms, "magnitude": magnitude,
		"stacking": stacking, "max_stacks": max_stacks, "max_instances": max_instances, "attribute": attribute, "modifier": modifier, "dispellable": dispellable, "isolation": isolation, "tags": tags, "suppressed_tags": suppressed_tags}
func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if not id.is_valid_identifier() or kind not in ["slow", "dot", "root", "stun", "haste", "modifier", "mark", "suppression"]: result.append("status: invalid id/kind")
	if duration_ms < 1 or duration_ms > 60000 or period_ms < 0 or period_ms > 10000 or not is_finite(magnitude) or magnitude < 0 or magnitude > 100: result.append("status: invalid duration/period/magnitude")
	if kind == "dot" and (period_ms < 50 or period_ms > duration_ms): result.append("period_ms: dot requires 50..duration")
	if kind == "slow" and (magnitude <= 0 or magnitude > 1): result.append("magnitude: slow requires (0,1]")
	if kind == "haste" and (magnitude < 1 or magnitude > 3): result.append("magnitude: haste requires 1..3")
	if stacking not in ["refresh", "stack", "replace", "independent"] or max_stacks < 1 or max_stacks > 16: result.append("stacking: invalid policy/limit")
	if max_instances < 1 or max_instances > 32: result.append("max_instances: expected 1..32 per source/target/status")
	if isolation not in ["source", "chain", "activation"]: result.append("isolation: invalid source scope")
	if attribute not in ["max_hp", "melee", "ranged", "armor", "speed"] or modifier not in ["add", "multiply"]: result.append("modifier: invalid attribute/operation")
	for labels: PackedStringArray in [tags, suppressed_tags]:
		if labels.size() > 16: result.append("tags: expected at most 16 labels")
		var seen: Dictionary = {}
		for label: String in labels:
			if label.length() > 48 or not label.is_valid_identifier() or seen.has(label): result.append("tags: expected unique identifiers of at most 48 characters")
			seen[label] = true
	if kind == "suppression" and (suppressed_tags.is_empty() or period_ms != 0): result.append("suppression: requires suppressed tags and no periodic tick")
	if kind != "suppression" and not suppressed_tags.is_empty(): result.append("suppressed_tags: only a suppression status can filter contributions")
	return result
