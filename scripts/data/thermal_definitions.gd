class_name ThermalDefinitions
extends RefCounted
## Validates the bound thermal device parameters. This owns no field state and
## does not depend on a historical heat solver or a save migration.

const VERSION: int = 3
const MAX_INTEGER: int = SimInventory.MAX_COUNT
const Shape = preload("res://scripts/sim/avian_schema.gd")


static func is_valid(data: Variant) -> bool:
	if not Shape.keys(data, ["version", "step_ms", "sample_ms", "world_size", "capacity_per_tenth", "pulse_energy", "coefficient_scale", "conductance", "bath_loss", "source_radius", "max_cells", "max_cell_energy", "max_total_input", "reference_tenths", "max_exchange_energy"]):
		return false
	if not Shape.count(data.version, VERSION, VERSION) or not Shape.count(data.reference_tenths, -10000, -10000) or not Shape.count(data.max_exchange_energy, 1, MAX_INTEGER):
		return false
	if not Shape.count(data.step_ms, 1, 60000) or not Shape.count(data.sample_ms, int(data.step_ms), 3600000) or int(data.sample_ms) % int(data.step_ms) != 0 or not Shape.count(data.world_size, 1, 100000):
		return false
	if not Shape.count(data.capacity_per_tenth, 1, 1000000000) or not Shape.count(data.coefficient_scale, 1, 1000000) or not Shape.count(data.source_radius, 0, 8) or not Shape.count(data.max_cells, 1, 8192):
		return false
	if not Shape.count(data.max_cell_energy, 13000 * int(data.capacity_per_tenth) + 1, 14000000000000):
		return false
	if not Shape.count(data.pulse_energy, 1, int(data.max_cell_energy)) or not Shape.count(data.max_total_input, int(data.pulse_energy), MAX_INTEGER):
		return false
	if not Shape.keys(data.conductance, ["open", "open_door", "wall", "closed_door"]) or not Shape.keys(data.bath_loss, ["roofed", "unroofed"]):
		return false
	var greatest_edge: int = 0
	var greatest_bath: int = 0
	for value: Variant in data.conductance.values():
		if not Shape.count(value, 0, int(data.coefficient_scale)):
			return false
		greatest_edge = maxi(greatest_edge, int(value))
	for value: Variant in data.bath_loss.values():
		if not Shape.count(value, 0, int(data.coefficient_scale)):
			return false
		greatest_bath = maxi(greatest_bath, int(value))
	return 4 * greatest_edge + greatest_bath <= int(data.coefficient_scale)
