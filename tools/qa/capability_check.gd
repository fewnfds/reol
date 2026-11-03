extends SceneTree
## Focused suites use the same assertions as the complete runner.

var failed: int = 0
var checks: int = 0
const SUITES: Dictionary = {
	"migration": "res://tests/runtime/test_capability_migration.gd",
	"runtime": "res://tests/runtime/test_capability_runtime.gd",
	"practice": "res://tests/sim/test_capability_practice.gd",
	"queries": "res://tests/sim/test_capability_queries.gd",
	"motion": "res://tests/sim/test_mobile_guard_motion.gd",
	"handoff": "res://tests/runtime/test_mobile_guard_handoff.gd",
	"tactics": "res://tests/runtime/test_mobile_guard_tactics.gd",
	"legacy_health": "res://tests/runtime/test_health_runtime.gd",
	"legacy_perception": "res://tests/runtime/test_conflict_perception_archive.gd",
	"legacy_world": "res://tests/runtime/test_world_persistence.gd",
	"legacy_sparring": "res://tests/runtime/test_sparring_runtime.gd",
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var selected: Array = OS.get_cmdline_user_args()
	if selected.is_empty():
		selected = ["migration", "runtime", "practice", "queries", "motion", "handoff", "tactics"]
	for name: String in selected:
		if not SUITES.has(name) or not FileAccess.file_exists(SUITES[name]):
			assert_true(false, "unknown or unfinished suite: " + name)
			continue
		print("RUN ", name)
		var suite: GDScript = load(SUITES[name])
		if suite == null or not suite.can_instantiate():
			assert_true(false, "suite parses: " + name)
			continue
		suite.new().run(self)
	print("CAPABILITY assertions=", checks, " failed=", failed)
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
