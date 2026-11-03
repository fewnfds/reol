class_name DayNight
extends CanvasModulate
## Tints the world by time of day. HUD lives on its own CanvasLayer, so it
## stays readable at night.

const NIGHT := Color(0.53, 0.61, 0.73)
const DAWN := Color(0.96, 0.82, 0.7)
const DAY := Color(1.0, 1.0, 1.0)
const DUSK := Color(0.95, 0.72, 0.62)


func _ready() -> void:
	GameClock.tick.connect(_on_tick)
	GameClock.hour_changed.connect(_on_tick)
	_update_tint()


func _on_tick(_index: int) -> void:
	_update_tint()


func _update_tint() -> void:
	var hour: float = float(GameClock.get_hour()) + float(GameClock.get_minute()) / 60.0
	color = _color_for_hour(hour)


func _color_for_hour(hour: float) -> Color:
	if hour < 5.0:
		return NIGHT
	if hour < 7.0:
		return NIGHT.lerp(DAWN, smoothstep(5.0, 7.0, hour))
	if hour < 9.0:
		return DAWN.lerp(DAY, smoothstep(7.0, 9.0, hour))
	if hour < 17.0:
		return DAY
	if hour < 19.0:
		return DAY.lerp(DUSK, smoothstep(17.0, 19.0, hour))
	if hour < 21.0:
		return DUSK.lerp(NIGHT, smoothstep(19.0, 21.0, hour))
	return NIGHT
