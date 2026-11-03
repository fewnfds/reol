extends "res://tests/run_tests.gd"


func _run_tests() -> void:
	test_entrusted_goods()
	test_entrusted_goods_runtime()
	test_local_trade()
	test_personal_foraging()
	test_settlement_services()
	print("Entrusted goods probe: %d assertions, %d failed" % [checks, failed])
	quit(1 if failed > 0 else 0)
