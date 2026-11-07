class_name SimParticipationIndex
extends RefCounted
## Disposable, owner-local execution index. It owns only IDs, pending reasons,
## and deadlines; the owning domain remains responsible for all world state.
##
## Membership, active participation, dirty work, and deadlines are independent.
## In particular, an inactive member may be dirtied or have a future deadline
## so that its owner can wake it. Removing membership clears all of its work.
## Queries are deterministic and do not consume work. The owner cancels a due
## item or acknowledges dirty work only after its own processing succeeds.
## No method advances time, invokes callbacks, or serializes domain data.

const MAX_REVISION: int = 9223372036854775807
const UNLIMITED: int = 2147483647

var _groups: Dictionary = {}
# Never reset by clear(): a snapshot from before clear/removal must not be able
# to acknowledge new work after the same subject has been registered again.
var _dirty_revision: int = 0


class Group:
	var members: Dictionary = {}
	var active: Dictionary = {}
	var dirty: Dictionary = {}
	var due: Dictionary = {}
	var heap: Array[String] = []
	var positions: Dictionary = {}
	var sorted_members: Array[String] = []
	var sorted_active: Array[String] = []
	var sorted_dirty: Array[String] = []
	var members_valid: bool = false
	var active_valid: bool = false
	var dirty_valid: bool = false
	var last_due_examined: int = 0


## Adds or removes a member. Valid duplicate additions/removals are no-ops.
func set_member(kind: StringName, id: String, present: bool = true) -> bool:
	if not _valid_key(kind, id):
		return false
	var group: Group = _groups.get(kind)
	if present:
		if group == null:
			group = Group.new()
			_groups[kind] = group
		if not group.members.has(id):
			group.members[id] = true
			group.members_valid = false
		return true
	if group == null or not group.members.has(id):
		return true
	group.members.erase(id)
	group.members_valid = false
	if group.active.erase(id):
		group.active_valid = false
	if group.dirty.erase(id):
		group.dirty_valid = false
	_remove_due(group, id)
	if group.members.is_empty():
		_groups.erase(kind)
	return true


func has_member(kind: StringName, id: String) -> bool:
	var group: Group = _groups.get(kind)
	return group != null and group.members.has(id)


## Activity is separate from membership and can only be set for a member.
func set_active(kind: StringName, id: String, active: bool) -> bool:
	var group: Group = _groups.get(kind)
	if group == null or not group.members.has(id):
		return false
	if active:
		if not group.active.has(id):
			group.active[id] = true
			group.active_valid = false
	elif group.active.erase(id):
		group.active_valid = false
	return true


## Returned arrays are independent, sorted snapshots; callers may mutate them.
func active_ids(kind: StringName) -> Array[String]:
	var group: Group = _groups.get(kind)
	if group == null:
		return []
	if not group.active_valid:
		group.sorted_active = _sorted_keys(group.active)
		group.active_valid = true
	return group.sorted_active.duplicate()


func member_ids(kind: StringName) -> Array[String]:
	var group: Group = _groups.get(kind)
	if group == null:
		return []
	if not group.members_valid:
		group.sorted_members = _sorted_keys(group.members)
		group.members_valid = true
	return group.sorted_members.duplicate()


## Union reasons for this member; every mark gets a new revision, even if the
## reason already existed. Zero means invalid input or revision exhaustion.
func mark_dirty(kind: StringName, id: String, reason: StringName) -> int:
	var group: Group = _groups.get(kind)
	if group == null or not group.members.has(id) or reason == &"" or _dirty_revision >= MAX_REVISION:
		return 0
	_dirty_revision += 1
	var row: Dictionary = group.dirty.get(id, {})
	if row.is_empty():
		row = {"revision": _dirty_revision, "reasons": {}}
		group.dirty[id] = row
		group.dirty_valid = false
	else:
		row.revision = _dirty_revision
	var reasons: Dictionary = row.reasons
	reasons[reason] = true
	return _dirty_revision


## Stable id order and per-id reason order. A limited snapshot leaves the rest
## pending. Repeated queries do not consume or acknowledge any work.
func pending_dirty(kind: StringName, limit: int = UNLIMITED) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var group: Group = _groups.get(kind)
	if group == null or limit <= 0:
		return result
	if not group.dirty_valid:
		group.sorted_dirty = _sorted_keys(group.dirty)
		group.dirty_valid = true
	for index: int in mini(limit, group.sorted_dirty.size()):
		var id: String = group.sorted_dirty[index]
		var row: Dictionary = group.dirty[id]
		var reason_names: Array[String] = []
		for reason: StringName in row.reasons:
			reason_names.append(str(reason))
		reason_names.sort()
		var reasons: Array[StringName] = []
		for reason: String in reason_names:
			reasons.append(StringName(reason))
		result.append({"id": id, "revision": int(row.revision), "reasons": reasons})
	return result


## A stale snapshot cannot clear a later mark, including after remove/re-add.
func ack_dirty(kind: StringName, id: String, revision: int) -> bool:
	var group: Group = _groups.get(kind)
	if group == null or not group.dirty.has(id) or int(group.dirty[id].revision) != revision:
		return false
	group.dirty.erase(id)
	group.dirty_valid = false
	return true


## At most one deadline per member and kind. Update-in-place prevents a stream
## of reschedules from growing a heap of stale entries. No active flag needed.
func set_due(kind: StringName, id: String, at_ms: int) -> bool:
	var group: Group = _groups.get(kind)
	if group == null or not group.members.has(id) or at_ms < 0:
		return false
	if not group.due.has(id):
		group.due[id] = at_ms
		group.positions[id] = group.heap.size()
		group.heap.append(id)
		_sift_up(group, group.heap.size() - 1)
		return true
	var previous: int = int(group.due[id])
	if previous == at_ms:
		return true
	group.due[id] = at_ms
	var index: int = int(group.positions[id])
	if at_ms < previous:
		_sift_up(group, index)
	else:
		_sift_down(group, index)
	return true


