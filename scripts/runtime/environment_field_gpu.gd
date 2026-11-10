class_name EnvironmentFieldGPU
extends RefCounted
## Disposable accelerator for a frozen cache projection. Call on one worker
## thread. No scene, original object, world clock or persistent state is owned.
## The caller must publish through the cache's revision/owner validation.

const SHADER_PATH: String = "res://assets/shaders/environment_field_compute.glsl"
const MAX_BUFFER_BYTES: int = 256 * 1024 * 1024
const MAX_TOTAL_BYTES: int = 512 * 1024 * 1024
const MAX_INPUT_BYTES: int = 64 * 1024 * 1024
const CHANNELS: int = 7

var _rd: RenderingDevice
var _shader := RID()
var _pipeline := RID()


func initialize() -> Dictionary:
	if _rd != null:
		return {"ok": true, "device": _rd.get_device_name()}
	# A dummy/headless or Compatibility renderer has no RenderingDevice.
	if RenderingServer.get_rendering_device() == null:
		return _failure("rendering_device_unavailable")
	var started: int = Time.get_ticks_usec()
	_rd = RenderingServer.create_local_rendering_device()
	if _rd == null:
		return _failure("local_device_unavailable")
	var shader_file: RDShaderFile = load(SHADER_PATH) as RDShaderFile
	if shader_file == null:
		close()
		return _failure("shader_source_missing")
	# Use the imported resource so packed Windows exports need no raw GLSL
	# file or runtime source compiler. Godot's importer owns SPIR-V compilation.
	var spirv: RDShaderSPIRV = shader_file.get_spirv()
	var error: String = spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not error.is_empty():
		close()
		return {"ok": false, "reason": "shader_compile", "detail": error}
	_shader = _rd.shader_create_from_spirv(spirv)
	if not _shader.is_valid():
		close()
		return _failure("shader_create")
	_pipeline = _rd.compute_pipeline_create(_shader)
	if not _pipeline.is_valid():
		close()
		return _failure("pipeline_create")
	return {"ok": true, "device": _rd.get_device_name(), "setup_ms": _ms(started)}


