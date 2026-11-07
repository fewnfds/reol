extends RefCounted
## Current learning, payment, cancellation and continuation: tests/sim/test_capability_practice.gd.
## These genuine older archives are immutable and cannot enter the current world.

const LegacyRejection = preload("res://tests/runtime/helpers/legacy_rejection_archive.gd")
const ARCHIVES: Dictionary = {
	"res://tests/fixtures/session_v38.json": "79c390a681a1c711b6dc3044bc5d79718b539e5916899187e3132c051a9d6067",
	"res://tests/fixtures/session_v38_explained.json": "88f040041a96b6210af07bdb5ac2cc65e1be8a881709f0174dd56b4d69c16ca3",
	"res://tests/fixtures/session_v38_conflict.json": "c45d885fe93a4e5057685d89eb08b3e2d38bf93c6ac022ae14f9af4716257ea2",
}


func run(runner: Object) -> void:
	LegacyRejection.run(runner, ARCHIVES, ["capability_practice"], [34])
	print("SCENARIO retired archives: real v38 capability predecessors are rejected without changing their files or the live session")
