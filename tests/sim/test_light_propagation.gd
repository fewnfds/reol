extends RefCounted
## Pure geometry and integer-light contract; no scene, inventory or clock.

const SOURCE := Vector2i(8, 8)
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
]
const MAX_INTEGER: int = 9223372036854775807


func run(runner: Object) -> void:
	_definition(runner)
	_straight_and_wall_faces(runner)
	_corner_and_slanted_lines(runner)
	_distance_and_intensity(runner)
	_emission_ratio(runner)
	print("SCENARIO light propagation: strict definitions, full 2D supercover, opaque faces, radial attenuation and overflow-safe emission ratios")


func _definition(runner: Object) -> void:
	runner.assert_true(SimLightPropagation.valid_definition({"version": 1, "peak_relative": 1, "radius_cells": 1}), "the smallest declared optical source is valid")
	runner.assert_true(SimLightPropagation.valid_definition({"version": 1, "peak_relative": 10000, "radius_cells": 8}), "the largest declared optical source is valid")
	for candidate: Variant in [
		null, [], {}, {"version": 1, "peak_relative": 1000},
		{"version": 1, "peak_relative": 1000, "radius_cells": 4, "extra": 1},
		{"version": 2, "peak_relative": 1000, "radius_cells": 4},
		{"version": 1.5, "peak_relative": 1000, "radius_cells": 4},
		{"version": 1, "peak_relative": 0, "radius_cells": 4},
		{"version": 1, "peak_relative": 10001, "radius_cells": 4},
		{"version": 1, "peak_relative": 12.5, "radius_cells": 4},
		{"version": 1, "peak_relative": 1000, "radius_cells": 0},
		{"version": 1, "peak_relative": 1000, "radius_cells": 9},
		{"version": 1, "peak_relative": 1000, "radius_cells": 1.5},
		{"version": 1, "peak_relative": true, "radius_cells": 4},
	]:
		runner.assert_true(not SimLightPropagation.valid_definition(candidate), "malformed light definition is rejected: " + str(candidate))


func _straight_and_wall_faces(runner: Object) -> void:
	var walls: Dictionary = {}
	var opaque: Callable = func(cell: Vector2i) -> bool: return walls.has(cell)
	runner.assert_true(SimLightPropagation.has_line_of_light(SOURCE, SOURCE, opaque), "a source illuminates its own cell")
	for direction: Vector2i in DIRECTIONS:
		var near: Vector2i = SOURCE + direction
		var far: Vector2i = SOURCE + direction * 2
		runner.assert_true(SimLightPropagation.has_line_of_light(SOURCE, far, opaque), "empty cells transmit light in direction " + str(direction))
		walls[near] = true
		runner.assert_true(SimLightPropagation.has_line_of_light(SOURCE, near, opaque), "the opaque target face itself receives light " + str(direction))
		runner.assert_true(not SimLightPropagation.has_line_of_light(SOURCE, far, opaque), "an intermediate opaque cell blocks light " + str(direction))
		walls.clear()
		runner.assert_true(SimLightPropagation.has_line_of_light(SOURCE, far, opaque), "the next query sees a removed wall " + str(direction))
	walls[SOURCE] = true
	runner.assert_true(SimLightPropagation.has_line_of_light(SOURCE, SOURCE, opaque), "an opaque source cell still receives its own light")
	runner.assert_true(not SimLightPropagation.has_line_of_light(SOURCE, SOURCE + Vector2i.RIGHT, opaque), "light does not emerge outward from an opaque source cell")
	runner.assert_true(not SimLightPropagation.has_line_of_light(SOURCE, SOURCE + Vector2i.RIGHT, Callable()), "an invalid geometry callback cannot promise an unobstructed ray")


func _corner_and_slanted_lines(runner: Object) -> void:
	var walls: Dictionary = {}
	var opaque: Callable = func(cell: Vector2i) -> bool: return walls.has(cell)
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			var diagonal := Vector2i(sx, sy)
			var target: Vector2i = SOURCE + diagonal
			for side: Vector2i in [Vector2i(sx, 0), Vector2i(0, sy)]:
				walls[SOURCE + side] = true
				runner.assert_true(not SimLightPropagation.has_line_of_light(SOURCE, target, opaque), "either wall touching the crossed corner blocks diagonal light")
				runner.assert_true(not SimLightPropagation.has_line_of_light(target, SOURCE, opaque), "the same corner blocks the reverse ray")
				walls.clear()
			runner.assert_true(SimLightPropagation.has_line_of_light(SOURCE, target, opaque), "an open diagonal corner transmits light")

	# The ray to (2,1) traverses (1,0) and (1,1). A conventional one-cell
	# Bresenham line can omit one of them; supercover must honor both.
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			var target: Vector2i = SOURCE + Vector2i(2 * sx, sy)
			for intermediate: Vector2i in [Vector2i(sx, 0), Vector2i(sx, sy)]:
				walls[SOURCE + intermediate] = true
				runner.assert_true(not SimLightPropagation.has_line_of_light(SOURCE, target, opaque), "a shallow ray cannot skip a crossed cell")
				runner.assert_true(not SimLightPropagation.has_line_of_light(target, SOURCE, opaque), "a shallow ray has the same obstruction in reverse")
				walls.clear()
			var steep: Vector2i = SOURCE + Vector2i(sx, 2 * sy)
			for intermediate: Vector2i in [Vector2i(0, sy), Vector2i(sx, sy)]:
				walls[SOURCE + intermediate] = true
				runner.assert_true(not SimLightPropagation.has_line_of_light(SOURCE, steep, opaque), "a steep ray cannot skip a crossed cell")
				runner.assert_true(not SimLightPropagation.has_line_of_light(steep, SOURCE, opaque), "a steep ray has the same obstruction in reverse")
				walls.clear()