## An already-cancelled deadline is a valid no-op for an existing member.
func cancel_due(kind: StringName, id: String) -> bool:
	var group: Group = _groups.get(kind)
	if group == null or not group.members.has(id):
		return false
	_remove_due(group, id)
	return true


func next_due_ms(kind: StringName, fallback: int) -> int:
	var group: Group = _groups.get(kind)
	if group == null or group.heap.is_empty():
		return fallback
	return int(group.due[group.heap[0]])


## Return at most limit due IDs in (time, id) order without consuming them or
## copying/scanning the whole heap. A small frontier heap visits at most one
## root plus two children per result, independent of unrelated members.
func due_ids(kind: StringName, through_ms: int, limit: int = UNLIMITED) -> Array[String]:
	var result: Array[String] = []
	var group: Group = _groups.get(kind)
	if group == null:
		return result
	group.last_due_examined = 0
	if limit <= 0 or through_ms < 0 or group.heap.is_empty():
		return result
	group.last_due_examined = 1
	if int(group.due[group.heap[0]]) > through_ms:
		return result
	var frontier: Array[int] = [0]
	while not frontier.is_empty() and result.size() < limit:
		var index: int = _frontier_pop(group, frontier)
		result.append(group.heap[index])
		var left: int = index * 2 + 1
		if left < group.heap.size():
			group.last_due_examined += 1
			if int(group.due[group.heap[left]]) <= through_ms:
				_frontier_push(group, frontier, left)
		var right: int = left + 1
		if right < group.heap.size():
			group.last_due_examined += 1
			if int(group.due[group.heap[right]]) <= through_ms:
				_frontier_push(group, frontier, right)
	return result


## Clear derived membership and work on world replacement; keep dirty revision.
func clear() -> void:
	_groups.clear()


func diagnostics(kind: StringName) -> Dictionary:
	var group: Group = _groups.get(kind)
	if group == null:
		return {"members": 0, "active": 0, "dirty": 0, "due": 0, "last_due_examined": 0}
	return {"members": group.members.size(), "active": group.active.size(), "dirty": group.dirty.size(),
		"due": group.heap.size(), "last_due_examined": group.last_due_examined}


static func _valid_key(kind: StringName, id: String) -> bool:
	return kind != &"" and not id.is_empty()


static func _sorted_keys(values: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for id: String in values:
		ids.append(id)
	ids.sort()
	return ids


static func _less(group: Group, first: String, second: String) -> bool:
	var first_ms: int = int(group.due[first])
	var second_ms: int = int(group.due[second])
	return first_ms < second_ms or (first_ms == second_ms and first < second)


static func _swap(group: Group, first: int, second: int) -> void:
	var first_id: String = group.heap[first]
	var second_id: String = group.heap[second]
	group.heap[first] = second_id
	group.heap[second] = first_id
	group.positions[first_id] = second
	group.positions[second_id] = first


static func _sift_up(group: Group, start: int) -> void:
	var index: int = start
	while index > 0:
		@warning_ignore("integer_division")
		var parent: int = (index - 1) / 2
		if not _less(group, group.heap[index], group.heap[parent]):
			break
		_swap(group, index, parent)
		index = parent


static func _sift_down(group: Group, start: int) -> void:
	var index: int = start
	while true:
		var left: int = index * 2 + 1
		if left >= group.heap.size():
			return
		var best: int = left
		var right: int = left + 1
		if right < group.heap.size() and _less(group, group.heap[right], group.heap[left]):
			best = right
		if not _less(group, group.heap[best], group.heap[index]):
			return
		_swap(group, index, best)
		index = best


static func _remove_due(group: Group, id: String) -> void:
	if not group.due.has(id):
		return
	var index: int = int(group.positions[id])
	var last: int = group.heap.size() - 1
	if index != last:
		_swap(group, index, last)
	group.heap.pop_back()
	group.positions.erase(id)
	group.due.erase(id)
	if index < group.heap.size():
		var moved: String = group.heap[index]
		_sift_up(group, index)
		_sift_down(group, int(group.positions[moved]))


static func _frontier_push(group: Group, frontier: Array[int], candidate: int) -> void:
	frontier.append(candidate)
	var index: int = frontier.size() - 1
	while index > 0:
		@warning_ignore("integer_division")
		var parent: int = (index - 1) / 2
		if not _less(group, group.heap[frontier[index]], group.heap[frontier[parent]]):
			break
		var old: int = frontier[parent]
		frontier[parent] = frontier[index]
		frontier[index] = old
		index = parent


static func _frontier_pop(group: Group, frontier: Array[int]) -> int:
	var result: int = frontier[0]
	var last: int = frontier.pop_back()
	if frontier.is_empty():
		return result
	frontier[0] = last
	var index: int = 0
	while true:
		var left: int = index * 2 + 1
		if left >= frontier.size():
			break
		var best: int = left
		var right: int = left + 1
		if right < frontier.size() and _less(group, group.heap[frontier[right]], group.heap[frontier[left]]):
			best = right
		if not _less(group, group.heap[frontier[best]], group.heap[frontier[index]]):
			break
		var old: int = frontier[index]
		frontier[index] = frontier[best]
		frontier[best] = old
		index = best
	return result
