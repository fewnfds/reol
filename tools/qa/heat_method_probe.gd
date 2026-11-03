extends SceneTree
## Focused invocation of the actual rule suite; full runner remains release gate.
var failed: int = 0
var checks: int = 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	load("res://tests/sim/test_heat_method_crafting.gd").new().run(self)
	print("Heat method probe: %d assertions, %d failed" % [checks, failed])
	quit(1 if failed > 0 else 0)


func assert_true(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failed += 1
		printerr("FAIL " + label)


func assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual != expected:
		failed += 1
		printerr("FAIL %s: expected %s, got %s" % [label, expected, actual])


func assert_not_null(value: Variant, label: String) -> void:
	assert_true(value != null, label)
