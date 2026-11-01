class_name TileGrid
extends RefCounted
## Axis-aligned square grid shared by the world, entities and camera.
##
## Cell (0, 0) is the top-left tile; x grows right, y grows down.
## Cell coordinates map 1:1 to world space, which keeps pathfinding,
## collision, fog and save data simple.

const TILE_SIZE: int = 64
const HALF_TILE: float = TILE_SIZE * 0.5


static func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(
		float(cell.x) * TILE_SIZE + HALF_TILE,
		float(cell.y) * TILE_SIZE + HALF_TILE
	)


static func world_to_cell(world: Vector2) -> Vector2i:
	return Vector2i(
		floori(world.x / float(TILE_SIZE)),
		floori(world.y / float(TILE_SIZE))
	)
