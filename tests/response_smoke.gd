extends SceneTree
## Diagnostic timestamps must follow the real mailbox without entering World.

const Runner = preload("res://scripts/sim/kernel/runner.gd")
const ResponseProbe = preload("res://scripts/presentation/response_probe.gd")
var _errors: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	if not ok:
		_errors += 1
		push_error(message)


func _run() -> void:
	var runner := Runner.new()
	runner.control(true, 1)
	check(runner.start(4, 0, 1) == OK, "Response runner did not start")
	var deadline: int = Time.get_ticks_usec() + 2000000
	var frame: RefCounted
	while frame == null and Time.get_ticks_usec() < deadline:
		await process_frame
		frame = runner.poll().frame
	if frame == null:
		check(false, "Response runner did not publish")
		runner.close()
		quit(1)
		return
	var request_usec: int = Time.get_ticks_usec()
	var command: Dictionary = {"kind": "interrupt", "actor": 1, "_trace": {"request_usec": request_usec}}
	var traced: int = runner.send(command)
	var plain: int = runner.send({"kind": "interrupt", "actor": 1})
	var receipts: Array[Dictionary] = []
	while receipts.size() < 2 and Time.get_ticks_usec() < deadline:
		await process_frame
		receipts.append_array(runner.poll().receipts)
	check(receipts.size() == 2, "Response receipts lost or duplicated")
	for receipt: Dictionary in receipts:
		if receipt.seq == traced:
			check(receipt.ok and receipt.has("trace"), "Traced command missing timestamps")
			if receipt.has("trace"):
				var trace: Dictionary = receipt.trace
				check(trace.request_usec == request_usec and trace.request_usec <= trace.enqueued_usec and trace.enqueued_usec <= trace.received_usec and trace.received_usec <= trace.applied_usec and trace.applied_usec <= trace.published_usec,
					"Response timestamps out of order")
				check(trace.frame_sequence > 0, "Receipt not bound to a published frame")
		elif receipt.seq == plain:
			check(receipt.ok and not receipt.has("trace"), "Untraced command acquired diagnostic payload")
	check(not command._trace.has("enqueued_usec"), "Runner mutated caller's diagnostic envelope")
	check(runner.poll().receipts.is_empty(), "Response receipt replayed")
	runner.close()
	print("RESPONSE_SMOKE errors=", _errors)
	quit(0 if _errors == 0 else 1)
