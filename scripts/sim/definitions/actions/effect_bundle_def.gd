@tool
class_name ActionEffectBundle
extends Resource
## Bounded synchronous operations. Time and mutable state belong to delivery hosts.
const Effect = preload("res://scripts/sim/definitions/actions/effect_def.gd")
@export var effects: Array[Effect] = []

func values() -> Array:
	var result: Array = []
	for effect: Effect in effects: result.append(effect.values())
	return result

func errors(required_stage: String = "") -> PackedStringArray:
	var result := PackedStringArray()
	if effects.size() > 16: result.append("effects: at most 16 synchronous operations")
	var once: Dictionary = {}
	for index: int in effects.size():
		var effect: Effect = effects[index]
		if effect == null: result.append("effects[%d]: missing resource" % index); continue
		for error: String in effect.errors(required_stage): result.append("effects[%d].%s" % [index, error])
		var key: String = effect.stage + ":" + effect.kind + ":" + effect.status_id
		if once.has(key): result.append("effects[%d]: duplicate operation %s" % [index, key])
		once[key] = true
	return result
