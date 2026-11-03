extends SceneTree
## Focused suites use the same assertion contract as tests/run_tests.gd.

var failed: int = 0
var checks: int = 0
const SUITES: Dictionary = {
	"drawing": "res://tests/sim/test_artifact_drawing.gd",
	"migration": "res://tests/runtime/test_drawing_migration.gd",
	"runtime": "res://tests/runtime/test_drawing_runtime.gd",
	"continuity": "res://tests/runtime/test_drawing_continuity.gd",
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var selected: Array = OS.get_cmdline_user_args()
	if selected.is_empty():
		selected = ["drawing", "migration"]
	for suite_name: String in selected:
		if not SUITES.has(suite_name) or not FileAccess.file_exists(SUITES[suite_name]):
			assert_true(false, "unknown or unfinished suite: " + suite_name)
			continue
		print("RUN ", suite_name)
		var suite: GDScript = load(SUITES[suite_name])
		if suite == null or not suite.can_instantiate():
			assert_true(false, "suite parses: " + suite_name)
			continue
		suite.new().run(self)
	print("DRAWING assertions=", checks, " failed=", failed)
	quit(1 if failed > 0 else 0)


func assert_true(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed += 1
		printerr("FAIL ", label)


func assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	assert_true(actual == expected, label)
	if actual != expected:
		printerr("  expected=", str(expected).left(240), " actual=", str(actual).left(240))
