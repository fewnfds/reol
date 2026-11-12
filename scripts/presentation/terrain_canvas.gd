extends Node2D
## One indexed ground texture and one atlas draw; fog ground stays last-observed.
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Art = preload("res://scripts/presentation/art.gd")
const TILE: float = 32.0
const MemoryShader = preload("res://scripts/presentation/terrain.gdshader")
const SOURCE_COLORS: Array[Color] = [Color.ORANGE_RED, Color.SKY_BLUE, Color.SILVER, Color.LIME_GREEN, Color.DODGER_BLUE, Color.RED, Color.SANDY_BROWN]
var terrain: RefCounted
var use_memory: bool = false
var _memory_revision: int = -1
var _memory_texture: ImageTexture
var _memory_material := ShaderMaterial.new()

func adopt(value: RefCounted, knowledge: Dictionary = {}) -> void:
    var next_revision: int = int(knowledge.get("revision", -1)) if use_memory else -1
    if terrain == value and _memory_revision == next_revision: return
    var geometry_changed: bool = terrain != value
    terrain = value
    _memory_revision = next_revision
    var bytes: PackedByteArray
    if use_memory and knowledge.has("ground"):
        bytes = knowledge.ground
    elif geometry_changed:
        bytes.resize(512 * 512)
        for tile: int in bytes.size(): bytes[tile] = terrain.surface_at(tile)
    else: return
    var image := Image.create_from_data(512, 512, false, Image.FORMAT_R8, bytes)
    if _memory_texture == null:
        _memory_texture = ImageTexture.create_from_image(image)
        _memory_material.shader = MemoryShader
        _memory_material.set_shader_parameter("ground_map", _memory_texture)
        _memory_material.set_shader_parameter("tile_atlas", Art.GROUND)
    else: _memory_texture.update(image)
    _memory_material.set_shader_parameter("use_fog", use_memory)
    material = _memory_material
    queue_redraw()

func visibility(texture: Texture2D) -> void:
    _memory_material.set_shader_parameter("visible_map", texture)

func _draw() -> void:
    if terrain != null: draw_rect(Rect2(0, 0, 512 * TILE, 512 * TILE), Color.WHITE)
