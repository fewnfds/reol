extends RefCounted
## Detached values. Publication ends all writes to this object and its arrays.
## A slow consumer can retain old frames without blocking simulation.

class Pose extends RefCounted:
	var world_ms: int
	var completed_usec: int
	var positions := PackedVector2Array()

var sequence: int
var world_ms: int
var published_usec: int
var speed: float
var paused: bool
var positions := PackedVector2Array()
var history: Array[RefCounted] = []
var health := PackedInt32Array()
var modes := PackedByteArray()
var inspected: Dictionary = {}
var counters: Dictionary = {}
var tides := PackedInt32Array()
var mobile_cells := PackedInt32Array()
var source_enabled := PackedByteArray()
var room_temperature := PackedFloat32Array()
var terrain: RefCounted
var tile_probe: Dictionary = {}
