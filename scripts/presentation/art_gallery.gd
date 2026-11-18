extends CanvasLayer
## Optional art contact sheet. Preview animation does not issue world commands.
const Art = preload("res://scripts/presentation/art.gd")
var _backdrop := Control.new()
var _panel := PanelContainer.new()
var _built: bool = false
var _tabs: TabContainer
var _actor_tabs: Array[Array] = [[], []]
var _previous_focus: Control
var _last_frame: int = -1


func _ready() -> void:
	layer = 20
	add_child(_backdrop)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 20
	_panel.offset_top = 55
	_panel.offset_right = -20
	_panel.offset_bottom = -20
	_backdrop.hide()
	set_process(false)


func is_open() -> bool:
	return _backdrop.visible


func toggle() -> void:
	if is_open():
		_backdrop.hide()
		set_process(false)
		if is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree(): _previous_focus.grab_focus()
		_previous_focus = null
		return
	_previous_focus = get_viewport().gui_get_focus_owner()
	if _previous_focus != null: _previous_focus.release_focus()
	if not _built:
		_build()
		_built = true
	_backdrop.show()
	_tabs.get_tab_bar().grab_focus()
	_last_frame = -1
	set_process(true)


func _grid(title: String) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var grid := GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	scroll.resized.connect(func(): grid.columns = clampi(int((scroll.size.x - 20.0) / 136.0), 1, 8))
	return grid


func _tile(grid: GridContainer, title: String, texture: Texture2D, key: String = "", details: String = "") -> void:
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
	image.mouse_filter = Control.MOUSE_FILTER_PASS
	image.tooltip_text = details
	box.add_child(image)
	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(label)
	if not key.is_empty():
		var identifier := Label.new()
		identifier.text = key
		identifier.tooltip_text = details
		identifier.mouse_filter = Control.MOUSE_FILTER_PASS
		identifier.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		identifier.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		identifier.modulate = Color("b5c6bd")
		identifier.add_theme_font_size_override("font_size", 11)
		box.add_child(identifier)


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
	var header := HBoxContainer.new()
	body.add_child(header)
	var heading := Label.new()
	heading.text = "素材图鉴"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_size_override("font_size", 20)
	header.add_child(heading)
	var close := Button.new()
	close.text = "关闭 · Esc"
	close.pressed.connect(toggle)
	header.add_child(close)
	var note := Label.new()
	note.text = "悬停查看资源路径与切片坐标。整张贴图见「原图集」。"
	note.add_theme_font_size_override("font_size", 13)
	body.add_child(note)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_tabs)
	var catalog: Dictionary = Art.catalog()
	for variant: int in 2:
		var grid: GridContainer = _grid("男角色" if variant == 0 else "女角色")
		for clip: Dictionary in catalog.characters.clips:
			for direction: int in 8:
				var texture := AtlasTexture.new()
				texture.atlas = Art.ACTORS
				texture.filter_clip = true
				texture.region = Rect2(Art.actor_region(int(clip.row), direction, 0, variant))
				var facing: String = str(catalog.characters.directions[direction])
				_tile(grid, "%s · %s" % [clip.label, facing], texture, str(clip.id), "%s\n首帧 %s" % [Art.ACTORS.resource_path, str(texture.region)])
				_actor_tabs[variant].append({"texture": texture, "row": int(clip.row), "direction": direction})
	var world_grid: GridContainer = _grid("地物与物品")
	var fauna_grid: GridContainer = _grid("生物预备")
	var effect_grid: GridContainer = _grid("特效切片")
	for key: String in catalog.entries:
		var entry: Dictionary = catalog.entries[key]
		var target: GridContainer = fauna_grid if entry.category == "creatures" else (effect_grid if entry.category == "effects" else world_grid)
		_tile(target, str(entry.label), Art.icon(key), key, "%s\n%s\n来源 %s" % [Art.WORLD.resource_path, Art.region(key), entry.get("source", "")])
	_add_atlases()
	_tabs.tab_changed.connect(func(_index: int): _last_frame = -1)


func _add_atlases() -> void:
	var column := VBoxContainer.new()
	column.name = "原图集"
	_tabs.add_child(column)
	var picker := OptionButton.new()
	column.add_child(picker)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var image := TextureRect.new()
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.stretch_mode = TextureRect.STRETCH_KEEP
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(image)
	var textures: Array[Texture2D] = [Art.ACTORS, Art.WORLD, Art.GROUND]
	for texture: Texture2D in textures: picker.add_item(texture.resource_path)
	image.texture = textures[0]
	picker.item_selected.connect(func(index: int):
		image.texture = textures[index]
		scroll.scroll_horizontal = 0
		scroll.scroll_vertical = 0)


func _process(_delta: float) -> void:
	var variant: int = _tabs.current_tab
	if variant < 0 or variant >= _actor_tabs.size(): return
	var frame: int = (Time.get_ticks_msec() / 225) % 4
	if _last_frame == frame: return
	_last_frame = frame
	for entry: Dictionary in _actor_tabs[variant]:
		entry.texture.region = Rect2(Art.actor_region(entry.row, entry.direction, 0 if entry.row == Art.Clip.DEAD else frame, variant))
