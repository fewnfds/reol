extends RefCounted
## Player actions, active contexts and local preferences share one definition.
signal changed
const ACT: int = 1
const INTERACT: int = 2
const GLOBAL: int = ACT | INTERACT
const SPECS: Array[Dictionary] = [
	{"id": "act_up", "label": "向上移动", "key": KEY_W, "contexts": ACT},
	{"id": "act_down", "label": "向下移动", "key": KEY_S, "contexts": ACT},
	{"id": "act_left", "label": "向左移动", "key": KEY_A, "contexts": ACT},
	{"id": "act_right", "label": "向右移动", "key": KEY_D, "contexts": ACT},
	{"id": "act_primary", "label": "主攻击", "mouse": MOUSE_BUTTON_LEFT, "contexts": ACT},
	{"id": "act_skill", "label": "武器技", "mouse": MOUSE_BUTTON_RIGHT, "contexts": ACT},
	{"id": "act_skill2", "label": "主动技能二", "key": KEY_E, "contexts": ACT},
	{"id": "act_skill3", "label": "主动技能三", "key": KEY_C, "contexts": ACT},
	{"id": "act_step", "label": "闪步／后撤", "key": KEY_SPACE, "contexts": ACT},
	{"id": "game_heal", "label": "用药", "key": KEY_R, "contexts": ACT},
	{"id": "game_ability", "label": "已学能力", "key": KEY_Q, "contexts": ACT},
	{"id": "game_context", "label": "战斗／交互模式", "key": KEY_TAB, "contexts": GLOBAL},
	{"id": "game_interact", "label": "附近交互", "key": KEY_F, "contexts": GLOBAL},
	{"id": "game_inventory", "label": "背包", "key": KEY_I, "contexts": GLOBAL},
	{"id": "game_build_menu", "label": "营造", "key": KEY_B, "contexts": GLOBAL},
	{"id": "game_equip_sword", "label": "装备剑", "key": KEY_1, "contexts": GLOBAL},
	{"id": "game_equip_bow", "label": "装备弓", "key": KEY_2, "contexts": GLOBAL},
	{"id": "game_work", "label": "自主工作", "key": KEY_J, "contexts": INTERACT},
	{"id": "game_rotate_take", "label": "旋转／拿取", "key": KEY_R, "contexts": INTERACT},
	{"id": "game_demolish_tool", "label": "拆除工具", "key": KEY_DELETE, "contexts": INTERACT},
	{"id": "game_save", "label": "保存", "key": KEY_F5, "contexts": GLOBAL},
	{"id": "game_load", "label": "读取", "key": KEY_F9, "contexts": GLOBAL},
	{"id": "game_pan_left", "label": "镜头左移", "key": KEY_LEFT, "contexts": GLOBAL},
	{"id": "game_pan_right", "label": "镜头右移", "key": KEY_RIGHT, "contexts": GLOBAL},
	{"id": "game_pan_up", "label": "镜头上移", "key": KEY_UP, "contexts": GLOBAL},
	{"id": "game_pan_down", "label": "镜头下移", "key": KEY_DOWN, "contexts": GLOBAL},
]
const RESERVED: Array[Dictionary] = [
	{"label": "返回／取消", "kind": "key", "code": KEY_ESCAPE, "contexts": GLOBAL},
	{"label": "系统切窗", "kind": "key", "code": KEY_ALT, "contexts": GLOBAL},
	{"label": "系统菜单", "kind": "key", "code": KEY_META, "contexts": GLOBAL},
	{"label": "DEV路线", "kind": "key", "code": KEY_P, "contexts": GLOBAL},
	{"label": "素材图鉴", "kind": "key", "code": KEY_F8, "contexts": GLOBAL},
	{"label": "诊断面板", "kind": "key", "code": KEY_F12, "contexts": GLOBAL},
	{"label": "交互选择／工具确认", "kind": "mouse", "code": MOUSE_BUTTON_LEFT, "contexts": INTERACT},
	{"label": "对象菜单／取消工具", "kind": "mouse", "code": MOUSE_BUTTON_RIGHT, "contexts": INTERACT},
]
var config_path: String = "user://controls.cfg"
var values: Dictionary = defaults()
var notice: String = ""

static func defaults() -> Dictionary:
	var result: Dictionary = {}
	for spec: Dictionary in SPECS:
		result[spec.id] = {"kind": "mouse" if spec.has("mouse") else "key", "code": int(spec.get("mouse", spec.get("key", 0)))}
	return result

static func spec_for(id: String) -> Dictionary:
	for spec: Dictionary in SPECS:
		if spec.id == id: return spec
	return {}

static func active(id: String, direct: bool) -> bool:
	return int(spec_for(id).get("contexts", 0)) & (ACT if direct else INTERACT) != 0

static func descriptor(event: InputEvent) -> Dictionary:
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if code in [KEY_CTRL, KEY_ALT, KEY_META]: return {}
		if (event.shift_pressed and code != KEY_SHIFT) or (event.ctrl_pressed and code != KEY_CTRL) or (event.alt_pressed and code != KEY_ALT) or (event.meta_pressed and code != KEY_META): return {}
		return {"kind": "key", "code": code}
	if event is InputEventMouseButton and event.pressed:
		if event.shift_pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return {}
		return {"kind": "mouse", "code": int(event.button_index)}
	return {}

