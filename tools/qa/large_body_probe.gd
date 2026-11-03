extends SceneTree
## Focused development runner; never loaded by the game.
var failed: int = 0
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	load("res://tests/sim/test_large_bodies.gd").new().run(self)
	load("res://tests/runtime/test_large_bodies_runtime.gd").new().run(self)
	print("LARGE BODY PROBE: %d checks, %d failures" % [checks, failed])
	quit(1 if failed > 0 else 0)


func assert_true(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failed += 1
		printerr("FAIL " + label)


func assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	assert_true(actual == expected, label + " expected=" + str(expected) + " actual=" + str(actual) if actual != expected else label)


func assert_not_null(value: Variant, label: String) -> void:
	assert_true(value != null, label)
