extends Control
class_name DraggableComponent
## Makes a control draggable with horizontal drag support and click-to-edit
## Parent can connect to drag_changed signal to update values

signal drag_changed(delta: float)
signal click_detected()

## Pixels before drag starts
@export var drag_threshold := 0.
## Base speed multiplier for drag
@export var base_drag_speed := 1.0
## Speed when holding Shift
@export var shift_multiplier := 5.0
## Speed when holding Alt
@export var alt_multiplier := 0.2
## Whether to allow click-through for editing
@export var allow_click_through := true

var _pressed := false
var _dragging := false
var _accumulated_delta := 0.0

func _input(event):
	# Global click detection to defocus parent when clicking outside
	if event is InputEventMouseButton and event.pressed:
		if get_parent() and get_parent().has_focus():
			# Check if click is outside the parent control
			var parent = get_parent()
			if parent is Control:
				var local_pos = parent.get_local_mouse_position()
				var rect = Rect2(Vector2.ZERO, parent.size)
				if not rect.has_point(local_pos):
					parent.release_focus()

func _ready():
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_DRAG

	# Fill parent completely
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	size = get_parent().size
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Ensure overlay is on top
	z_index = 100


func _gui_input(event):
	# Mouse press / release
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pressed = true
				_dragging = false
				_accumulated_delta = 0.0
			else:
				if not _dragging and allow_click_through:
					# It was a click, not a drag
					click_detected.emit()
				_pressed = false
				_dragging = false

	# Mouse motion -> handle dragging after threshold
	if event is InputEventMouseMotion and _pressed:
		var dx: float = event.relative.x
		_accumulated_delta += abs(dx)

		if not _dragging and _accumulated_delta >= drag_threshold:
			_dragging = true
			mouse_default_cursor_shape = Control.CURSOR_DRAG

		if _dragging:
			# Calculate speed with modifiers
			var speed := base_drag_speed
			if Input.is_key_pressed(Key.KEY_SHIFT):
				speed *= shift_multiplier
			elif Input.is_key_pressed(Key.KEY_ALT):
				speed *= alt_multiplier


			# Emit the delta for parent to handle
			drag_changed.emit(dx * speed)
