@tool
class_name CombatEntityDef
extends Resource
const Bundle = preload("res://scripts/sim/definitions/actions/effect_bundle_def.gd")
@export_enum("companion", "static") var body: String = "companion"
@export var group: String = "companion"
@export_range(1, 4) var limit: int = 1
@export_range(500, 60000) var lifetime_ms: int = 12000
@export_range(1, 10000) var max_hp: int = 80
@export_range(0.1, 20.0) var speed: float = 6.0
@export_range(0, 1000) var damage: int = 12
@export var loadout: String = "light"
@export_enum("follow", "hold") var stance: String = "follow"
@export_range(0.0, 10.0) var aura_radius: float = 0.0
@export var aura: Bundle = Bundle.new()
@export var pulse: Bundle = Bundle.new()
@export_range(50, 5000) var period_ms: int = 500
func values() -> Dictionary:
	return {"body": body, "group": group, "limit": limit, "life": lifetime_ms, "max_hp": max_hp, "speed": speed, "damage": damage,
		"loadout": loadout, "stance": stance, "radius": aura_radius, "aura": aura.values() if aura != null else [], "pulse": pulse.values() if pulse != null else [], "period": period_ms}
func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if body not in ["companion", "static"] or not group.is_valid_identifier() or limit < 1 or limit > 4 or lifetime_ms < 500 or lifetime_ms > 60000 or max_hp < 1 or max_hp > 10000 or damage < 0 or damage > 1000: result.append("entity: invalid identity/body/limits")
	if stance not in ["follow", "hold"]: result.append("stance: expected follow/hold")
	if not is_finite(speed) or speed <= 0 or speed > 20 or not is_finite(aura_radius) or aura_radius < 0 or aura_radius > 10 or period_ms < 50 or period_ms > 5000: result.append("entity: invalid movement/aura/period")
	for bundle: Bundle in [aura, pulse]:
		if bundle == null: result.append("entity: required bundle"); continue
		for error: String in bundle.errors(): result.append(error)
	if aura != null:
		for effect: Resource in aura.effects:
			if effect != null and (effect.kind != "status" or effect.status == null or effect.status.kind not in ["modifier", "haste", "slow"]): result.append("aura: use persistent modifier/haste/slow status; put other effects in pulse")
	return result
