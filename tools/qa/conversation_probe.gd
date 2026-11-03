extends "res://tests/run_tests.gd"
## Focused behavioral checks; no real fixture is created or overwritten here.


func _run_tests() -> void:
	test_capability_conversation()
	test_capability_conversation_runtime()
	print("Conversation probe: %d assertions / %d failures" % [checks, failed])
	quit(1 if failed > 0 else 0)
