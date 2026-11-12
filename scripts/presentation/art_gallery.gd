extends CanvasLayer
## Optional art contact sheet. Preview animation does not issue world commands.
const Art = preload("res://scripts/presentation/art.gd")
var _panel := PanelContainer.new()
var _built: bool = false
var _actors: Array[Dictionary] = []
var _last_frame: int = -1


func _ready() -> void:
	layer = 20
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 20
	_panel.offset_top = 55
	_panel.offset_right = -20
	_panel.offset_bottom = -20
	_panel.hide()
	set_process(false)


func is_open() -> bool:
	return _panel.visible


func toggle() -> void:
	if not _built:
		_build()
		_built = true
	_panel.visible = not _panel.visible
	set_process(_panel.visible)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F8 or (event.keycode == KEY_ESCAPE and is_open()):
			toggle()
			get_viewport().set_input_as_handled()


func _grid(tabs: TabContainer, title: String) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	tabs.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	return grid


func _tile(grid: GridContainer, title: String, texture: Texture2D) -> void:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(128, 106)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(box)
	var image := TextureRect.new()
	image.texture = texture
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = Vector2(90, 82)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(image)
	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	box.add_child(label)


func _build() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	_panel.add_theme_font_override("font", font)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("263c3a")
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", style)
	var body := VBoxContainer.new()
	_panel.add_child(body)
	var heading := Label.new()
	heading.text = "玉谷 · 临时像素素材图鉴   |   F8 / Esc 返回游戏"
	heading.add_theme_font_size_override("font_size", 20)
	body.add_child(heading)
	var note := Label.new()
	note.text = "临时测试素材 · 动作预览独立于世界；生物和部分家具为美术预备，对应玩法尚未实现。"
	note.add_theme_font_size_override("font_size", 13)
	body.add_child(note)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(tabs)
	var grid := _grid(tabs, "八向动作")
	for clip: Dictionary in Art.catalog().characters.clips:
		for direction: int in 8:
			var texture := AtlasTexture.new()
			texture.atlas = Art.ACTORS
			texture.region = Rect2(direction * 4 * 48, int(clip.row) * 48, 48, 48)
			_tile(grid, "%s · %s" % [clip.label, Art.catalog().characters.directions[direction]], texture)
			_actors.append({"texture": texture, "row": int(clip.row), "direction": direction})
	var world_grid := _grid(tabs, "地物与物品")
	var fauna_grid := _grid(tabs, "生物预备")
	var effect_grid := _grid(tabs, "特效切片")
	for key: String in Art.catalog().entries:
		var entry: Dictionary = Art.catalog().entries[key]
		var target: GridContainer = fauna_grid if entry.category == "creatures" else (effect_grid if entry.category == "effects" else world_grid)
		_tile(target, str(entry.label), Art.icon(key))


func _process(_delta: float) -> void:
	var frame: int = (Time.get_ticks_msec() / 225) % 4
	if _last_frame == frame:
		return
	_last_frame = frame
	for entry: Dictionary in _actors:
		entry.texture.region = Rect2((entry.direction * 4 + (0 if entry.row == 14 else frame)) * 48, entry.row * 48, 48, 48)