func _distance_and_intensity(runner: Object) -> void:
	var walls: Dictionary = {}
	var opaque: Callable = func(cell: Vector2i) -> bool: return walls.has(cell)
	var expected: Dictionary = {
		Vector2i.ZERO: 4000, Vector2i(1, 0): 3750, Vector2i(1, 1): 3500,
		Vector2i(2, 0): 3000, Vector2i(3, 0): 1750,
		Vector2i(4, 0): 0, Vector2i(3, 3): 0,
	}
	for displacement: Vector2i in expected:
		var value: int = int(expected[displacement])
		for transform: Vector2i in [displacement, Vector2i(-displacement.x, displacement.y), Vector2i(displacement.x, -displacement.y), Vector2i(displacement.y, displacement.x)]:
			runner.assert_eq(SimLightPropagation.contribution(SOURCE, SOURCE + transform, 4, 4000, opaque), value, "integer radial falloff and symmetry at " + str(transform))
	runner.assert_eq(SimLightPropagation.contribution(SOURCE, SOURCE + Vector2i(1, 1), 3, 1000, opaque), 777, "non-divisible falloff is floored rather than rounded")
	walls[SOURCE + Vector2i.RIGHT] = true
	runner.assert_eq(SimLightPropagation.contribution(SOURCE, SOURCE + Vector2i.RIGHT, 4, 4000, opaque), 3750, "an opaque target is lit on its facing surface")
	runner.assert_eq(SimLightPropagation.contribution(SOURCE, SOURCE + Vector2i.RIGHT * 2, 4, 4000, opaque), 0, "an opaque intermediate cell removes that source contribution")
	walls.clear()
	for invalid_radius: int in [-1, 0, 9]:
		runner.assert_eq(SimLightPropagation.contribution(SOURCE, SOURCE, invalid_radius, 4000, opaque), 0, "an invalid radius contributes no invented light")
	for invalid_peak: int in [-1, 10001]:
		runner.assert_eq(SimLightPropagation.contribution(SOURCE, SOURCE, 4, invalid_peak, opaque), 0, "an invalid peak contributes no invented light")
	runner.assert_eq(SimLightPropagation.contribution(SOURCE, SOURCE, 4, 0, opaque), 0, "zero peak emits zero light")
	runner.assert_eq(SimLightPropagation.contribution(SOURCE, SOURCE + Vector2i.RIGHT, 4, 4000, Callable()), 0, "missing opacity geometry fails closed")


func _emission_ratio(runner: Object) -> void:
	runner.assert_eq(SimLightPropagation.emission_peak(4000, 1000, 1000), 4000, "nominal actual output yields the declared peak")
	runner.assert_eq(SimLightPropagation.emission_peak(4000, 250, 1000), 1000, "a quarter of actual output yields one quarter peak")
	runner.assert_eq(SimLightPropagation.emission_peak(4000, 1, 1000), 4, "a real one-unit final rate is not mistaken for a full source")
	runner.assert_eq(SimLightPropagation.emission_peak(4000, 2000, 1000), 4000, "output exceeding nominal cannot amplify the declared peak")
	runner.assert_eq(SimLightPropagation.emission_peak(1000, 1, 3), 333, "fractional output is floored deterministically")
	runner.assert_eq(SimLightPropagation.emission_peak(10000, MAX_INTEGER - 1, MAX_INTEGER), 9999, "large integers preserve the one-unit deficit without multiplication overflow or float rounding")
	@warning_ignore("integer_division")
	runner.assert_eq(SimLightPropagation.emission_peak(9999, MAX_INTEGER / 2, MAX_INTEGER), 4999, "the integer limit below one half remains below one half")
	for input: Array in [[-1, 1, 1], [10001, 1, 1], [4000, -1, 1], [4000, 1, 0], [4000, 1, -1]]:
		runner.assert_eq(SimLightPropagation.emission_peak(input[0], input[1], input[2]), 0, "invalid output ratio fails closed")
