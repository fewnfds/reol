extends RefCounted
## Current payment and independent restored future: tests/sim/test_private_exchange_order.gd.
## These genuine older archives are immutable and cannot enter the current world.

const LegacyRejection = preload("res://tests/runtime/helpers/legacy_rejection_archive.gd")
const ARCHIVES: Dictionary = {
	"res://tests/fixtures/session_v41_research.json": "bb08013411cdf841521107aeb3941636d117369004d1f7d3a9ee8b63d46c6fbc",
	"res://tests/fixtures/session_v41_draw.json": "a814606c6b8a9666267378ce7ad104fabbb3d1fbe7c2d340bec7ed3583e66143",
}


func run(runner: Object) -> void:
	LegacyRejection.run(runner, ARCHIVES, ["private_exchange"], [37], [5])
	print("SCENARIO retired archives: real v41 in-flight artifact histories are rejected without changing their files or the live session")
