class_name DayNight
extends CanvasModulate
## Presentation of the accepted world's natural sky light, never a clock.
## HUD stays on its own CanvasLayer; roof darkness is a local rule query,
## not a global tint that would darken the outdoors when entering a room.

const NIGHT := Color(0.53, 0.61, 0.73)
const DAWN := Color(0.96, 0.82, 0.7)
const DAY := Color(1.0, 1.0, 1.0)
const DUSK := Color(0.95, 0.72, 0.62)
var _owner: WeakRef


func bind_world(adapter: WorldContinuityRuntime) -> void:
	if _owner != null or adapter == null:
		return
	_owner = weakref(adapter)
	GameClock.time_advanced.connect(_on_time)
	adapter.avatar_changed.connect(refresh)
	adapter.region_changed.connect(_on_region)
	adapter.player_travel_advanced.connect(_on_travel)
	adapter.home_runtime()._player.cell_changed.connect(refresh)
	refresh()


func _on_time(_from: int, _to: int) -> void:
	refresh()


func _on_region(_id: String) -> void:
	refresh()


func _on_travel(_point: Vector2) -> void:
	refresh()


func refresh() -> void:
	var adapter: WorldContinuityRuntime = _owner.get_ref() as WorldContinuityRuntime if _owner != null else null
	if adapter == null:
		return
	var light: Dictionary = SimNaturalLight.sky(adapter.world_sim, adapter.controlled_cell())
	if bool(light.supported):
		color = color_for_sky(light)


static func color_for_sky(light: Dictionary) -> Color:
	if not bool(light.get("supported", false)) or int(light.get("relative_scale", 0)) < 1:
		return DAY
	var brightness: float = clampf(float(light.total_relative) / float(light.relative_scale), 0.0, 1.0)
	var result: Color = NIGHT.lerp(DAY, sqrt(brightness))
	# Warm horizon tint fades smoothly by the same solar height in both
	# hemispheres; it is not a second sunrise table or a source of energy.
	var height: float = float(light.elevation_mdeg) / 1000.0
	if height > -6.0 and height < 12.0:
		var horizon: float = smoothstep(-6.0, 0.0, height) * (1.0 - smoothstep(0.0, 12.0, height))
		var warm: Color = DAWN if int(light.solar_time_ms) < SimWorldCalendar.DAY_MS / 2 else DUSK
		result = result.lerp(warm, horizon * 0.48)
	return result
