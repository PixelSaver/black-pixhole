extends Control
class_name DraggableComponent

## Makes a control draggable with horizontal drag support and click-to-edit
## Parent can connect to drag_changed signal to update values

signal drag_changed(delta: float)
signal click_detected()

## Pixels before drag starts
@export var drag_threshold := 5.0 # Increased threshold slightly
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
var _par : Control

# --- FIX 1: Set Z-Index and Mouse Filter in _ready ---
func custom_init():
	_par = get_parent()
	_par.mouse_filter = Control.MOUSE_FILTER_PASS
	# before it reaches the SpinBox underneath.
	mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Setting anchors preset to full rect is fine
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	
	_par.mouse_entered.connect(_on_enter)
	_par.mouse_exited.connect(_on_exit)

func _on_enter():
	grab_click_focus()
	grab_focus()
	print("Grab click focus")
	pass
func _on_exit():
	release_focus()
	pass

func _gui_input(event):
	# Mouse press / release
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pressed = true
				_dragging = false
				_accumulated_delta = 0.0
				# FIX 2: Accept the event immediately on press
				# This prevents the event from propagating to the SpinBox
				#accept_event()
			else:
				if not _dragging and allow_click_through:
					# It was a click, not a drag
					click_detected.emit()
				_pressed = false
				_dragging = false
				# FIX 3: Accept the event on release too, ensuring it stops here
				#accept_event()


	# Mouse motion -> handle dragging after threshold
	if event is InputEventMouseMotion and _pressed:
		var dx: float = event.relative.x
		
		# FIX 4: Only process motion if within the drag threshold or already dragging
		if not _dragging:
			_accumulated_delta += abs(dx)
			_dragging = true
			# Once we start dragging, we should accept the event
			accept_event()
			return # Skip calculation on the threshold frame
		
		if _dragging or true:
			# Calculate speed with modifiers
			var speed := base_drag_speed
			if Input.is_key_pressed(Key.KEY_SHIFT):
				speed *= shift_multiplier
			elif Input.is_key_pressed(Key.KEY_ALT):
				speed *= alt_multiplier

			# Emit the delta for parent to handle
			drag_changed.emit(dx * speed)
			
			# FIX 5: Accept the event to prevent motion from propagating
			# This is crucial during an active drag.
			accept_event()
