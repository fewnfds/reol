@tool
class_name InstitutionLibrary
extends Resource
const Role = preload("res://scripts/sim/definitions/institutions/role_def.gd")
@export var roles: Array[Role] = []

func compile() -> Dictionary:
	var result: Dictionary = {"roles": {}, "errors": PackedStringArray()}
	for role: Role in roles:
		if role == null: result.errors.append("null institution role"); continue
		result.errors.append_array(role.errors())
		if result.roles.has(role.id): result.errors.append("duplicate institution role: " + role.id)
		else: result.roles[role.id] = role.values()
	return result
