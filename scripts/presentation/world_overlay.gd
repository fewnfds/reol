extends Node2D
## Native CanvasItem drawing inside the world viewport, independent of input UI.
var paint: Callable
func _draw() -> void:
	if paint.is_valid(): paint.call(self)
