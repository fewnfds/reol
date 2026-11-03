extends "res://tests/run_tests.gd"
## Focused integration gate before the ordinary full regression run.


func _run_tests() -> void:
	for name: String in ["test_world_map_data", "test_world_map_runtime", "test_world_terrain_and_elevation", "test_village_navigation", "test_village_runtime", "test_construction_runtime", "test_large_bodies_runtime", "test_world_persistence"]:
		print("RUN ", name)
		call(name)
	print("World map probe: ", checks, " assertions, ", failed, " failures")
	quit(0 if failed == 0 else 1)
