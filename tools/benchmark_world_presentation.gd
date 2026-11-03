extends SceneTree
## Repeatable CPU probe; excludes rendering/GPU work and whole-game FPS.

const ITERATIONS: int = 120


func _initialize() -> void:
	var world := ReolWorld.new()
	world.initialize()
	var fog := FogOfWar.new()
	var origin := Vector2i(256, 256)
	fog.setup(world, origin)
	var start: int = Time.get_ticks_usec()
	for _index: int in ITERATIONS:
		fog._process(FogOfWar.UPDATE_INTERVAL)
	var stationary: int = Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	for index: int in ITERATIONS:
		fog.set_focus(origin + Vector2i(index % 2, 0))
		fog._process(FogOfWar.UPDATE_INTERVAL)
	var moving: int = Time.get_ticks_usec() - start
	print("WORLD PRESENTATION CPU: %d fog intervals; stationary %dus (mean %.2fus), alternating cells %dus (mean %.2fus)" % [
		ITERATIONS, stationary, float(stationary) / ITERATIONS, moving, float(moving) / ITERATIONS,
	])
	fog.free()
	world.free()
	quit(0)
