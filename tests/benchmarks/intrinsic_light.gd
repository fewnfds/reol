extends "res://tests/run_tests.gd"
## Original issued objects, bounded queries; not FPS or moving-source capacity.


func _run_tests() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].is_valid_int() or int(args[0]) not in [1, 16, 128]:
		quit(1)
		return
	var count: int = int(args[0])
	var fixture: RefCounted = load("res://tests/sim/test_intrinsic_light.gd").new()
	var content: ReolContentDB = fixture._content(self)
	var world: RegionalSimulation = fixture._world(self, content, count)
	if world == null or failed > 0:
		quit(1)
		return
	var center: Vector2i = world.artifacts.object_cell("pearl")
	var cells: Array[Vector2i] = []
	for y: int in range(-10, 11):
		for x: int in range(-10, 11):
			cells.append(center + Vector2i(x, y))
	var before: String = fixture._json(world.to_dict())
	var samples: Array[int] = []
	for _sample: int in 30:
		var start: int = Time.get_ticks_usec()
		var result: Dictionary = SimLocalLight.local_patch(world, cells)
		samples.append(Time.get_ticks_usec() - start)
		if not result.supported or int(result.values[center]) != mini(40000, 6000 + (3000 if count > 1 else 0) + maxi(0, count - 2) * 6000):
			quit(1)
			return
	assert_eq(fixture._json(world.to_dict()), before, "benchmark queries preserve all original world facts")
	samples.sort()
	var total: int = 0
	for sample: int in samples:
		total += sample
	print("INTRINSIC_BENCHMARK_RESULT ", JSON.stringify({"sources": count, "cells": cells.size(), "samples": samples.size(), "mean_us": float(total) / samples.size(), "p95_us": samples[28], "p99_us": samples[29]}))
	quit(1 if failed > 0 else 0)
