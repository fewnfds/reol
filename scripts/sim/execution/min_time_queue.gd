extends RefCounted
## Indexed minimum queue for transient schedules. Equal times use identity order.

var _keys: Array[String] = []
var _slots: Dictionary[String, int] = {}
var _times: Dictionary[String, int] = {}


func first() -> String:
	return "" if _keys.is_empty() else _keys[0]


func first_through(time: int) -> String:
	var key: String = first()
	return key if not key.is_empty() and _times[key] <= time else ""

func has(key: String) -> bool:
	return _slots.has(key)


func set_time(key: String, time: int) -> void:
	var slot: int = _slots.get(key, -1)
	if slot < 0:
		slot = _keys.size()
		_keys.append(key)
		_slots[key] = slot
		_times[key] = time
		_sift_up(slot)
		return
	var previous: int = _times[key]
	_times[key] = time
	if time < previous: _sift_up(slot)
	elif time > previous: _sift_down(slot)


func erase(key: String) -> void:
	var slot: int = _slots.get(key, -1)
	if slot < 0: return
	var last: String = _keys.pop_back()
	_slots.erase(key)
	_times.erase(key)
	if last == key: return
	_keys[slot] = last
	_slots[last] = slot
	if slot > 0 and _before(last, _keys[(slot - 1) >> 1]):
		_sift_up(slot)
	else:
		_sift_down(slot)


func clear() -> void:
	_keys.clear()
	_slots.clear()
	_times.clear()


func _before(a: String, b: String) -> bool:
	var left: int = _times[a]
	var right: int = _times[b]
	return left < right or (left == right and a < b)


func _sift_up(slot: int) -> void:
	var key: String = _keys[slot]
	while slot > 0:
		var parent: int = (slot - 1) >> 1
		if not _before(key, _keys[parent]): break
		_keys[slot] = _keys[parent]
		_slots[_keys[slot]] = slot
		slot = parent
	_keys[slot] = key
	_slots[key] = slot


func _sift_down(slot: int) -> void:
	var key: String = _keys[slot]
	while slot * 2 + 1 < _keys.size():
		var child: int = slot * 2 + 1
		if child + 1 < _keys.size() and _before(_keys[child + 1], _keys[child]): child += 1
		if not _before(_keys[child], key): break
		_keys[slot] = _keys[child]
		_slots[_keys[slot]] = slot
		slot = child
	_keys[slot] = key
	_slots[key] = slot
