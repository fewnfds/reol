extends RefCounted
## The cache is an isolated F1 candidate, not a new world owner. The F0 index
## provides an independent per-point oracle for exact values, including its
## integer Euclidean kernel and rounding.

const Cache = preload("res://scripts/sim/environment_field_cache.gd")
const Index = preload("res://scripts/sim/environment_field_index.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const CHANNELS: int = 7


func run(runner: Object) -> void:
	_compare_mixed_map_and_changes(runner)
	_bounded_work_and_atomic_rejection(runner)
	_separate_distant_footprints(runner)
	_conservative_bound_after_removal(runner)
	_compute_snapshot_and_publish(runner)
	_compute_worker_prepare_and_publish(runner)
	_empty_compute_snapshot(runner)
	_compact_compute_snapshot(runner)
	print("SCENARIO environment field cache: exact F0 comparison, mixed sources, bounded pending, winner removal and distinct old/new invalidation")


func _compare_mixed_map_and_changes(runner: Object) -> void:
	var size := Vector2i(35, 19)
	var cache := Cache.new()
	var reference := Index.new()
	runner.assert_true(cache.configure(size, 48) and reference.configure(size, 48), "the packed and reference fields configure independently")
	_set_both(cache, reference, 0, Vector2i(1, 1), 4, [9000, 2, 0, 200, 0, 12000, 0], runner)
	_set_both(cache, reference, 1, Vector2i(1, 1), 4, [7000, 3, 0, 0, 0, 5000, 2000], runner)
	_set_both(cache, reference, 2, Vector2i(15, 16), 8, [0, 7000, 4000, 0, 9000, 0, 14000], runner)
	_set_both(cache, reference, 3, Vector2i(34, 18), 1, [900, 800, 700, 600, 500, 400, 300], runner)
	_set_both(cache, reference, 4, Vector2i(16, 0), 3, [0, 0, 0, 0, 0, 0, 0], runner)
	_set_both(cache, reference, 40, Vector2i(34, 0), 2, [Rules.MAX_GRADE_MILLI, 0, 0, 0, 0, 0, 0], runner)
	var random := RandomNumberGenerator.new()
	random.seed = 816017
	for slot: int in range(5, 40):
		var cell := Vector2i(random.randi_range(0, size.x - 1), random.randi_range(0, size.y - 1))
		var grades: Array[int] = []
		for channel: int in CHANNELS:
			grades.append(0 if random.randi_range(0, 3) == 0 else random.randi_range(1, 30000))
		_set_both(cache, reference, slot, cell, random.randi_range(1, 7), grades, runner)

	_request_all(cache, size, runner)
	_drain(cache, runner)
	_compare_all(cache, reference, size, runner, "initial mixed field")
	# The changed source has a new radius and crosses several tile boundaries;
	# removing the earlier winner exposes its co-located weaker source.
	runner.assert_true(bool(cache.remove_source(0).ok) and bool(reference.remove_source("s_0").ok), "removing the strongest source is accepted by both projections")
	_set_both(cache, reference, 2, Vector2i(31, 2), 5, [0, 5000, 1500, 0, 9000, 0, 17000], runner)
	_set_both(cache, reference, 3, Vector2i(0, 18), 6, [900, 800, 700, 600, 500, 400, 300], runner)
	runner.assert_true(bool(cache.read_base(Vector2i(1, 1)).pending), "old winner's tile stays unavailable until rebuilt")
	_drain(cache, runner)
	_compare_all(cache, reference, size, runner, "field after removal, radius change and move")
	var returned: Dictionary = cache.read_base(Vector2i(1, 1))
	var expected: PackedInt32Array = returned.channels.duplicate()
	var caller_copy: PackedInt32Array = returned.channels
	caller_copy[0] = 1
	runner.assert_eq(cache.read_base(Vector2i(1, 1)).channels, expected, "the returned seven values cannot mutate the cached tile")


func _bounded_work_and_atomic_rejection(runner: Object) -> void:
	var cache := Cache.new()
	runner.assert_true(cache.configure(Vector2i(32, 16), 3), "the pending fixture configures")
	runner.assert_true(bool(cache.set_source(0, Vector2i(15, 7), 4, [1000, 0, 0, 0, 0, 4000, 0]).ok), "a source near a tile boundary is accepted")
	var requested: Dictionary = cache.read_base(Vector2i(16, 7))
	runner.assert_true(bool(requested.ok) and bool(requested.pending) and not requested.has("channels"), "a first read requests work without returning an invented or partial value")
	var tiny: Dictionary = cache.rebuild(1, 1)
	runner.assert_true(bool(tiny.ok) and int(tiny.work) <= 1 and int(tiny.completed) == 0, "one work unit cannot silently rebuild a tile")
	runner.assert_true(bool(cache.read_base(Vector2i(16, 7)).pending), "the private partial tile remains unavailable")
	var partial: Dictionary = cache.rebuild(1, 400)
	runner.assert_true(bool(partial.ok) and int(partial.completed) == 0 and bool(cache.read_base(Vector2i(16, 7)).pending), "a partly searched tile cannot leak through a read")
	var before: Dictionary = cache.diagnostics().duplicate(true)
	var invalid: Array[Dictionary] = [
		cache.set_source(-1, Vector2i.ZERO, 1, [1, 0, 0, 0, 0, 0, 0]),
		cache.set_source(3, Vector2i.ZERO, 1, [1, 0, 0, 0, 0, 0, 0]),
		cache.set_source(0, Vector2i(-1, 0), 1, [1, 0, 0, 0, 0, 0, 0]),
		cache.set_source(0, Vector2i.ZERO, 0, [1, 0, 0, 0, 0, 0, 0]),
		cache.set_source(0, Vector2i.ZERO, Rules.MAX_RADIUS + 1, [1, 0, 0, 0, 0, 0, 0]),
		cache.set_source(0, Vector2i.ZERO, 1, [1, 0, 0, 0, 0, 0]),
		cache.set_source(0, Vector2i.ZERO, 1, [1, 0, 0, 0, 0, 0, Rules.MAX_GRADE_MILLI + 1]),
		cache.set_source(0, Vector2i.ZERO, 1, [1, 0, 0, 0, 0, 0, -1]),
		cache.remove_source(1), cache.rebuild(0), cache.rebuild(1, 0),
		cache.read_base(Vector2i(32, 0)),
	]
	for rejected: Dictionary in invalid:
		runner.assert_true(not bool(rejected.ok) and not str(rejected.get("reason", "")).is_empty(), "invalid source, budget or read returns a failure")
	runner.assert_eq(cache.diagnostics(), before, "rejected operations leave the source, revision and pending work untouched")
	# A linked-list change while work is in progress must restart the private
	# draft; it cannot leak an old winner or skip another source in that cell.
	runner.assert_true(bool(cache.set_source(1, Vector2i(15, 7), 4, [2000, 0, 0, 0, 0, 6000, 0]).ok), "another source may share the same projected cell")
	runner.assert_true(bool(cache.remove_source(0).ok), "the first source can be removed while the tile is pending")
	runner.assert_true(bool(cache.read_base(Vector2i(16, 7)).pending), "restarted work remains pending")
	_drain(cache, runner)
	var final: Dictionary = cache.read_base(Vector2i(16, 7))
	runner.assert_true(not bool(final.pending), "the bounded queue eventually publishes its complete tile")
	runner.assert_eq(int(final.channels[0]), 1500, "the retained source contributes its exact distance-one strength")
	runner.assert_eq(int(final.channels[5]), 4500, "the retained thermal channel uses the same integer kernel")


func _separate_distant_footprints(runner: Object) -> void:
	var cache := Cache.new()
	runner.assert_true(cache.configure(Vector2i(80, 16), 2), "the distant move fixture configures")
	runner.assert_true(bool(cache.set_source(0, Vector2i(2, 7), 3, [8000, 0, 0, 0, 0, 0, 0]).ok), "the source starts at one map end")
	for cell: Vector2i in [Vector2i(2, 7), Vector2i(40, 7), Vector2i(77, 7)]:
		cache.read_base(cell)
	_drain(cache, runner)
	var middle_before: Dictionary = cache.read_base(Vector2i(40, 7))
	var moved: Dictionary = cache.set_source(0, Vector2i(77, 7), 3, [8000, 0, 0, 0, 0, 0, 0])
	runner.assert_true(bool(moved.ok) and moved.old_area.has_point(Vector2i(2, 7)) and moved.new_area.has_point(Vector2i(77, 7)), "move reports two separately clipped footprints")
	runner.assert_true(not moved.old_area.has_point(Vector2i(40, 7)) and not moved.new_area.has_point(Vector2i(40, 7)), "the middle of a long jump is not an affected footprint")
	var middle_after: Dictionary = cache.read_base(Vector2i(40, 7))
	runner.assert_true(not bool(middle_after.pending) and middle_after.channels == middle_before.channels, "an unrelated cached middle tile remains readable")
	runner.assert_true(bool(cache.read_base(Vector2i(2, 7)).pending) and bool(cache.read_base(Vector2i(77, 7)).pending), "both old and new cached ends are pending")
	_drain(cache, runner)
	runner.assert_eq(int(cache.read_base(Vector2i(2, 7)).channels[0]), 0, "the old end loses the moved source")
	runner.assert_eq(int(cache.read_base(Vector2i(77, 7)).channels[0]), 8000, "the new end has the source's unchanged nominal peak")
	runner.assert_eq(cache.diagnostics().source_count, 1, "a long move does not duplicate the projected source")


func _conservative_bound_after_removal(runner: Object) -> void:
	var cache := Cache.new()
	var reference := Index.new()
	var size := Vector2i(24, 8)
	runner.assert_true(cache.configure(size, 4) and reference.configure(size, 4), "the mixed-radius upper-bound fixture configures")
	_set_both(cache, reference, 0, Vector2i(3, 4), 1, [1000000, 0, 0, 0, 0, 0, 0], runner)
	_set_both(cache, reference, 1, Vector2i(8, 4), 8, [9000, 2000, 0, 0, 0, 0, 0], runner)
	_set_both(cache, reference, 2, Vector2i(4, 4), 1, [10, 9, 0, 0, 0, 0, 0], runner)
	_request_all(cache, size, runner)
	_drain(cache, runner)
	_compare_all(cache, reference, size, runner, "unequal radii and global source maxima")
	runner.assert_eq(int(cache.read_base(Vector2i(4, 4)).channels[0]), 4500, "a weak local source does not hide the farther wider source")
	runner.assert_true(bool(cache.remove_source(0).ok) and bool(reference.remove_source("s_0").ok), "the source providing a conservative maximum can be removed")
	_drain(cache, runner)
	_compare_all(cache, reference, size, runner, "stale high upper bound after strongest source removal")
	runner.assert_eq(int(cache.read_base(Vector2i(4, 4)).channels[0]), 4500, "a stale high global upper bound only costs work; it cannot hide the remaining source")
	runner.assert_true(bool(cache.remove_source(1).ok) and bool(reference.remove_source("s_1").ok), "the only wide source can be removed")
	_drain(cache, runner)
	_compare_all(cache, reference, size, runner, "maximum radius shrinks after removal")
	runner.assert_eq(int(cache.read_base(Vector2i(4, 4)).channels[0]), 10, "radius shrink retains the surviving local source")
	runner.assert_true(bool(cache.remove_source(2).ok) and bool(reference.remove_source("s_2").ok), "the last source can be removed")
	_drain(cache, runner)
	_compare_all(cache, reference, size, runner, "no sources after a previously high upper bound")
	runner.assert_eq(int(cache.read_base(Vector2i(4, 4)).channels[0]), 0, "an empty world cannot manufacture a source")


func _compute_snapshot_and_publish(runner: Object) -> void:
	var size := Vector2i(35, 19)
	var cache := Cache.new()
	var other := Cache.new()
	var reference := Index.new()
	runner.assert_true(cache.configure(size, 4) and other.configure(size, 4) and reference.configure(size, 4), "independent compute fixtures configure")
	_set_both(cache, reference, 0, Vector2i(3, 4), 4, [100, 20, 30, 40, 50, 60, 70], runner)
	_set_both(cache, reference, 1, Vector2i(6, 5), 5, [200, 500, 300, 400, 500, 600, 700], runner)
	_set_both(cache, reference, 2, Vector2i(34, 18), 3, [800, 20, 0, 50, 0, 40, 0], runner)
	_set_both(cache, reference, 3, Vector2i(8, 8), 2, [0, 0, Rules.MAX_GRADE_MILLI, 0, 0, 0, 0], runner)
	var initial: Dictionary = cache.diagnostics().duplicate(true)
	for bad_area: Rect2i in [Rect2i(), Rect2i(1, 0, 15, 16), Rect2i(0, 0, 15, 16),
		Rect2i(0, 0, 16, 17), Rect2i(-16, 0, 16, 16), Rect2i(32, 16, 4, 3)]:
		runner.assert_true(not bool(cache.export_compute_job(bad_area).ok), "an empty, misaligned or out-of-bounds compute area is rejected")
	runner.assert_eq(cache.diagnostics(), initial, "invalid compute areas do not request a tile or change sources")
	# The separate right-hand tile starts a CPU draft before the left tile is
	# exported. Publishing the left result must not cancel the other draft.
	runner.assert_true(bool(cache.read_base(Vector2i(16, 8)).pending), "the independent right-hand tile is pending")
	var begun: Dictionary = cache.rebuild(1, 1)
	runner.assert_true(bool(begun.ok) and int(begun.completed) == 0, "the other tile has started bounded private work")
	var area := Rect2i(0, 0, 16, 16)
	var job: Dictionary = cache.export_compute_job(area)
	runner.assert_true(bool(job.ok) and int(job.owner_token) == cache.get_instance_id(), "the export identifies the owning cache")
	runner.assert_eq(job.params, PackedInt32Array([35, 19, 4, 5, 0, 0, 16, 16]), "the export describes the map, capacity, maximum radius and requested area")
	runner.assert_eq(job.compute_params, job.params, "the noncompact compute coordinates retain the original full-map layout")
	runner.assert_eq(job.heads.size(), size.x * size.y, "the snapshot contains one head per map cell")
	runner.assert_eq(job.slots.size(), 4 * 11, "the snapshot contains the fixed slot layout")
	_assert_snapshot_sources(job, runner)
	runner.assert_eq(job.radius_offsets[2], 0, "the first encountered radius starts the kernel table")
	runner.assert_eq(job.radius_offsets[3], 4, "radius offsets advance by the previous squared radius")
	runner.assert_eq(job.radius_offsets[4], 13, "multiple distinct radii have separate tables")
	runner.assert_eq(job.radius_offsets[5], 29, "kernel offsets use each distinct active radius")
	runner.assert_eq(job.radius_offsets[1], -1, "inactive radii do not invent a table")
	# Returned arrays can be modified by a caller without changing the packed
	# source index or a future export from it.
	var changed_heads: PackedInt32Array = job.heads
	var changed_slots: PackedInt32Array = job.slots
	var changed_kernels: PackedInt32Array = job.kernels
	var changed_offsets: PackedInt32Array = job.radius_offsets
	changed_heads[4 * size.x + 3] = -1
	changed_slots[4 * 4] = 999999
	changed_kernels[0] = 0
	changed_offsets[4] = -1
	job.heads = changed_heads
	job.slots = changed_slots
	job.kernels = changed_kernels
	job.radius_offsets = changed_offsets
	var fresh: Dictionary = cache.export_compute_job(area)
	runner.assert_eq(fresh.heads[4 * size.x + 3], 0, "editing exported heads cannot remove the original projected source")
	runner.assert_eq(fresh.slots[4 * 4], 100, "editing exported slots cannot alter an original projected grade")
	_assert_snapshot_sources(fresh, runner)
	runner.assert_eq(fresh.kernels[0], Rules.SCALE, "editing exported kernel data cannot alter the retained kernel")
	runner.assert_eq(fresh.radius_offsets[4], 13, "editing exported offsets cannot alter a later snapshot")
	var values: PackedInt32Array = _reference_values(reference, area)
	var before: Dictionary = cache.diagnostics().duplicate(true)
	var short_values: PackedInt32Array = values.duplicate()
	short_values.resize(short_values.size() - 1)
	var negative_values: PackedInt32Array = values.duplicate()
	negative_values[negative_values.size() - 1] = -1
	var large_values: PackedInt32Array = values.duplicate()
	large_values[large_values.size() - 1] = Rules.MAX_GRADE_MILLI + 1
	var bad_area_job: Dictionary = fresh.duplicate(true)
	bad_area_job.area = Rect2i(1, 0, 15, 16)
	var bad_params_job: Dictionary = fresh.duplicate(true)
	var bad_params: PackedInt32Array = bad_params_job.params
	bad_params[4] = 16
	bad_params_job.params = bad_params
	var unrequested_job: Dictionary = fresh.duplicate(true)
	unrequested_job.area = Rect2i(32, 0, 3, 16)
	var unrequested_params: PackedInt32Array = unrequested_job.params
	unrequested_params[4] = 32
	unrequested_params[6] = 3
	unrequested_job.params = unrequested_params
	var unrequested_values := PackedInt32Array()
	unrequested_values.resize(3 * 16 * CHANNELS)
	var rejected: Array[Dictionary] = [cache.accept_compute_result({}, values),
		cache.accept_compute_result(fresh, short_values), cache.accept_compute_result(fresh, negative_values),
		cache.accept_compute_result(fresh, large_values), cache.accept_compute_result(bad_area_job, values),
		cache.accept_compute_result(bad_params_job, values), cache.accept_compute_result(unrequested_job, unrequested_values),
		other.accept_compute_result(fresh, values)]
	for result: Dictionary in rejected:
		runner.assert_true(not bool(result.ok) and not str(result.get("reason", "")).is_empty(), "invalid job, result, area or owner is rejected")
	runner.assert_eq(cache.diagnostics(), before, "every rejected result preserves sources, queued tiles and the in-progress draft")
	runner.assert_true(bool(cache.read_base(Vector2i(0, 0)).pending) and bool(cache.read_base(Vector2i(16, 8)).pending), "rejection exposes neither a partial result nor a false clean tile")
	var accepted: Dictionary = cache.accept_compute_result(fresh, values)
	runner.assert_true(bool(accepted.ok) and int(accepted.published_tiles) == 1 and int(accepted.pending_tiles) == 1, "publishing one tile retains the other in-progress tile")
	_compare_area(cache, reference, area, runner, "accepted compute result")
	runner.assert_true(bool(cache.read_base(Vector2i(16, 8)).pending), "the unrelated in-progress tile remains pending")
	runner.assert_true(bool(cache.accept_compute_result(fresh, values).ok), "repeating a complete result for the same revision is idempotently accepted")
	runner.assert_eq(int(cache.diagnostics().pending_tiles), 1, "republication does not drop the other pending tile")
	var clean_before: Dictionary = cache.read_base(Vector2i(3, 4))
	runner.assert_true(not bool(cache.accept_compute_result(fresh, negative_values).ok), "a bad final value is rejected even after an earlier valid publication")
	runner.assert_eq(cache.read_base(Vector2i(3, 4)), clean_before, "a rejected replacement preserves the previously published clean value")
	values[0] = 999999
	_compare_area(cache, reference, area, runner, "caller mutation after accepted result")
	_drain(cache, runner)
	var right: Dictionary = cache.read_base(Vector2i(16, 8))
	var right_reference: Dictionary = reference.sample_base(Vector2i(16, 8))
	for channel: int in CHANNELS:
		runner.assert_eq(int(right.channels[channel]), int(right_reference.channels[channel]), "the unrelated CPU draft completes with the expected field")
	# The bottom-right map boundary may cut two requested tiles short.
	var edge_area := Rect2i(16, 16, 19, 3)
	var edge_job: Dictionary = cache.export_compute_job(edge_area)
	runner.assert_true(bool(edge_job.ok), "a tile-aligned area may end at the map's clipped right/bottom edges")
	var edge_values: PackedInt32Array = _reference_values(reference, edge_area)
	var edge_result: Dictionary = cache.accept_compute_result(edge_job, edge_values)
	runner.assert_true(bool(edge_result.ok) and int(edge_result.published_tiles) == 2, "two clipped boundary tiles publish together")
	_compare_area(cache, reference, edge_area, runner, "clipped compute result")
	var stale: Dictionary = cache.export_compute_job(area)
	var stale_values: PackedInt32Array = _reference_values(reference, area)
	_set_both(cache, reference, 0, Vector2i(3, 4), 4, [101, 20, 30, 40, 50, 60, 70], runner)
	var before_stale: Dictionary = cache.diagnostics().duplicate(true)
	var stale_result: Dictionary = cache.accept_compute_result(stale, stale_values)
	runner.assert_true(not bool(stale_result.ok) and str(stale_result.reason) == "compute_stale", "a source mutation rejects the previous snapshot revision")
	runner.assert_eq(cache.diagnostics(), before_stale, "a stale result leaves the new revision and queued recalculation intact")
	runner.assert_true(bool(cache.read_base(Vector2i(3, 4)).pending), "a stale result cannot mark the changed tile clean")
	_drain(cache, runner)
	_compare_area(cache, reference, area, runner, "CPU result after stale compute rejection")


func _compute_worker_prepare_and_publish(runner: Object) -> void:
	var size := Vector2i(35, 19)
	var area := Rect2i(16, 0, 19, 19)
	var cache := Cache.new()
	var reference := Index.new()
	runner.assert_true(cache.configure(size, 4) and reference.configure(size, 4), "the worker preparation fixture configures")
	_set_both(cache, reference, 0, Vector2i(15, 4), 5, [1200, 0, 0, 300, 100, 900, 0], runner)
	_set_both(cache, reference, 1, Vector2i(33, 17), 3, [0, 2000, 0, 0, 70, 0, 600], runner)
	# This independent block is deliberately pending before the worker job.
	cache.read_base(Vector2i(0, 0))
	var job: Dictionary = cache.export_compute_job(area)
	var values: PackedInt32Array = _reference_values(reference, area)
	var before: Dictionary = cache.diagnostics().duplicate(true)
	var prepared: Dictionary = Cache.prepare_compute_result(job, values)
	runner.assert_true(bool(prepared.ok) and prepared.area == area and int(prepared.tiles.size()) == 4, "worker preparation creates four clipped tiles")
	runner.assert_eq(cache.diagnostics(), before, "worker preparation does not query, publish, dequeue or mutate the live cache")
	var short_input: PackedInt32Array = values.duplicate()
	short_input.resize(short_input.size() - 1)
	var invalid_input: PackedInt32Array = values.duplicate()
	invalid_input[invalid_input.size() - 1] = -1
	var oversized_input: PackedInt32Array = values.duplicate()
	oversized_input[oversized_input.size() - 1] = Rules.MAX_GRADE_MILLI + 1
	runner.assert_true(not bool(Cache.prepare_compute_result(job, short_input).ok), "worker preparation checks the complete input length")
	runner.assert_true(not bool(Cache.prepare_compute_result(job, invalid_input).ok), "worker preparation checks the last result value before returning blocks")
	runner.assert_true(not bool(Cache.prepare_compute_result(job, oversized_input).ok), "worker preparation rejects an over-limit final value")
	runner.assert_eq(cache.diagnostics(), before, "worker-side input failures do not touch the live cache")
	var original_value: int = int(values[0])
	values[0] = 777777
	var first_values: PackedInt32Array = prepared.tiles[0].values
	runner.assert_eq(int(first_values[0]), original_value, "the worker's prepared blocks own their copied result values")
	var missing: Dictionary = prepared.duplicate(true)
	missing.tiles.pop_back()
	var wrong_id: Dictionary = prepared.duplicate(true)
	wrong_id.tiles[0].id = 123456
	var duplicate_id: Dictionary = prepared.duplicate(true)
	duplicate_id.tiles[1].id = duplicate_id.tiles[0].id
	var short: Dictionary = prepared.duplicate(true)
	var short_values: PackedInt32Array = short.tiles[0].values
	short_values.resize(short_values.size() - 1)
	short.tiles[0].values = short_values
	var bad_prepared_area: Dictionary = prepared.duplicate(true)
	bad_prepared_area.area = Rect2i(0, 0, 16, 16)
	var bad_prepared_params: Dictionary = prepared.duplicate(true)
	var prepared_params: PackedInt32Array = bad_prepared_params.params
	prepared_params[0] = 32
	bad_prepared_params.params = prepared_params
	for bad: Dictionary in [missing, wrong_id, duplicate_id, short, bad_prepared_area, bad_prepared_params]:
		var rejected: Dictionary = cache.publish_compute_result(job, bad)
		runner.assert_true(not bool(rejected.ok) and not str(rejected.get("reason", "")).is_empty(), "missing, duplicate, wrong or malformed worker tiles fail preflight")
	runner.assert_eq(cache.diagnostics(), before, "invalid prepared shapes cannot change any requested tile or queue")
	runner.assert_true(bool(cache.read_base(Vector2i(16, 0)).pending) and bool(cache.read_base(Vector2i(34, 18)).pending), "no subset publishes when prepared preflight fails")
	var published: Dictionary = cache.publish_compute_result(job, prepared)
	runner.assert_true(bool(published.ok) and int(published.published_tiles) == 4 and int(published.pending_tiles) == 1, "worker tiles publish together while the separate block remains pending")
	_compare_area(cache, reference, area, runner, "worker-prepared field")
	var detached: PackedInt32Array = prepared.tiles[0].values
	detached[0] = 999999
	prepared.tiles[0].values = detached
	_compare_area(cache, reference, area, runner, "mutating the caller's former prepared buffer cannot change published values")
	runner.assert_true(bool(cache.read_base(Vector2i(0, 0)).pending), "publishing worker output cannot clear the independent pending block")
	var stale_job: Dictionary = cache.export_compute_job(area)
	var stale_values: PackedInt32Array = _reference_values(reference, area)
	var stale_prepared: Dictionary = Cache.prepare_compute_result(stale_job, stale_values)
	runner.assert_true(bool(stale_prepared.ok), "a valid result may be fully prepared before a later source change")
	_set_both(cache, reference, 1, Vector2i(33, 17), 3, [0, 2001, 0, 0, 70, 0, 600], runner)
	var changed: Dictionary = cache.diagnostics().duplicate(true)
	var stale: Dictionary = cache.publish_compute_result(stale_job, stale_prepared)
	runner.assert_true(not bool(stale.ok) and str(stale.reason) == "compute_stale", "source changes after worker preparation reject publication")
	runner.assert_eq(cache.diagnostics(), changed, "a stale prepared result leaves newer sources and pending work untouched")
	runner.assert_true(bool(cache.read_base(Vector2i(33, 17)).pending), "stale work cannot mark a changed block ready")
	_drain(cache, runner)
	_compare_area(cache, reference, area, runner, "CPU field following stale prepared result")


func _empty_compute_snapshot(runner: Object) -> void:
	var cache := Cache.new()
	runner.assert_true(cache.configure(Vector2i(9, 7), 2), "the empty compute field configures")
	var area := Rect2i(0, 0, 9, 7)
	var job: Dictionary = cache.export_compute_job(area)
	runner.assert_true(bool(job.ok) and int(job.params[3]) == 0 and job.kernels.is_empty(), "no sources produce an empty kernel snapshot")
	runner.assert_true(bool(cache.rebuild(1, 1).ok), "a CPU draft can already be in progress when an accelerated result arrives")
	for offset: int in job.radius_offsets:
		runner.assert_eq(offset, -1, "no radius has a retained active offset")
	var values := PackedInt32Array()
	values.resize(area.size.x * area.size.y * CHANNELS)
	var accepted: Dictionary = cache.accept_compute_result(job, values)
	runner.assert_true(bool(accepted.ok) and int(accepted.pending_tiles) == 0, "an empty field publishes zero values without inventing sources")
	runner.assert_eq(int(cache.rebuild(1, 100).completed), 0, "publishing the in-progress tile removes its obsolete CPU draft")
	var point: Dictionary = cache.read_base(Vector2i(8, 6))
	runner.assert_true(not bool(point.pending) and point.channels == PackedInt32Array([0, 0, 0, 0, 0, 0, 0]), "the clipped empty field reads as seven zeros")


func _compact_compute_snapshot(runner: Object) -> void:
	var size := Vector2i(80, 64)
	var area := Rect2i(32, 16, 16, 16)
	var cache := Cache.new()
	var reference := Index.new()
	runner.assert_true(cache.configure(size, 8) and reference.configure(size, 8), "the compact-window fixture configures")
	_set_both(cache, reference, 0, Vector2i(28, 20), 6, [8000, 1000, 0, 0, 400, 0, 0], runner)
	_set_both(cache, reference, 1, Vector2i(28, 20), 4, [0, 3000, 5000, 0, 0, 700, 0], runner)
	_set_both(cache, reference, 2, Vector2i(34, 20), 2, [200, 0, 0, 0, 50, 0, 0], runner)
	_set_both(cache, reference, 3, Vector2i(48, 31), 3, [0, 0, 0, 2000, 0, 0, 2000], runner)
	_set_both(cache, reference, 4, Vector2i(2, 2), 2, [700, 0, 0, 0, 0, 0, 0], runner)
	_set_both(cache, reference, 5, Vector2i(52, 20), 1, [0, 0, 0, 0, 0, 0, 0], runner)
	_set_both(cache, reference, 6, Vector2i(35, 33), 4, [0, 900, 0, 0, 0, 0, 200], runner)
	_set_both(cache, reference, 7, Vector2i(0, 63), 8, [400, 0, 0, 0, 0, 0, 0], runner)
	var full: Dictionary = cache.export_compute_job(area)
	var compact: Dictionary = cache.export_compute_job(area, true)
	runner.assert_true(bool(compact.ok) and compact.area == area and compact.params == full.params, "compact work retains the global publication identity and region")
	runner.assert_eq(compact.compute_params, PackedInt32Array([30, 30, 6, 6, 7, 7, 16, 16]), "the compact region includes the entire clipped global-radius source halo and records its local maximum")
	runner.assert_eq(int(compact.heads.size()), 30 * 30, "compact heads cover only the halo window")
	runner.assert_eq(int(compact.slots.size()), 6 * 11, "only source references inside the halo occupy compact slots")
	var expected: PackedInt32Array = _reference_values(reference, area)
	var compact_values: PackedInt32Array = _sample_compact_job(compact, runner)
	runner.assert_eq(compact_values, expected, "a spatially offset compact snapshot reproduces every F0 channel")
	runner.assert_true(int(expected[((20 - 16) * 16 + 0) * CHANNELS]) > 0, "a source outside the result area still reaches its near edge")
	var prepared: Dictionary = Cache.prepare_compute_result(compact, compact_values)
	runner.assert_true(bool(prepared.ok), "compact values prepare using global publication parameters")
	var published: Dictionary = cache.publish_compute_result(compact, prepared)
	runner.assert_true(bool(published.ok) and int(published.published_tiles) == 1, "the original cache accepts compact output for its global tile")
	_compare_area(cache, reference, area, runner, "compact snapshot result")
	var old: Dictionary = cache.export_compute_job(area, true)
	var old_values: PackedInt32Array = _sample_compact_job(old, runner)
	var old_prepared: Dictionary = Cache.prepare_compute_result(old, old_values)
	_set_both(cache, reference, 0, Vector2i(28, 20), 6, [8001, 1000, 0, 0, 400, 0, 0], runner)
	var stale: Dictionary = cache.publish_compute_result(old, old_prepared)
	runner.assert_true(not bool(stale.ok) and str(stale.reason) == "compute_stale", "compact output cannot publish after a source revision")
	var edge_area := Rect2i(64, 48, 16, 16)
	var edge: Dictionary = cache.export_compute_job(edge_area, true)
	var edge_params: PackedInt32Array = edge.compute_params
	runner.assert_true(bool(edge.ok) and edge_params[0] == 23 and edge_params[1] == 23 and edge_params[4] == 7 and edge_params[5] == 7, "the window clips its right and bottom halo to the actual map")
	runner.assert_eq(int(edge_params[2]), 1, "a locally empty window retains one inactive storage slot")
	runner.assert_eq(int(edge_params[3]), 0, "a locally empty window has no active maximum radius")
	runner.assert_eq(_sample_compact_job(edge, runner), _reference_values(reference, edge_area), "an empty compact window yields the empty field")


func _sample_compact_job(job: Dictionary, runner: Object) -> PackedInt32Array:
	# Independent slow oracle for the exported local coordinate contract. It
	# walks all window chains rather than using the cache's ordered search.
	var params: PackedInt32Array = job.compute_params
	var heads: PackedInt32Array = job.heads
	var slots: PackedInt32Array = job.slots
	var kernels: PackedInt32Array = job.kernels
	var offsets: PackedInt32Array = job.radius_offsets
	var width: int = int(params[0])
	var height: int = int(params[1])
	var capacity: int = int(params[2])
	var visited := PackedInt32Array()
	visited.resize(capacity)
	var chains_ok: bool = true
	var coordinates_ok: bool = true
	for y: int in height:
		for x: int in width:
			var slot: int = heads[y * width + x]
			var traversed: int = 0
			while slot >= 0 and slot < capacity and traversed < capacity:
				coordinates_ok = coordinates_ok and Vector2i(slots[slot], slots[capacity + slot]) == Vector2i(x, y)
				visited[slot] += 1
				slot = slots[capacity * 3 + slot]
				traversed += 1
			chains_ok = chains_ok and slot == -1
	runner.assert_true(coordinates_ok and chains_ok, "all compact heads resolve to the correct coordinates and terminate")
	for slot: int in capacity:
		var active: bool = slots[capacity * 2 + slot] > 0
		runner.assert_eq(visited[slot], 1 if active else 0, "each active local source occurs once, including co-located sources")
	var values := PackedInt32Array()
	values.resize(params[6] * params[7] * CHANNELS)
	for y: int in params[7]:
		for x: int in params[6]:
			var receiver := Vector2i(x + params[4], y + params[5])
			var target: int = (y * params[6] + x) * CHANNELS
			for slot: int in capacity:
				var radius: int = slots[capacity * 2 + slot]
				if radius == 0:
					continue
				var dx: int = absi(receiver.x - slots[slot])
				var dy: int = absi(receiver.y - slots[capacity + slot])
				if dx >= radius or dy >= radius:
					continue
				var weight: int = kernels[offsets[radius] + dy * radius + dx]
				for channel: int in CHANNELS:
					@warning_ignore("integer_division")
					var value: int = (slots[capacity * 4 + slot * CHANNELS + channel] * weight + Rules.SCALE / 2) / Rules.SCALE
					values[target + channel] = maxi(values[target + channel], value)
	return values


func _assert_snapshot_sources(job: Dictionary, runner: Object) -> void:
	# Decode physical source properties through the exported map heads and the
	# declared packed layout, independently of cache-internal source fields.
	var params: PackedInt32Array = job.params
	var heads: PackedInt32Array = job.heads
	var slots: PackedInt32Array = job.slots
	var capacity: int = int(params[2])
	var examples: Array[Dictionary] = [
		{"cell": Vector2i(3, 4), "radius": 4, "channels": [100, 20, 30, 40, 50, 60, 70]},
		{"cell": Vector2i(6, 5), "radius": 5, "channels": [200, 500, 300, 400, 500, 600, 700]},
		{"cell": Vector2i(34, 18), "radius": 3, "channels": [800, 20, 0, 50, 0, 40, 0]},
		{"cell": Vector2i(8, 8), "radius": 2, "channels": [0, 0, Rules.MAX_GRADE_MILLI, 0, 0, 0, 0]},
	]
	for example: Dictionary in examples:
		var cell: Vector2i = example.cell
		var slot: int = heads[cell.y * int(params[0]) + cell.x]
		runner.assert_true(slot >= 0 and slot < capacity, "each source remains reachable through its projected cell head")
		if slot < 0 or slot >= capacity:
			continue
		runner.assert_eq(Vector2i(slots[slot], slots[capacity + slot]), cell, "the head resolves to the original projected position")
		runner.assert_eq(slots[capacity * 2 + slot], example.radius, "the head resolves to the original source radius")
		runner.assert_eq(slots[capacity * 3 + slot], -1, "an isolated projected cell terminates its source chain")
		for channel: int in CHANNELS:
			runner.assert_eq(slots[capacity * 4 + slot * CHANNELS + channel], example.channels[channel], "the source retains each declared channel strength")


func _reference_values(reference: RefCounted, area: Rect2i) -> PackedInt32Array:
	var values := PackedInt32Array()
	values.resize(area.size.x * area.size.y * CHANNELS)
	for y: int in area.size.y:
		for x: int in area.size.x:
			var direct: Dictionary = reference.sample_base(area.position + Vector2i(x, y))
			for channel: int in CHANNELS:
				values[(y * area.size.x + x) * CHANNELS + channel] = int(direct.channels[channel])
	return values


func _compare_area(cache: RefCounted, reference: RefCounted, area: Rect2i, runner: Object, label: String) -> void:
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			var cached: Dictionary = cache.read_base(cell)
			var direct: Dictionary = reference.sample_base(cell)
			runner.assert_true(bool(cached.ok) and not bool(cached.pending), label + ": each cell is published")
			if not bool(cached.ok) or bool(cached.pending):
				continue
			for channel: int in CHANNELS:
				runner.assert_eq(int(cached.channels[channel]), int(direct.channels[channel]), label + ": exact channel at " + str(cell))


func _set_both(cache: RefCounted, reference: RefCounted, slot: int, cell: Vector2i, radius: int, channels: Array, runner: Object) -> void:
	var projected: Dictionary = cache.set_source(slot, cell, radius, channels)
	var direct: Dictionary = reference.set_source({"id": "s_%d" % slot, "cell": cell, "radius": radius, "channels": channels})
	runner.assert_true(bool(projected.ok) and bool(direct.ok), "both projections accept source %d" % slot)


func _request_all(cache: RefCounted, size: Vector2i, runner: Object) -> void:
	for y: int in range(0, size.y, Cache.TILE_SIZE):
		for x: int in range(0, size.x, Cache.TILE_SIZE):
			var result: Dictionary = cache.read_base(Vector2i(x, y))
			runner.assert_true(bool(result.ok) and bool(result.pending), "every unbuilt tile reports pending")


func _drain(cache: RefCounted, runner: Object) -> void:
	var iterations: int = 0
	while int(cache.diagnostics().pending_tiles) > 0 and iterations < 2000:
		var result: Dictionary = cache.rebuild(3, 5000)
		if not bool(result.ok):
			runner.assert_true(false, "the bounded rebuild failed: " + str(result))
			return
		runner.assert_true(int(result.completed) <= 3 and int(result.work) <= 5000, "each rebuild honors both work budgets")
		iterations += 1
	runner.assert_eq(int(cache.diagnostics().pending_tiles), 0, "the finite pending queue drains without dropping work")


func _compare_all(cache: RefCounted, reference: RefCounted, size: Vector2i, runner: Object, label: String) -> void:
	for y: int in size.y:
		for x: int in size.x:
			var cell := Vector2i(x, y)
			var cached: Dictionary = cache.read_base(cell)
			var expected: Dictionary = reference.sample_base(cell)
			runner.assert_true(bool(cached.ok) and not bool(cached.pending) and bool(expected.ok), label + ": each value is ready")
			if not bool(cached.ok) or bool(cached.pending) or not bool(expected.ok):
				continue
			for channel: int in CHANNELS:
				runner.assert_eq(int(cached.channels[channel]), int(expected.channels[channel]), label + ": exact channel at " + str(cell))
