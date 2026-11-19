extends Node2D
## Rebuild a static atlas batch only when immutable observed descriptors change.
## The same buffer drives sprites and bounded ground contact on the GPU.
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Art = preload("res://scripts/presentation/art.gd")
const Definitions = preload("res://scripts/sim/kernel/operation_query.gd")
const TILE: float = Art.TILE
var objects: Dictionary = {}
var by_tile: Dictionary = {}
const ORDER_STRIDE: int = 1048576
var buffer := PackedFloat32Array()
var order := PackedFloat64Array()
var identities := PackedInt64Array()
var revision: int = 0
var _source: Dictionary = {}
var _fringe: Dictionary = {}


func adopt(value: Dictionary, fringe: Dictionary = {}) -> void:
    if is_same(_source, value) and (is_same(_fringe, fringe) or (_fringe.is_empty() and fringe.is_empty())):
        return
    _source = value
    _fringe = fringe
    objects = value if fringe.is_empty() else value.duplicate()
    if not fringe.is_empty(): objects.merge(fringe, false)
    by_tile = {}
    for id: int in objects:
        for tile: int in objects[id].get("cells", PackedInt32Array([objects[id].tile])):
            if not by_tile.has(tile): by_tile[tile] = []
            by_tile[tile].append(id)
    var sprites: Array[Dictionary] = []
    for id: int in objects:
        var rec: Dictionary = objects[id]
        if rec.kind in ["floor", "combat_object"]: continue
        if rec.kind == "blueprint" and rec.get("construction_started", false):
            var members: PackedInt32Array = rec.get("cells", PackedInt32Array([rec.tile]))
            for tile: int in members:
                var mask: int = 0
                var cell: Vector2i = Terrain.cell(tile)
                var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
                for side: int in 4:
                    var neighbour: Vector2i = cell + directions[side]
                    if neighbour.x >= 0 and neighbour.y >= 0 and neighbour.x < 512 and neighbour.y < 512 and members.has(Terrain.index(neighbour)): mask |= 1 << side
                var part: Dictionary = rec.duplicate()
                part.tile = tile
                part.cells = PackedInt32Array([tile])
                part["construction_mask"] = mask
                sprites.append(part)
        else: sprites.append(rec)
    var visual_parts: Array[Dictionary] = []
    for rec: Dictionary in sprites:
        var key: String = str(rec.get("art_key", _key(rec)))
        var source: Dictionary = Art.catalog().entries.get(key, Art.catalog().entries.rock)
        for part: Dictionary in source.get("parts", [{"key":key, "offset":[0,0], "depth":0}]):
            var visual: Dictionary = rec.duplicate()
            visual["art_key"] = part.key
            visual["part_offset"] = Vector2(part.offset[0], part.offset[1])
            visual["part_depth"] = float(part.depth)
            visual["contact_shadow"] = bool(part.get("contact_shadow", source.get("contact_shadow", true)))
            if part.has("occluder") or source.has("occluder"): visual["occluder"] = bool(part.get("occluder",source.get("occluder",false)))
            visual_parts.append(visual)
    sprites = visual_parts
    sprites.sort_custom(func(a: Dictionary, b: Dictionary): return a.tile < b.tile)
    buffer = PackedFloat32Array()
    buffer.resize(sprites.size() * 16)
    order = PackedFloat64Array()
    identities = PackedInt64Array()
    for index: int in sprites.size():
        var rec: Dictionary = sprites[index]
        var key: String = str(rec.get("art_key", _key(rec)))
        var source: Dictionary = Art.catalog().entries.get(key, Art.catalog().entries.rock)
        var extent := Rect2i(Terrain.cell(rec.tile), Vector2i.ONE)
        for tile: int in rec.get("cells", PackedInt32Array([rec.tile])):
            extent = extent.merge(Rect2i(Terrain.cell(tile), Vector2i.ONE))
        # Art parts place their own pivot/depth relative to the shared footprint.
        var point: Vector2 = Art.footprint_foot(extent) * TILE
        var scale_value := Vector2(0.65, 0.65)
        var tall: bool = (rec.kind == "resource" and int(rec.get("vegetation_level", 3)) >= 3) or (rec.kind == "plant" and rec.definition == "old_tree" and int(rec.get("stage", 0)) in [2,4])
        if tall:
            scale_value = Vector2.ONE * (1.2 if rec.kind == "resource" else 1.0)
        if source.has("footprint"):
            var art_cells: Array = source.footprint
            scale_value = Vector2(float(extent.size.x) / int(art_cells[0]), float(extent.size.y) / int(art_cells[1]))
        var sort_y: float = point.y + float(rec.get("part_depth", 0.0)) * scale_value.y
        point += Vector2(rec.get("part_offset", Vector2.ZERO)) * scale_value
        var material: String = str(Definitions.BUILDINGS.get(rec.definition, {}).get("item", ""))
        var color: Color = Color("8ab6dc") if material == "stone" else Color.WHITE
        if rec.kind == "blueprint" and not rec.get("construction_started", false): color *= Color(0.45, 0.95, 1.0, 0.50)
        var special: int = 0
        if rec.kind == "plant" and rec.definition == "fire_herb" and int(rec.get("stage", 0)) == 2: special = 1
        if rec.get("sapient", false): special = 2
        identities.append(int(rec.id))
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
        var ground_fog: int = int(not tall)
        # Low bit is free for scenery; bits 9-10 already encode special effects.
        var occluder: int = int(rec.kind != "blueprint" and bool(rec.get("occluder", tall)))
        buffer[offset + 15] = 128 + occluder * 2 + int(not rec.get("contact_shadow", true)) * 4 + ground_fog + sway * 256 + special * 512 + int(anchor[0]) * 2048 + int(anchor[1]) * 131072
        var plane: Art.DrawPlane = Art.DrawPlane.BODY
        if source.get("plane", "") == "ground" or rec.kind == "pile" or (rec.kind == "blueprint" and not rec.get("construction_started", false)): plane = Art.DrawPlane.GROUND
        var depth: int = Art.depth(sort_y, plane)
        order.append(float(depth * ORDER_STRIDE + index))
    order.sort()
    revision += 1

