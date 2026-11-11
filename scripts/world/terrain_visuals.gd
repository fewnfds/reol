class_name TerrainVisuals
extends RefCounted
## One small deterministic atlas, shared by every tile and elevation layer.

const VARIANTS: int = 4


static func build_natural_image(tile_size: int, surfaces: Dictionary) -> Image:
	var atlas := Image.create(tile_size * NaturalEnvironment.SURFACES.size(), tile_size * VARIANTS, false, Image.FORMAT_RGBA8)
	for column: int in NaturalEnvironment.SURFACES.size():
		var id: String = NaturalEnvironment.SURFACES[column]
		for variant: int in VARIANTS:
			var base := Color(str(surfaces[id].color)).lightened(variant * 0.009)
			var origin := Vector2i(column * tile_size, variant * tile_size)
			atlas.fill_rect(Rect2i(origin, Vector2i(tile_size, tile_size)), base)
			for detail: int in 15:
				var point := origin + Vector2i(3 + (detail * 17 + variant * 11) % (tile_size - 9), 4 + (detail * 23 + variant * 7) % (tile_size - 9))
				var shape := Vector2i(2, 2)
				match id:
					"water": shape = Vector2i(8, 1)
					"stone", "ore_rock", "gravel": shape = Vector2i(4, 3)
					"woodland": shape = Vector2i(4, 1)
				atlas.fill_rect(Rect2i(point, shape), base.lightened(0.07) if detail % 3 == 0 else base.darkened(0.055))
				if id == "ore_rock" and detail % 4 == 0:
					atlas.fill_rect(Rect2i(point + Vector2i(1, 1), Vector2i(2, 1)), Color("#b2a67c"))
	return atlas


@warning_ignore("integer_division")
static func build_flora_image(tile_size: int, flora: Dictionary) -> Image:
	var ids: Array = flora.keys()
	ids.sort()
	var atlas := Image.create(tile_size * ids.size(), tile_size * VARIANTS, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	for index: int in ids.size():
		var plant: Dictionary = flora[ids[index]]
		var color := Color(str(plant.color))
		for variant: int in VARIANTS:
			var origin := Vector2i(index * tile_size, variant * tile_size)
			var foot: Vector2i = origin + Vector2i(tile_size / 2 + (variant % 2) * 5 - 2, tile_size / 2 + 10)
			var height: int = mini(int(plant.height), tile_size - 12)
			match str(plant.kind):
				"tree":
					atlas.fill_rect(Rect2i(foot - Vector2i(2, 9), Vector2i(4, 11)), Color("#6a5943"))
					for tier: int in 3:
						var width: int = 10 + tier * 7
						atlas.fill_rect(Rect2i(foot - Vector2i(width / 2, height - tier * 8), Vector2i(width, 10)), color.lightened(tier * 0.025))
				"bamboo", "reed":
					for stem: int in 3:
						var point: Vector2i = foot + Vector2i((stem - 1) * 7, -height + stem * 3)
						atlas.fill_rect(Rect2i(point, Vector2i(2, height - stem * 3)), color)
						atlas.fill_rect(Rect2i(point - Vector2i(4, -6), Vector2i(10, 2)), color.lightened(0.13))
				"aquatic", "lichen", "moss":
					atlas.fill_rect(Rect2i(foot - Vector2i(9, 4), Vector2i(17, 5)), color)
					atlas.fill_rect(Rect2i(foot - Vector2i(5, 6), Vector2i(10, 2)), color.lightened(0.08))
				_:
					for stem: int in 4:
						var point: Vector2i = foot + Vector2i((stem - 2) * 5, -height + (stem % 2) * 4)
						atlas.fill_rect(Rect2i(point, Vector2i(2, height - (stem % 2) * 4)), color.darkened(0.08))
						atlas.fill_rect(Rect2i(point - Vector2i(2, 0), Vector2i(5, 3)), color.lightened(0.16))
	return atlas


static func variant_for(cell: Vector2i) -> int:
	return int((cell.x * 73856093 ^ cell.y * 19349663) & 0x7fffffff) % VARIANTS
