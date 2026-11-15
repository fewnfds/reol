@tool
extends VBoxContainer
## Native Resource diagnostics and reference navigation. Never executes a World.
const Items = preload("res://scripts/sim/kernel/items.gd")
var definition: Resource
var _messages := Label.new()
var _references := VBoxContainer.new()

func _ready() -> void:
	custom_minimum_size.x = 260
	var check := Button.new()
	check.text = "校验定义与引用"
	add_child(check)
	_messages.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_messages.add_theme_font_size_override("font_size", 12)
	add_child(_messages)
	add_child(_references)
	check.pressed.connect(refresh)
	refresh()

func refresh() -> void:
	if definition == null: return
	var errors: PackedStringArray = definition.call("compile").errors if definition.has_method("compile") else definition.call("errors")
	var library: Resource = load("res://data/definitions/combat/library.tres")
	if library == null: errors.append("library: 技能库无法加载")
	else: _check_references(definition, library, errors, "", {})
	var fields: Array[String] = []
	for property: Dictionary in definition.get_property_list():
		if property.usage & PROPERTY_USAGE_EDITOR != 0: fields.append(property.name)
	for child: Node in _references.get_children():
		_references.remove_child(child)
		child.queue_free()
	for field: String in fields:
		if field == "script": continue
		var value: Variant = definition.get(field)
		if value is Resource: _link(field, value)
		elif value is Array:
			for index: int in value.size():
				if value[index] is Resource: _link("%s[%d]" % [field, index], value[index])
		elif value is String and field in ["primary", "skill", "skill2", "skill3", "step", "next_action", "template", "emitter", "loadout"] and not value.is_empty():
			if library != null:
				var target: Resource = _target(library, field, value)
				if target != null: _link(field + " → " + value, target)
	_messages.text = "校验通过。保存后重新运行试玩；可点击下方引用继续编辑。" if errors.is_empty() else "\n".join(errors)
	_messages.modulate = Color("a9d6bd") if errors.is_empty() else Color("f0a18e")
	_messages.tooltip_text = definition.resource_path + "\n" + _messages.text

func _target(library: Resource, field: String, id: String) -> Resource:
	for target: Resource in (library.loadouts if field == "loadout" else library.abilities):
		if target != null and target.id == id: return target
	return null

func _check_references(resource: Resource, library: Resource, errors: PackedStringArray, path: String, seen: Dictionary) -> void:
	if seen.has(resource): return
	seen[resource] = true
	for property: Dictionary in resource.get_property_list():
		if property.usage & PROPERTY_USAGE_EDITOR == 0 or property.name == "script": continue
		var field: String = property.name
		var value: Variant = resource.get(field)
		var location: String = path + field
		if value is Resource: _check_references(value, library, errors, location + ".", seen)
		elif value is Array:
			for index: int in value.size():
				if value[index] is Resource: _check_references(value[index], library, errors, "%s[%d]." % [location, index], seen)
		elif value is String and field in ["primary", "skill", "skill2", "skill3", "step", "next_action", "template", "emitter", "loadout"] and not value.is_empty():
			var target: Resource = _target(library, field, value)
			if target == null: errors.append(location + ": 未注册的" + ("配置 " if field == "loadout" else "技能 ") + value)
			elif field == "emitter" and (target.delivery == null or target.delivery.kind != "projectile"): errors.append(location + ": 需要投射物技能")
			elif field == "template" and resource.get("mode") == "emit" and (target.delivery == null or target.delivery.kind not in ["projectile", "area"]): errors.append(location + ": emit需要投射物或区域技能")
		elif field == "equipment" and (not Items.valid(str(value)) or Items.spec(str(value)).get("slot") != "weapon"): errors.append(location + ": 需要武器物品")
		elif field == "id" and resource.get_script() == preload("res://scripts/sim/definitions/actions/cost_def.gd") and resource.kind == "item" and not Items.valid(str(value)): errors.append(location + ": 未注册物品 " + str(value))

func _link(field: String, target: Resource) -> void:
	var button := Button.new()
	button.text = "打开 " + field
	button.tooltip_text = target.resource_path
	button.pressed.connect(func(): EditorInterface.edit_resource(target))
	_references.add_child(button)
