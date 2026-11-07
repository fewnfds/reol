extends RefCounted
## Current research, payment, custody and in-flight continuation: tests/sim/test_artifact_drawing.gd.
## These genuine older archives are immutable and cannot enter the current world.

const LegacyRejection = preload("res://tests/runtime/helpers/legacy_rejection_archive.gd")
const ARCHIVES: Dictionary = {
	"res://tests/fixtures/session_v40.json": "383717fbed1a214a2e0d3e38ae4ff495a4d9b33666ff245fdb75e0900649a8b1",
	"res://tests/fixtures/session_v40_take.json": "8a97fabf282c80a69cd718496a92889dfd30aa97be0ca728c4b17f2d065d4d02",
	"res://tests/fixtures/session_v40_npc.json": "27186018991b78ee1201e2d1286e16af206c72d7d3e9289cdf328fc40acbf7c0",
}


func run(runner: Object) -> void:
	LegacyRejection.run(runner, ARCHIVES, [], [36], [4])
	print("SCENARIO retired archives: real v40 drawing predecessors are rejected without changing their files or the live session")
