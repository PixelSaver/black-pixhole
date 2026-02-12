extends SpinBox


func _on_draggable_component_drag_changed(delta: float) -> void:
	self.value += delta
