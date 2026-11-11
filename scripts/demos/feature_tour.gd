extends "res://scripts/main.gd"
## Explicit small playable exhibition. Ordinary Main and stress openings stay separate.
const Scenario = preload("res://scripts/demos/feature_tour_scenario.gd")
const Guide = preload("res://scripts/demos/feature_tour_guide.gd")
const SAVE_SLOT: String = "user://feature_tour.json"
var tour_guide: CanvasLayer
var tour_locations: Dictionary = {}

class TourVillage extends VillageRuntime:
	func _load_config() -> bool:
		if not super._load_config():
			return false
		# Opening supplies, not rewards or a bypass of ordinary transactions.
		_config.initial_stock.store.wood = 1000
		_config.initial_stock.store.stone = 200
		return true


func _init() -> void:
	Scenario.configure(self)


func _create_village_runtime() -> VillageRuntime:
	return TourVillage.new()


func _ready() -> void:
	# Reloading the exhibition starts a new life, after the previous scene has
	# released its executor. Loading the demo slot uses the ordinary save pipeline.
	GameClock.restore_state({"tick_index": 0, "total_minutes": GameClock.start_minutes, "speed": 1.0,
		"paused": true, "elapsed_ms": 0, "frame_debt_ms": 0.0, "wait_target_ms": 0})
	super._ready()
	if _continuity == null or _continuity.world_sim == null:
		return
	_continuity.save_path = SAVE_SLOT
	var scenario := Scenario.new()
	var result: Dictionary = scenario.install(_continuity)
	if not result.ok:
		push_error("Feature tour setup: " + str(result.line))
		return
	tour_locations = result.locations
	var subject: String = str(get_tree().get_meta("feature_tour_avatar", "subject:player"))
	_avatar.choose(subject)
	GameClock.set_paused(true)
	_continuity.set_life_panels_visible(false)
	_continuity._refresh_views(true)
	_continuity._capture_committed_canvases()
	fog.set_focus(_continuity.controlled_cell())
	fog.invalidate_visibility()
	fog.update_now()
	tour_guide = Guide.new()
	tour_guide.name = "FeatureTourGuide"
	add_child(tour_guide)
	tour_guide.setup(self, tour_locations)
	DisplayServer.window_set_title("REOL · 功能试游 · 地块悬浮与单位选择")
	print("FEATURE_TOUR_READY residents=12 rooms=2 save_slot=", SAVE_SLOT)