func _key(rec: Dictionary) -> String:
    if rec.has("construction_mask"): return "construction_%d" % int(rec.construction_mask)
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
            return ("wall_eaves_%d" if rec.get("eaves", false) else "wall_%d") % mask
        "door": return _door_key(rec)
        "rock": return "rock"
        "resource":
            var level: int = int(rec.get("vegetation_level", 3))
            return "item_wood" if level == 0 else ("stump" if level == 2 else ("pine" if rec.tile % 3 == 0 else "oak"))
        "landmark": return "well" if rec.definition == "well" else "lantern"
        "plant":
            var stage: int = clampi(int(rec.get("stage", 0)), 0, 4)
            if rec.definition == "old_tree":
                return "tree_spirit" if rec.get("sapient", false) and stage == 2 else "old_tree_%d" % stage
            return "%s_%d" % [Definitions.PLANTS.get(rec.definition, {}).get("art_base", rec.definition), stage]
        "chest": return _facing_key(str(Definitions.BUILDINGS.get(rec.definition, {}).get("art_key", "chest")), rec)
        "pile": return "item_" + rec.definition if Art.catalog().entries.has("item_" + rec.definition) else "item_bundle"
    # A pending floor uses the ground-level material preview; completed floors
    # are drawn in the terrain atlas, never as raised furniture.
    var mapping: Dictionary = {"wood_wall": "wall_0", "wood_door": "door", "wood_bed": "bed", "long_bed": "long_bed", "wood_chest": "chest", "cook_stove": "stove", "wood_table": "table", "wood_chair": "chair", "wood_floor": "floor_preview", "planter": "planter", "water_well": "planter", "wood_screen": "screen", "wood_window": "window", "stone_wall": "wall_0", "desk_chair": "chair"}
    return _facing_key(str(Definitions.BUILDINGS.get(rec.definition, {}).get("art_key", mapping.get(rec.definition, "workbench"))), rec)


func _facing_key(key: String, rec: Dictionary) -> String:
    var facing: int = int(rec.get("facing", 0))
    if key == "door":
        return _door_key(rec)
    var variant: String = "%s_%d" % [key, facing]
    return variant if facing > 0 and Art.catalog().entries.has(variant) else key


func _door_key(rec: Dictionary) -> String:
    var point: Vector2i = Terrain.cell(rec.tile)
    var horizontal: bool = false
    var vertical: bool = false
    for delta: Vector2i in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
        var cell: Vector2i = point + delta
        if cell.x < 0 or cell.y < 0 or cell.x >= 512 or cell.y >= 512: continue
        for id: int in by_tile.get(Terrain.index(cell), []):
            if objects[id].kind != "wall": continue
            if delta.x == 0: vertical = true
            else: horizontal = true
    # Ambiguous junctions preserve the author's explicit facing.
    if vertical != horizontal: return "door_v" if vertical else "door"
    return "door_v" if int(rec.get("facing",0)) % 2 == 1 else "door"
