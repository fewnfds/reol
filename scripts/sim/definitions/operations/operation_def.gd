@tool
class_name OperationDef
extends Resource
const Target = preload("res://scripts/sim/definitions/operations/target_rule.gd")
const Cost = preload("res://scripts/sim/definitions/actions/cost_def.gd")
const Bundle = preload("res://scripts/sim/definitions/actions/effect_bundle_def.gd")
const Form = preload("res://scripts/sim/definitions/beings/form_def.gd")
const HANDLERS: Dictionary = {"transfer": ["take", "put"], "facility": ["construct", "rest", "cook", "eat", "demolish"],
	"nature": ["sow", "tend", "gather", "cut", "uproot"], "society": ["talk", "trade", "request_help", "learn", "study", "practice"],
	"instant": ["self_effect"], "work_source": ["harvest"]}
@export var id: String = ""
@export var title: String = ""
@export var icon: String = "work"
@export var command_alias: String = ""
@export_enum("transfer", "facility", "nature", "society", "instant", "work_source") var executor: String = "facility"
@export var handler: String = ""
@export var required_capabilities: PackedStringArray = []
@export var targets: Array[Target] = []
## -1: remaining labor on the target; 0: synchronous self effect.
@export_range(-1, 300000) var duration_ms: int = 1000
@export var exclusive: bool = true
@export var target_menu: bool = true
@export var required_items: Dictionary[String, int] = {}
@export var required_method: String = ""
@export var required_ability: String = ""
@export var learning_method: String = ""
@export_range(0, 100000) var learning_points: int = 0
## Practical work may consume mastery independently of awarding learning.
@export var duration_method: String = ""
@export var injured: bool = false
@export var actor_inventory: bool = false
@export var help_target: bool = false
@export var costs: Array[Cost] = []
@export var effects: Bundle

func values() -> Dictionary:
	var rules: Array = []
	for target: Target in targets: rules.append(target.values())
	var payments: Array = []
	for cost: Cost in costs: payments.append(cost.values())
	return {"id": id, "title": title, "icon": icon, "command_alias": command_alias, "executor": executor, "handler": handler,
		"required_capabilities": Array(required_capabilities), "targets": rules, "duration_ms": duration_ms, "exclusive": exclusive,
		"target_menu": target_menu, "required_items": required_items.duplicate(), "required_method": required_method,
		"required_ability": required_ability, "learning_method": learning_method, "learning_points": learning_points, "duration_method": duration_method, "injured": injured, "actor_inventory": actor_inventory, "help_target": help_target,
		"costs": payments, "effects": effects.values() if effects != null else []}

func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if not id.is_valid_identifier() or title.is_empty(): result.append("id/title: required")
	# Only this existing UI adapter distinguishes placing a blueprint from
	# working on it. Arbitrary aliases would bypass the declared operation.
	if not command_alias.is_empty() and (id != "construct" or command_alias != "continue_build"): result.append("command alias: unsupported adapter")
	if id == "construct" and command_alias != "continue_build": result.append("construct: requires existing blueprint adapter")
	if id in ["action_trace", "journey", "ability", "action", "body", "move", "interrupt", "work", "heal", "equip", "unequip", "source", "plant", "weather", "drop", "build", "save", "load", "combat_practice", "continue_build"]: result.append("id: reserved command")
	if not HANDLERS.get(executor, []).has(handler): result.append("executor/handler: unsupported domain operation")
	if duration_ms < -1 or duration_ms > 300000 or ((duration_ms == 0) != (executor == "instant")): result.append("duration: unsupported host")
	if (duration_ms == -1) != (handler in ["construct", "sow"]): result.append("remaining labor: requires construct/sow host")
	if executor == "work_source" and id != "harvest": result.append("work source: only the current harvest host is registered")
	if executor == "work_source" and (target_menu or not exclusive): result.append("work source: legacy host requires exclusive work and no direct menu")
	if executor == "instant" and exclusive: result.append("instant: cannot own a timed occupation")
	if executor == "instant" and (effects == null or effects.effects.is_empty()): result.append("instant: effects required")
	if help_target != (handler == "request_help"): result.append("help target: requires request_help adapter")
	for key: String in [required_method, required_ability]:
		if not key.is_empty() and not key.is_valid_identifier(): result.append("identifier: invalid")
	var growth: Script = preload("res://scripts/sim/kernel/growth_defs.gd")
	if not required_method.is_empty() and not growth.METHODS.has(required_method): result.append("required method: unknown")
	if learning_method.is_empty() != (learning_points == 0) or learning_points < 0 or learning_points > 100000: result.append("learning: inconsistent method/points")
	if not learning_method.is_empty() and (not growth.METHODS.has(learning_method) or handler not in ["learn", "study", "practice", "cook"]): result.append("learning: unsupported method/consumer")
	if handler in ["learn", "study", "practice"] and learning_method.is_empty(): result.append("learning: method required")
	if handler == "practice" and required_method != learning_method: result.append("practice: admission method must match practiced method")
	if handler == "practice" and growth.METHODS.has(learning_method) and (growth.METHODS[learning_method].energy_cost > 0 or growth.METHODS[learning_method].satiety_cost > 0) and not required_capabilities.has("metabolism"): result.append("practice: body costs require metabolism")
	if handler in ["cook", "practice"] and growth.METHODS.has(learning_method) and growth.METHODS[learning_method].requires_introduction and required_method != learning_method: result.append("learning: practical consumer must require introduction")
	if handler == "study" and growth.METHODS.has(learning_method) and growth.METHODS[learning_method].study_item.is_empty(): result.append("study: method has no readable source")
	if not duration_method.is_empty() and (not growth.METHODS.has(duration_method) or handler != "cook"): result.append("duration method: requires known method and practical work consumer")
	for capability: String in required_capabilities:
		if not Form.CAPABILITIES.has(capability): result.append("capability: unknown")
	if targets.is_empty() or targets.size() > 6: result.append("targets: require 1..6 alternatives")
	for target: Target in targets:
		if target == null: result.append("target: required"); continue
		result.append_array(target.errors())
		if executor == "instant" and target.relation != "self": result.append("instant: only self targets supported")
	for item: String in required_items:
		if not preload("res://scripts/sim/kernel/items.gd").valid(item) or required_items[item] <= 0: result.append("required item: invalid")
	if executor != "instant" and (not costs.is_empty() or effects != null): result.append("timed effects/costs belong to domain commit")
	if costs.size() > 8: result.append("costs: at most 8")
	for cost: Cost in costs:
		if cost == null: result.append("cost: required"); continue
		result.append_array(cost.errors())
	if effects != null:
		result.append_array(effects.errors("activation"))
		# Synchronous self effects use P4 owners; domain commands and delayed
		# deliveries require an explicit host, not an unvalidated payment callback.
		for effect: Resource in effects.effects:
			if effect != null and effect.kind not in ["heal", "resource", "shield", "status", "dispel"]: result.append("instant effect: unsupported host")
	return result
