extends RefCounted
## Detached values. Publication ends all writes to this object and its arrays.
## A slow consumer can retain old frames without blocking simulation.

enum Visual { IDLE, WALK, CARRY, HARVEST, BUILD, CRAFT, MELEE, SHOOT, HURT, REST, EAT, READ, MEDITATE, FLY, DEAD, WATER }

class Pose extends RefCounted:
	var world_ms: int
	var completed_usec: int
	var positions := PackedVector2Array()
	var ids := PackedInt64Array()

var projectiles := PackedVector2Array()
var projectile_velocities := PackedVector2Array()
var sequence: int
var world_ms: int
var published_usec: int
var speed: float
var paused: bool
var epoch: int = 1
var ids := PackedInt64Array()
var actor_slots: Dictionary = {}
var objects: Dictionary = {}
var perception: Dictionary = {}
var visible := PackedByteArray()
var positions := PackedVector2Array()
var history: Array[RefCounted] = []
var health := PackedInt32Array()
var modes := PackedByteArray()
var flight := PackedByteArray()
var radii := PackedFloat32Array()
var visuals := PackedByteArray() # Detached action presentation; never used by settlement.
var inspected: Dictionary = {}
var player: Dictionary = {} # Always present independently of selection/scroll position.
var counters: Dictionary = {}
var tides := PackedInt32Array()
var mobile_cells := PackedInt32Array()
var source_enabled := PackedByteArray()
var room_temperature := PackedFloat32Array()
var terrain: RefCounted
var tile_probe: Dictionary = {}