static func valid_binding(value: Variant) -> bool:
	if not value is Dictionary or not value.get("code") is int: return false
	if value.get("kind") == "key": return value.code > 0 and value.code < KEY_SPECIAL * 2 and (value.code & KEY_MODIFIER_MASK) == 0
	return value.get("kind") == "mouse" and value.code in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]

static func same(a: Variant, b: Variant) -> bool:
	return a is Dictionary and b is Dictionary and a.get("kind") == b.get("kind") and a.get("code") == b.get("code")

static func conflicts(id: String, value: Dictionary, table: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var spec: Dictionary = spec_for(id)
	for other: Dictionary in SPECS:
		if other.id != id and int(other.contexts) & int(spec.contexts) != 0 and same(value, table.get(other.id, {})): result.append(other.id)
	for fixed: Dictionary in RESERVED:
		if int(fixed.contexts) & int(spec.contexts) != 0 and same(value, fixed): result.append(fixed.label)
	return result

static func validate(table: Dictionary) -> String:
	for spec: Dictionary in SPECS:
		if not valid_binding(table.get(spec.id)): return "%s没有有效按键" % spec.label
		var occupied: Array[String] = conflicts(spec.id, table[spec.id], table)
		if not occupied.is_empty(): return "%s与%s冲突" % [spec.label, action_label(occupied[0])]
	return ""

static func action_label(id: String) -> String:
	return str(spec_for(id).get("label", id))

static func format_binding(value: Dictionary) -> String:
	if value.get("kind") == "mouse": return {MOUSE_BUTTON_LEFT: "左键", MOUSE_BUTTON_RIGHT: "右键", MOUSE_BUTTON_XBUTTON1: "侧键1", MOUSE_BUTTON_XBUTTON2: "侧键2"}.get(int(value.code), "鼠标键")
	var code: int = int(value.get("code", 0))
	var label: int = DisplayServer.keyboard_get_label_from_physical(code) if DisplayServer.get_name() != "headless" else code
	return OS.get_keycode_string(label if label != 0 else code)

func hint(id: String) -> String:
	return format_binding(values[id]) if values.has(id) else ""

func install() -> void:
	values = defaults()
	notice = ""
	var config := ConfigFile.new()
	var error: Error = config.load(config_path)
	if error == OK:
		var candidate: Dictionary = defaults()
		for spec: Dictionary in SPECS:
			if config.has_section_key("actions", spec.id): candidate[spec.id] = config.get_value("actions", spec.id)
		# New optional slots must not discard older custom movement/attack keys.
		for id: String in ["act_skill2", "act_skill3"]:
			if config.has_section_key("actions", id): continue
			for code: Key in [KEY_E, KEY_C, KEY_V, KEY_X, KEY_T, KEY_Y, KEY_U, KEY_O, KEY_K]:
				var proposed: Dictionary = {"kind": "key", "code": code}
				if conflicts(id, proposed, candidate).is_empty(): candidate[id] = proposed; break
		if int(config.get_value("controls", "version", 0)) == 1 and validate(candidate).is_empty(): values = candidate
		else: notice = "键位配置无效，已使用默认键位"
	elif error != ERR_FILE_NOT_FOUND: notice = "无法读取键位配置，已使用默认键位"
	_apply()

func propose(id: String, event: InputEvent) -> Dictionary:
	if spec_for(id).is_empty(): return {"ok": false, "message": "此操作不可改键"}
	var value: Dictionary = descriptor(event)
	if not valid_binding(value): return {"ok": false, "message": "请选择单个键或鼠标主键／侧键；滚轮和中键保留给镜头"}
	var candidate: Dictionary = values.duplicate(true)
	candidate[id] = value
	var occupied: Array[String] = conflicts(id, value, candidate)
	if occupied.is_empty(): return {"ok": true, "candidate": candidate}
	var names := PackedStringArray()
	for other: String in occupied: names.append(action_label(other))
	var reply: Dictionary = {"ok": false, "message": "%s已用于%s" % [format_binding(value), "、".join(names)]}
	if occupied.size() == 1 and values.has(occupied[0]):
		candidate[occupied[0]] = values[id].duplicate()
		if validate(candidate).is_empty():
			reply.swap = candidate
			reply.message += "，可交换两项键位"
	return reply

func commit(candidate: Dictionary, persist: bool = true) -> Error:
	if not validate(candidate).is_empty(): return ERR_INVALID_DATA
	if persist:
		var config := ConfigFile.new()
		config.set_value("controls", "version", 1)
		for spec: Dictionary in SPECS: config.set_value("actions", spec.id, candidate[spec.id])
		var error: Error = config.save(config_path)
		if error != OK: return error
	values = candidate.duplicate(true)
	_apply()
	changed.emit()
	return OK

func _apply() -> void:
	for spec: Dictionary in SPECS:
		if not InputMap.has_action(spec.id): InputMap.add_action(spec.id)
		InputMap.action_erase_events(spec.id)
		var value: Dictionary = values[spec.id]
		var event: InputEvent
		if value.kind == "key":
			var key := InputEventKey.new()
			key.physical_keycode = int(value.code)
			event = key
		else:
			var mouse := InputEventMouseButton.new()
			mouse.button_index = int(value.code)
			event = mouse
		InputMap.action_add_event(spec.id, event)