func compute(job: Dictionary, rows_per_dispatch: int = 16) -> Dictionary:
	if _rd == null:
		return _failure("not_initialized")
	if rows_per_dispatch < 1 or rows_per_dispatch > 64:
		return _failure("dispatch_budget")
	for key: String in ["params", "heads", "slots", "kernels", "radius_offsets"]:
		if not job.get(key) is PackedInt32Array:
			return _failure("job_arrays")
	var params: PackedInt32Array = job.get("compute_params", job.params)
	if params.size() != 8 or params[0] < 1 or params[1] < 1 or params[0] > 4096 or params[1] > 4096 or params[2] < 1 or params[2] > 4194304 or params[3] < 0 or params[3] > 256:
		return _failure("job_params")
	if params[4] < 0 or params[5] < 0 or params[6] < 1 or params[7] < 1 or params[6] > params[0] or params[7] > params[1] or params[4] > params[0] - params[6] or params[5] > params[1] - params[7]:
		return _failure("job_area")
	if job.heads.size() != params[0] * params[1] or job.slots.size() != params[2] * 11 or job.radius_offsets.size() != 257:
		return _failure("job_layout")
	var geometry: Variant = job.get("geometry", PackedInt32Array([0]))
	if not geometry is PackedInt32Array or geometry.is_empty():
		return _failure("job_geometry")
	if geometry[0] != 0:
		if geometry.size() < 6 or geometry[0] != 1 or geometry[3] < 1 or geometry[3] > 4096 or geometry[4] < 1 or geometry[4] > 4096 or geometry[5] < 1 or geometry[5] > 256 or geometry.size() != 6 + geometry[3] * geometry[4]:
			return _failure("job_geometry")
	var neighbor_width: int = mini(params[0], maxi(1, params[3] * 2 - 1))
	var neighbor_height: int = mini(params[1], maxi(1, params[3] * 2 - 1))
	# Limit a dispatch's receiver/source-cell visits before driver submission.
	# Dense co-located chains can still cost more; this is a declared budget,
	# not a hard GPU-time guarantee. Unusual radii fall back to the CPU path.
	var density: Variant = job.get("max_cell_sources", 1)
	if not density is int or density < 1 or density > params[2]:
		return _failure("job_density")
	var row_work: int = params[6] * neighbor_width * neighbor_height * int(density)
	if row_work > 2_000_000:
		return _failure("device_radius_budget")
	@warning_ignore("integer_division")
	rows_per_dispatch = mini(rows_per_dispatch, maxi(1, 2_000_000 / row_work))
	var input_size: int = (params.size() + job.heads.size() + job.slots.size() + job.kernels.size() + job.radius_offsets.size() + geometry.size()) * 4
	if input_size > MAX_INPUT_BYTES:
		return _failure("device_working_budget")
	var started: int = Time.get_ticks_usec()
	var bytes: Array[PackedByteArray] = [params.to_byte_array(), job.heads.to_byte_array(), job.slots.to_byte_array(), job.kernels.to_byte_array(), job.radius_offsets.to_byte_array()]
	# Storage buffers cannot be empty; no-source jobs never read the dummy word.
	if bytes[3].is_empty():
		bytes[3] = PackedInt32Array([0]).to_byte_array()
	var output_bytes: int = params[6] * mini(params[7], rows_per_dispatch) * CHANNELS * 4
	# Godot exposes storage buffer counts but no per-buffer byte-size limit.
	# Apply our cap and treat allocation rejection as a backend failure.
	var limit: int = MAX_BUFFER_BYTES
	var total_bytes: int = output_bytes
	for data: PackedByteArray in bytes:
		if data.size() > limit:
			return _failure("device_buffer_limit")
		total_bytes += data.size()
	if output_bytes > limit or total_bytes > MAX_TOTAL_BYTES:
		return _failure("device_memory_budget")
	var buffers: Array[RID] = []
	var uniforms: Array[RDUniform] = []
	for binding: int in 7:
		var buffer: RID
		if binding < 5:
			buffer = _rd.storage_buffer_create(bytes[binding].size(), bytes[binding])
		elif binding == 5:
			buffer = _rd.storage_buffer_create(output_bytes)
		else:
			var geometry_bytes: PackedByteArray = geometry.to_byte_array()
			if geometry_bytes.size() > limit or total_bytes > MAX_TOTAL_BYTES - geometry_bytes.size():
				_free_buffers(buffers)
				return _failure("device_memory_budget")
			total_bytes += geometry_bytes.size()
			buffer = _rd.storage_buffer_create(geometry_bytes.size(), geometry_bytes)
		if not buffer.is_valid():
			_free_buffers(buffers)
			return _failure("buffer_create")
		buffers.append(buffer)
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding = binding
		uniform.add_id(buffer)
		uniforms.append(uniform)
	var uniform_set: RID = _rd.uniform_set_create(uniforms, _shader, 0)
	if not uniform_set.is_valid():
		_free_buffers(buffers)
		return _failure("uniform_create")
	var upload_ms: float = _ms(started)
	var values := PackedInt32Array()
	var dispatch_samples: Array[float] = []
	var readback_ms: float = 0.0
	for offset_y: int in range(0, params[7], rows_per_dispatch):
		var batch: PackedInt32Array = params.duplicate()
		batch[5] += offset_y
		batch[7] = mini(rows_per_dispatch, params[7] - offset_y)
		var batch_bytes: PackedByteArray = batch.to_byte_array()
		_rd.buffer_update(buffers[0], 0, batch_bytes.size(), batch_bytes)
		var dispatch_started: int = Time.get_ticks_usec()
		var list: int = _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _pipeline)
		_rd.compute_list_bind_uniform_set(list, uniform_set, 0)
		@warning_ignore("integer_division")
		var groups_x: int = (batch[6] + 7) / 8
		@warning_ignore("integer_division")
		var groups_y: int = (batch[7] + 7) / 8
		_rd.compute_list_dispatch(list, groups_x, groups_y, 1)
		_rd.compute_list_end()
		_rd.submit()
		# Runs on the owned worker: never block the game's main thread here.
		# Keep each dispatch bounded, rather than one driver-timeout-sized job.
		_rd.sync()
		dispatch_samples.append(_ms(dispatch_started))
		var read_started: int = Time.get_ticks_usec()
		var count: int = batch[6] * batch[7] * CHANNELS
		var raw: PackedByteArray = _rd.buffer_get_data(buffers[5], 0, count * 4)
		if raw.size() != count * 4:
			_rd.free_rid(uniform_set)
			_free_buffers(buffers)
			return _failure("readback_length")
		# Native append avoids one interpreted assignment per channel value.
		values.append_array(raw.to_int32_array())
		readback_ms += _ms(read_started)
	_rd.free_rid(uniform_set)
	_free_buffers(buffers)
	return {"ok": true, "values": values, "total_ms": _ms(started), "upload_ms": upload_ms,
		"dispatch_ms": dispatch_samples, "readback_ms": readback_ms, "buffer_bytes": total_bytes,
		"device": _rd.get_device_name()}


func close() -> void:
	if _rd == null:
		return
	if _pipeline.is_valid():
		_rd.free_rid(_pipeline)
	if _shader.is_valid():
		_rd.free_rid(_shader)
	_pipeline = RID()
	_shader = RID()
	_rd.free()
	_rd = null


func _free_buffers(buffers: Array[RID]) -> void:
	for buffer: RID in buffers:
		_rd.free_rid(buffer)


static func _ms(started: int) -> float:
	return float(Time.get_ticks_usec() - started) / 1000.0


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
