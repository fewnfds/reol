@tool
class_name SettlementOpeningDef
extends Resource
## One-time initial conditions. Runtime roles, goods and relationships never
## read back from this blueprint after its owners have adopted them.
const Layout = preload("res://scripts/sim/definitions/openings/layout_def.gd")
const Resident = preload("res://scripts/sim/definitions/openings/resident_def.gd")
const Appointment = preload("res://scripts/sim/definitions/openings/appointment_def.gd")
const Department = preload("res://scripts/sim/definitions/openings/department_def.gd")
@export var title: String = ""
@export var district_names: PackedStringArray = []
@export var district_origins: Array[Vector2i] = []
@export_range(2, 128) var residents_per_district: int = 25
@export var soil_areas: Array[Rect2i] = []
@export var layouts: Array[Layout] = []
@export var resident_profiles: Array[Resident] = []
@export var appointments: Array[Appointment] = []
@export var departments: Array[Department] = []
@export var bed_key: String = "beds"
@export var familiar_keys: PackedStringArray = []
@export var spawn_offsets: Array[Vector2i] = []
@export var qi_plant: String = "spirit_bamboo"
@export var qi_offsets: Array[Vector2i] = []
@export_range(0, 10000) var initial_source_qi: int = 0
@export_range(0, 10000) var satiety_min: int = 7000
@export_range(0, 10000) var satiety_span: int = 2500
@export_range(0, 10000) var energy_min: int = 7000
@export_range(0, 10000) var energy_span: int = 2500

func population() -> int:
	return district_origins.size() * residents_per_district
