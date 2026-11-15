@tool
class_name CombatAbilityDef
extends Resource
const Delivery = preload("res://scripts/sim/definitions/combat/delivery_def.gd")
const Bundle = preload("res://scripts/sim/definitions/actions/effect_bundle_def.gd")
@export_group("Identity")
@export var id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
@export var tint: Color = Color("f9d384")
@export_enum("melee", "ranged") var stat: String = "melee"
@export var repeat_held: bool = false
## Zero allows every pellet to hurt; positive values protect against one volley.
@export_range(0, 5000) var hit_group_ms: int = 280
@export_group("Timing (world milliseconds)")
@export_range(0, 5000) var windup: int = 70
@export_range(1, 5000) var active: int = 60
@export_range(0, 5000) var recovery: int = 150
@export_range(0, 5000) var lock: int = 0
@export_range(0, 60000) var cooldown: int = 0
@export var cooldown_group: String = ""
@export var cost_item: String = ""
@export_range(0, 100) var cost_amount: int = 0
@export_group("Movement")
@export_range(0.0, 2.0) var move: float = 0.4
@export_range(0.0, 2.0) var free_move: float = 0.4
@export_range(0, 15000) var free_at: int = 15000
@export_range(0.0, 3.0) var lunge: float = 0.0
@export_range(0, 15000) var lunge_from: int = 0
@export_range(0, 15000) var lunge_to: int = 1
@export_range(0, 1000) var evade_ms: int = 0
@export_group("Combos and Cancels (-1 = action end)")
@export var next_action: String = ""
@export_range(0, 1000) var chain_ms: int = 300
@export var next_hit: int = -1
@export var next_miss: int = -1
@export var skill_hit: int = -1
@export var skill_miss: int = -1
@export var step_hit: int = -1
@export var step_miss: int = -1
@export_group("Enemy commitment")
@export var steady: bool = false
@export var punishable: bool = false
@export_range(0, 5000) var post: int = 0
@export_group("Delivery and Effects")
@export var delivery: Delivery
@export var bundle: Bundle = Bundle.new()

func values() -> Dictionary:
	var data: Dictionary = {"id": id, "title": title, "description": description, "tint": tint.to_html(), "stat": stat,
		"repeat": repeat_held, "group_ms": hit_group_ms, "windup": windup, "active": active, "recovery": recovery, "lock": lock,
		"cooldown": cooldown, "cd_group": cooldown_group if not cooldown_group.is_empty() else id,
		"cost_item": cost_item, "cost_amount": cost_amount, "move": move, "free_move": free_move, "free_at": free_at,
		"lunge": lunge, "lunge_from": lunge_from, "lunge_to": lunge_to, "evade_ms": evade_ms,
		"next": next_action, "chain_ms": chain_ms, "steady": steady, "punishable": punishable, "post": post,
		"delivery": delivery.values() if delivery != null else {}, "payload": bundle.values() if bundle != null else []}
	var end: int = windup + active + recovery
	for field: String in ["next_hit", "next_miss", "skill_hit", "skill_miss", "step_hit", "step_miss"]:
		data[field] = get(field) if int(get(field)) >= 0 else end
	if delivery != null and delivery.kind == "melee":
		data.reach = delivery.reach
		data.angle = delivery.half_angle
	return data

func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if not id.is_valid_identifier() or title.is_empty(): result.append("id/title: valid id and title required")
	if stat not in ["melee", "ranged"]: result.append("stat: unknown stat")
	if hit_group_ms < 0 or hit_group_ms > 5000: result.append("hit_group_ms: must be 0..5000")
	if windup < 0 or windup > 5000 or active < 1 or active > 5000 or recovery < 0 or recovery > 5000 or lock < 0 or lock > windup: result.append("timing: invalid phases/lock")
	if cooldown < 0 or cooldown > 60000 or post < 0 or post > 5000: result.append("cooldown/post: out of range")
	if cost_amount < 0 or cost_amount > 100 or (cost_amount > 0 and cost_item.is_empty()): result.append("cost: item and amount required")
	for field: String in ["move", "free_move", "lunge"]:
		if not is_finite(get(field)) or float(get(field)) < 0 or float(get(field)) > 3: result.append(field + ": out of range")
	if lunge > 0 and (lunge_from < 0 or lunge_to <= lunge_from or lunge_to > windup + active + recovery): result.append("lunge: invalid interval")
	if free_at < 0 or free_at > 15000: result.append("free_at: out of range")
	if evade_ms < 0 or evade_ms > active or chain_ms < 0 or chain_ms > 1000: result.append("evade/chain: invalid duration")
	for field: String in ["next_hit", "next_miss", "skill_hit", "skill_miss", "step_hit", "step_miss"]:
		if int(get(field)) < -1 or int(get(field)) > windup + active + recovery: result.append(field + ": outside action")
	if delivery == null: result.append("delivery: required")
	else:
		for error: String in delivery.errors(): result.append("delivery." + error)
	if bundle == null: result.append("bundle: required")
	else:
		for error: String in bundle.errors(): result.append("bundle." + error)
	return result
