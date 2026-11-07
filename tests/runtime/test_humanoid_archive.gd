extends RefCounted
## Current journey and facing continuation: test_humanoid_runtime.gd.
## These genuine older archives are immutable and cannot enter the current world.

const LegacyRejection = preload("res://tests/runtime/helpers/legacy_rejection_archive.gd")
const ARCHIVES: Dictionary = {
	"res://tests/fixtures/session_v30.json": "3c977831104d238ec0fb02c28a74fc0dd8abed07faf313b7c3cec3e945b57588",
	"res://tests/fixtures/session_v31.json": "3753f178d701b26d2bd479f5acd06068037fcfa03bf2e5f7b58e5ebd6dacc991",
}


func run(runner: Object) -> void:
	LegacyRejection.run(runner, ARCHIVES, [], [27], [4])
	print("SCENARIO retired archives: real v30/v31 body and journey archives are rejected without changing their files or the live session")
