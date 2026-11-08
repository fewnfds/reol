class_name WeatherRuntime
extends Node2D
## Read-only local calendar/conditions and bounded cosmetic rain.
## The original world owns climate, bodies, water and all exposure costs.

var _owner: WeakRef
var _caption: Label
var _weather_region: String = "home"
var _rain_points := PackedVector2Array()


func setup(adapter: WorldContinuityRuntime) -> void:
	_owner = weakref(adapter)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	var screen := Control.new()
	screen.name = "EnvironmentScreen"
	layer.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption = Label.new()
	_caption.name = "EnvironmentCaption"
	_caption.position = Vector2(24, 106)
	_caption.size = Vector2(618, 24)
	_caption.clip_text = true
	_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_caption.add_theme_color_override("font_color", Color("b4cdd2"))
	_caption.add_theme_font_size_override("font_size", 15)
	_caption.mouse_filter = Control.MOUSE_FILTER_PASS
	screen.add_child(_caption)
	screen.resized.connect(_resize_caption.bind(screen))
	_resize_caption(screen)
	adapter.avatar_changed.connect(refresh)
	adapter.region_changed.connect(_on_region)
	adapter.player_travel_advanced.connect(_on_travel)
	adapter.home_runtime()._player.cell_changed.connect(refresh)
	GameClock.time_advanced.connect(_on_time)
	refresh()


func refresh() -> void:
	var adapter: WorldContinuityRuntime = _owner.get_ref() as WorldContinuityRuntime
	if adapter == null or adapter.world_sim == null:
		return
	if adapter.world_sim.settlement != null and adapter.world_sim.settlement.is_pending():
		# Retain caption and rain until the next complete clock notification.
		return
	_caption.visible = not adapter.soul_player_active()
	_weather_region = SimClimateRules.region_at(adapter.world_sim.environment.definitions, adapter.controlled_cell())
	var feeling: String = ""
	if adapter.human_player_active():
		var conditions: Dictionary = adapter.world_sim.environment.local_conditions("player")
		feeling = str(conditions.get("feeling", ""))
		if adapter.world_sim.weather.definitions.regions.has(str(conditions.get("region", ""))):
			_weather_region = str(conditions.region)
	var raining: bool = adapter.world_sim.weather.current_kind(_weather_region) == "rain"
	var light: Dictionary = SimNaturalLight.at_cell(adapter.world_sim, adapter.controlled_cell())
	var sky: String = SimNaturalLight.description(light).trim_suffix("。")
	_caption.text = "%s · %s · %s" % [adapter.world_sim.environment.date_label(), "山间落雨" if raining else "天晴", sky]
	if not feeling.is_empty():
		_caption.text += " · " + feeling
	var local: String = SimLocalLight.description(SimLocalLight.at_cell(adapter.world_sim, adapter.controlled_cell())).trim_suffix("。")
	if not local.is_empty():
		_caption.text += " · " + local
	_caption.tooltip_text = "露天床铺会受潮，雨水可回补泉源。" if raining else "雨后的床铺逐渐晾干。"
	if adapter.human_player_active():
		_caption.tooltip_text += "\n冷暖取决于当地时令、实际衣着和近旁余热；屋面与门墙会影响余热散失。"
	_project_rain(adapter)
	queue_redraw()


func _on_region(_id: String) -> void:
	refresh()


func _on_travel(_point: Vector2) -> void:
	refresh()


func _resize_caption(screen: Control) -> void:
	var width: float = minf(618.0, maxf(0.0, screen.size.x - 48.0)) if screen.size.x > 0.0 else 618.0
	_caption.size = Vector2(width, 24)


func _on_time(_from: int, _to: int) -> void:
	refresh()


func _project_rain(adapter: WorldContinuityRuntime) -> void:
	_rain_points.clear()
	if adapter.soul_player_active():
		return
	if adapter.world_sim.weather.current_kind(_weather_region) != "rain":
		return
	var center: Vector2 = adapter._home._player.global_position
	if adapter.bird_player_active():
		center = SimAvianLife.point(adapter.world_sim.avian_life.birds[adapter.bird_avatar_id()])
	var phase: float = float(adapter.world_sim.elapsed_ms % 1200) / 1200.0
	for index: int in 88:
		var offset := Vector2(float((index * 137) % 1280) - 640.0, fposmod(float(index * 73) + phase * 720.0, 720.0) - 360.0)
		var point: Vector2 = center + offset
		var cell: Vector2i = TileGrid.world_to_cell(point)
		if adapter._home._fog != null and not adapter._home._fog.is_cell_visible(cell):
			continue
		if adapter.world_sim.construction.roofed(cell):
			continue
		_rain_points.append(point)


func _draw() -> void:
	# At most 88 cosmetic marks; no world state is copied or read on redraw.
	for point: Vector2 in _rain_points:
		draw_line(point, point + Vector2(-5, 13), Color(0.66, 0.81, 0.87, 0.38), 1.2)
