extends "res://tests/run_tests.gd"


func _run_tests() -> void:
	test_standing_work()
	test_standing_work_runtime()
	test_interaction_requests()
	test_entrusted_goods_runtime()
	print("Standing work probe: %d assertions, %d failed" % [checks, failed])
	quit(1 if failed > 0 else 0)
