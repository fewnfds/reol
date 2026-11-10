class_name SimBatchExecution
extends RefCounted
## One disposable calculation batch. Workers own scratch results, never live
## domain/SceneTree state. The caller alone validates and publishes results.

class WorkGroup extends RefCounted:
	var chunks: Array[RefCounted] = []

	func run(index: int) -> void:
		chunks[index].run()

var cancelled: bool = false
var parallel: bool = false
var submitted_usec: int = 0
var completed_usec: int = 0
var dispatch_usec: int = 0
var _task: int = -1
var _group: WorkGroup


func start(chunks: Array[RefCounted], workers: int) -> void:
	assert(_group == null)
	_group = WorkGroup.new()
	_group.chunks = chunks.duplicate()
	submitted_usec = Time.get_ticks_usec()
	parallel = workers > 0 and chunks.size() > 1
	if parallel:
		# The callable retains only scratch data, not this handle or its owner.
		_task = WorkerThreadPool.add_group_task(_group.run, chunks.size(), mini(workers, chunks.size()), false, "Reol simulation batch")
		dispatch_usec = Time.get_ticks_usec() - submitted_usec
	else:
		for index: int in chunks.size():
			_group.run(index)
		completed_usec = Time.get_ticks_usec()


func finish(blocking: bool = false) -> bool:
	if _task >= 0:
		if not blocking and not WorkerThreadPool.is_group_task_completed(_task):
			return false
		# Completed tasks must be collected even when their results were cancelled.
		WorkerThreadPool.wait_for_group_task_completion(_task)
		_task = -1
		completed_usec = Time.get_ticks_usec()
	return true


func cancel() -> void:
	# Cancellation revokes publication; workers can finish their bounded chunks.
	# Owners keep retired handles until finish() can collect them without waiting.
	cancelled = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Only teardown may wait. The group has no reference back to this handle.
		if _task >= 0:
			WorkerThreadPool.wait_for_group_task_completion(_task)
