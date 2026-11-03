extends "res://tests/run_tests.gd"


func _run_tests() -> void:
	test_roofs_and_weather()
	test_roofs_weather_runtime()
	test_regional_simulation()
	test_demo_refactor()
	test_rooms_and_rest()
	test_rooms_and_rest_runtime()
	print("Roofs/weather: %d assertions, %d failed" % [checks, failed])
	quit(1 if failed > 0 else 0)
