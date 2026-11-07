extends SceneTree
## Focused suites use the same assertions as the complete runner.

var failed: int = 0
var checks: int = 0
const SUITES: Dictionary = {
	"migration": "res://tests/runtime/test_field_opportunity_migration.gd",
	"field": "res://tests/sim/test_field_opportunities.gd",
	"runtime": "res://tests/runtime/test_field_opportunity_runtime.gd",
	"objects": "res://tests/sim/test_field_artifacts.gd",
	"views": "res://tests/runtime/test_field_views_and_travel.gd",
	"causality": "res://tests/sim/test_field_causality.gd",
	"absence": "res://tests/runtime/test_field_opportunity_absence.gd",
	"legacy_continuity": "res://tests/runtime/test_world_continuity_runtime.gd",
	"legacy_capability": "res://tests/runtime/test_capability_migration.gd",
	"legacy_care": "res://tests/runtime/test_source_care_migration.gd",
	"legacy_loan": "res://tests/runtime/test_source_loan_migration.gd",
	"legacy_heat": "res://tests/runtime/test_local_heat_migration.gd",
	"legacy_source": "res://tests/runtime/test_spirit_source_continuity.gd",
	"legacy_health": "res://tests/runtime/test_health_runtime.gd",
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var selected: Array = OS.get_cmdline_user_args()
	if selected.is_empty():
		selected = ["migration", "field", "runtime", "objects", "views", "causality", "absence"]
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
	print("FIELD assertions=", checks, " failed=", failed)
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
