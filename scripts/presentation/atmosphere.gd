extends Node
## Rendering only. Solar colour/approximate shadows and weather follow committed
## world time. One GPU screen layer, no per-cell lights or simulation changes.

const WeatherShader = preload("res://scripts/presentation/weather.gdshader")
var _ambient := CanvasModulate.new()
var _weather := ColorRect.new()
var _weather_layer := CanvasLayer.new()
var _shade := ShaderMaterial.new()
var _last_ms: int = -1
var _weather_mode: int = 0
var _epoch: int = -1


func _ready() -> void:
	add_child(_ambient)
	_weather_layer.layer = 1
	add_child(_weather_layer)
	_shade.shader = WeatherShader
	_weather.material = _shade
	_weather.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weather.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_weather_layer.add_child(_weather)


func adopt(frame: RefCounted, at_ms: float) -> void:
	var time_ms: int = int(at_ms)
	var calendar: Dictionary = frame.counters.get("calendar", {})
	var weather_mode: int = ["晴", "雨", "寒风", "热浪"].find(str(calendar.get("weather", "晴")))
	if time_ms == _last_ms and _epoch == frame.epoch and weather_mode == _weather_mode:
		return
	_last_ms = time_ms
	_epoch = frame.epoch
	var phase: float = fposmod(at_ms / 1200000.0 + 0.5, 1.0)
	var day: float = maxf(0.0, sin((phase - 0.25) * TAU))
	var color := Color(0.48, 0.59, 0.77).lerp(Color(1.0, 0.99, 0.94), day)
	var dusk: float = exp(-pow((phase - 0.74) / 0.06, 2.0)) + exp(-pow((phase - 0.26) / 0.06, 2.0))
	color = color.lerp(Color(1.0, 0.76, 0.60), dusk * 0.40)
	_weather_mode = weather_mode
	if _weather_mode == 1:
		color *= Color(0.82, 0.88, 0.94)
	elif _weather_mode == 2:
		color *= Color(0.85, 0.94, 1.0)
	_ambient.color = color
	RenderingServer.global_shader_parameter_set("art_time", fmod(at_ms / 1000.0, 7200.0))
	RenderingServer.global_shader_parameter_set("art_sun", Vector2(cos((phase - 0.25) * TAU) * 0.48, 0.14 + day * 0.04))
	RenderingServer.global_shader_parameter_set("art_sun_strength", day * (0.35 if _weather_mode == 1 else 1.0))
	_shade.set_shader_parameter("weather_mode", _weather_mode)
	_shade.set_shader_parameter("world_time", fmod(at_ms / 1000.0, 7200.0))
	_shade.set_shader_parameter("day_light", 0.45 + day * 0.55)
	_weather.visible = _weather_mode > 0


func view(visibility: Texture2D, shelter: Texture2D, use_fog: bool) -> void:
	if not _weather.visible:
		return
	# CanvasLayer uses screen coordinates; recover the world rectangle after the
	# camera update. Camera panning must update the mask even while time is paused.
	var viewport := get_viewport()
	var inverse := viewport.get_canvas_transform().affine_inverse()
	var size: Vector2 = viewport.get_visible_rect().size
	var origin: Vector2 = inverse * Vector2.ZERO
	_shade.set_shader_parameter("world_origin", origin / (512.0 * 32.0))
	_shade.set_shader_parameter("world_u", (inverse * Vector2(size.x, 0) - origin) / (512.0 * 32.0))
	_shade.set_shader_parameter("world_v", (inverse * Vector2(0, size.y) - origin) / (512.0 * 32.0))
	_shade.set_shader_parameter("visible_map", visibility)
	_shade.set_shader_parameter("shelter_map", shelter)
	_shade.set_shader_parameter("use_fog", use_fog)
