extends Node2D
## Rebuild a static atlas batch only when immutable observed descriptors change.
## The same buffer drives sprites and bounded solar projections on the GPU.
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Art = preload("res://scripts/presentation/art.gd")
const TILE: float = 32.0
var objects: Dictionary = {}
var by_tile: Dictionary = {}
const ORDER_STRIDE: int = 1048576
var buffer := PackedFloat32Array()
var order := PackedFloat64Array()
var revision: int = 0
var shelter: ImageTexture


func adopt(value: Dictionary) -> void:
    if is_same(objects, value):
        return
    objects = value
    by_tile = {}
    for id: int in objects:
        for tile: int in objects[id].get("cells", PackedInt32Array([objects[id].tile])):
            if not by_tile.has(tile): by_tile[tile] = []
            by_tile[tile].append(id)
    var ids: Array = []
    for id: int in objects:
        if objects[id].kind != "floor": ids.append(id)
    ids.sort_custom(func(a: int, b: int):
        var roof_a: bool = objects[a].get("layer", "") == "roof"
        var roof_b: bool = objects[b].get("layer", "") == "roof"
        return not roof_a if roof_a != roof_b else objects[a].tile < objects[b].tile)
    var covered := PackedByteArray()
    covered.resize(512 * 512)
    for rec: Dictionary in objects.values():
        if rec.kind == "roof":
            for tile: int in rec.get("cells", PackedInt32Array([rec.tile])):
                covered[tile] = 255
    var image := Image.create_from_data(512, 512, false, Image.FORMAT_R8, covered)
    if shelter == null:
        shelter = ImageTexture.create_from_image(image)
    else:
        shelter.update(image)
    buffer = PackedFloat32Array()
    buffer.resize(ids.size() * 16)
    order = PackedFloat64Array()
    for index: int in ids.size():
        var rec: Dictionary = objects[ids[index]]
        var key: String = _key(rec)
        var source: Dictionary = Art.catalog().entries.get(key, Art.catalog().entries.rock)
        var extent := Rect2i(Terrain.cell(rec.tile), Vector2i.ONE)
        for tile: int in rec.get("cells", PackedInt32Array([rec.tile])):
            extent = extent.merge(Rect2i(Terrain.cell(tile), Vector2i.ONE))
        var point: Vector2 = Vector2(extent.position.x + extent.size.x * 0.5, extent.end.y) * TILE
        var scale_value := Vector2(0.65, 0.65)
        var tall: bool = rec.kind == "resource" or (rec.kind == "plant" and rec.definition == "old_tree")
        if tall:
            scale_value = Vector2.ONE * (1.2 if rec.kind == "resource" else 1.0)
        elif rec.kind in ["wall", "door", "roof"] or (rec.kind == "blueprint" and rec.definition in ["wood_wall", "wood_door", "wood_roof", "wood_floor"]):
            scale_value = Vector2.ONE
        elif extent.size != Vector2i.ONE:
            scale_value = Vector2(maxf(0.65, extent.size.x * TILE / 54.0), maxf(0.65, extent.size.y * TILE / 48.0))
        var color := Color.WHITE
        if rec.kind == "blueprint": color = Color(0.45, 0.95, 1.0, 0.50)
        if rec.get("layer", "") == "roof": color.a = 0.24
        var special: int = 0
        if rec.kind == "plant" and rec.definition == "fire_herb" and int(rec.get("stage", 0)) == 2: special = 1
        if rec.get("sapient", false): special = 2
        var offset: int = index * 16
        buffer[offset] = scale_value.x
        buffer[offset + 3] = point.x
        buffer[offset + 5] = scale_value.y
        buffer[offset + 7] = point.y
        buffer[offset + 8] = color.r
        buffer[offset + 9] = color.g
        buffer[offset + 10] = color.b
        buffer[offset + 11] = color.a
        buffer[offset + 12] = Terrain.center(rec.tile).x * TILE
        buffer[offset + 13] = Terrain.center(rec.tile).y * TILE
        buffer[offset + 14] = int(source.slot)
        var anchor: Array = source.anchor
        var sway: int = int(tall and int(rec.get("stage", 2)) not in [3, 4] and not (rec.kind == "resource" and int(rec.get("vegetation_level", 3)) < 3))
        buffer[offset + 15] = 128 + sway * 256 + special * 512 + int(anchor[0]) * 2048 + int(anchor[1]) * 131072
        var depth: int = int(point.y * 256.0) + (1 << 26 if rec.get("layer", "") == "roof" else 0)
        order.append(float(depth * ORDER_STRIDE + index))
    order.sort()
    revision += 1

func _key(rec: Dictionary) -> String:
    match rec.kind:
        "wall":
            var mask: int = 0
            var cell: Vector2i = Terrain.cell(rec.tile)
            var neighbours: Array[Vector2i] = [cell + Vector2i.UP, cell + Vector2i.RIGHT, cell + Vector2i.DOWN, cell + Vector2i.LEFT]
            for side: int in 4:
                var next: Vector2i = neighbours[side]
                if next.x < 0 or next.y < 0 or next.x >= 512 or next.y >= 512: continue
                for other: int in by_tile.get(Terrain.index(next), []):
                    if objects[other].kind in ["wall", "door"]:
                        mask |= 1 << side
                        break
            return "wall_%d" % mask
        "door":
            var point: Vector2i = Terrain.cell(rec.tile)
            for delta: Vector2i in [Vector2i.UP, Vector2i.DOWN]:
                var cell: Vector2i = point + delta
                if cell.x < 0 or cell.y < 0 or cell.x >= 512 or cell.y >= 512: continue
                for id: int in by_tile.get(Terrain.index(cell), []):
                    if objects[id].kind == "wall": return "door_v"
            return "door"
        "resource":
            var level: int = int(rec.get("vegetation_level", 3))
            return "item_wood" if level == 0 else ("stump" if level == 2 else ("pine" if rec.tile % 3 == 0 else "oak"))
        "landmark": return "well" if rec.definition == "well" else "lantern"
        "plant":
            var stage: int = clampi(int(rec.get("stage", 0)), 0, 4)
            if rec.definition == "old_tree":
                return "tree_spirit" if rec.get("sapient", false) and stage == 2 else "old_tree_%d" % stage
            return "%s_%d" % [rec.definition, stage]
        "chest": return "chest"
        "pile": return "item_" + rec.definition if Art.catalog().entries.has("item_" + rec.definition) else "item_bundle"
    # A pending floor uses the same flat, tile-sized preview as a roof; the
    # completed floor is drawn in the ground atlas, never as a furniture icon.
    var mapping: Dictionary = {"wood_wall": "wall_0", "wood_door": "door", "wood_bed": "bed", "long_bed": "bed", "wood_chest": "chest", "cook_stove": "stove", "wood_table": "table", "wood_chair": "chair", "wood_roof": "roof", "wood_floor": "roof", "planter": "planter"}
    return str(mapping.get(rec.definition, "workbench"))
