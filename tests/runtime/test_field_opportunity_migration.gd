extends RefCounted
## Current in-flight clue, journey and independent future: test_field_opportunity_runtime.gd.
## These genuine older archives are immutable and cannot enter the current world.

const LegacyRejection = preload("res://tests/runtime/helpers/legacy_rejection_archive.gd")
const ARCHIVES: Dictionary = {
	"res://tests/fixtures/session_v39.json": "396fe171bc0384335bece4120fa7ac4e7aecfee0cd1f8c3629909d1cf0976bab",
	"res://tests/fixtures/session_v39_guard.json": "fe8629a5aa8ea068adc2112720801bfaa9538562c566f57cabcd6acc8f382f2e",
}


func run(runner: Object) -> void:
	LegacyRejection.run(runner, ARCHIVES, ["field_opportunities"], [35])
	print("SCENARIO retired archives: real v39 field predecessors are rejected without changing their files or the live session")
