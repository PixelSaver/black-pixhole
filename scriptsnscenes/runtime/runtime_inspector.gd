extends PanelContainer
## Runtime Inspector - Automatically generates UI for @export variables
## Usage: Add this to your scene, then call inspect(your_node)
class_name RuntimeInspector

@export var show_private_properties := false
@export var compact_mode := false

@export var inspector_min_width: int = 280
@export var inspector_min_height: int = 400
@export var value_column_max_width: int = 140

@export var property_label_min_x: int = 150
@export var spinbox_min_x: int = 100
@export var vector_axis_label_width: int = 12
@export var vector_axis_spin_min_x: int = 80

@export var color_picker_width: int = 60
@export var color_picker_height: int = 24

# Draggable speed modifier
@export var drag_speed_multiplier: float = 20.0

# SpinBox range limits (use large finite values instead of INF)
const SPINBOX_MIN = -1e10
const SPINBOX_MAX = 1e10

var _current_target: Object = null
var _property_controls: Dictionary = {}
var _scroll_container: ScrollContainer
var _property_container: VBoxContainer

func _ready():
	Global.runtime_inspector = self
	_setup_ui()

func _setup_ui():
	custom_minimum_size = Vector2(inspector_min_width, inspector_min_height)
	
	var margin = MarginContainer.new()
	add_child(margin)
	
	var vbox = VBoxContainer.new()
	margin.add_child(vbox)
	
	var title = RichTextLabel.new()
	title.text = "Inspector"
	vbox.add_child(title)
	
	var separator = HSeparator.new()
	vbox.add_child(separator)
	
	_scroll_container = ScrollContainer.new()
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll_container)
	
	_property_container = VBoxContainer.new()
	_property_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_container.add_child(_property_container)

func inspect(target: Object):
	_current_target = target
	_clear_properties()
	
	if target == null:
		return
	
	var properties = target.get_property_list()
	var property_names = []
	
	for prop in properties:
		if prop.usage & PROPERTY_USAGE_EDITOR == 0:
			continue
		
		if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
			
		if not show_private_properties and prop.name.begins_with("_"):
			continue
			
		if prop.name == "target":
			continue
		
		property_names.append(prop.name)
		_create_property_control(prop)
	print("Inspecting this property list: %s" % str(property_names))

func _clear_properties():
	for child in _property_container.get_children():
		child.queue_free()
	_property_controls.clear()

func _create_property_control(prop: Dictionary):
	var prop_name = prop.name
	var prop_type = prop.type
	var current_value = _current_target.get(prop_name)
	
	var container = HBoxContainer.new()
	_property_container.add_child(container)
	
	var label = Label.new()
	label.text = prop_name.capitalize()
	label.custom_minimum_size.x = property_label_min_x
	label.add_theme_font_size_override("font_size", 15)
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.clip_text = true
	container.add_child(label)
	
	var control = _create_control_for_type(prop_type, current_value, prop)
	if control:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.add_child(control)
		_property_controls[prop_name] = control

func _create_control_for_type(type: int, value, prop: Dictionary):
	match type:
		TYPE_BOOL:
			return _create_bool_control(value, prop.name)
		TYPE_INT:
			return _create_int_control(value, prop)
		TYPE_FLOAT:
			return _create_float_control(value, prop)
		TYPE_STRING:
			return _create_string_control(value, prop.name)
		TYPE_VECTOR2:
			return _create_vector2_control(value, prop.name)
		TYPE_VECTOR3:
			return _create_vector3_control(value, prop.name)
		TYPE_COLOR:
			return _create_color_control(value, prop.name)
		TYPE_NODE_PATH:
			return _create_string_control(str(value), prop.name)
		TYPE_OBJECT:
			return _create_object_control(value, prop.name)
		_:
			return _create_generic_control(value, prop.name)

func _create_bool_control(value: bool, prop_name: String) -> CheckButton:
	var check = CheckButton.new()
	check.button_pressed = value
	check.toggled.connect(func(pressed): _on_property_changed(prop_name, pressed))
	return check

func _create_int_control(value: int, prop: Dictionary) -> Control:
	if prop.has("hint") and prop.hint == PROPERTY_HINT_RANGE:
		var hint_string = prop.hint_string
		var parts = hint_string.split(",")
		if parts.size() >= 2:
			var min_val = parts[0].to_float()
			var max_val = parts[1].to_float()
			var step = 1.0
			if parts.size() >= 3:
				step = parts[2].to_float()
			
			var hbox = HBoxContainer.new()
			
			var value_label = Label.new()
			value_label.text = str(value)
			value_label.custom_minimum_size.x = spinbox_min_x
			
			var slider = HSlider.new()
			slider.min_value = min_val
			slider.max_value = max_val
			slider.step = step
			slider.value = value
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.value_changed.connect(func(v): 
				_on_property_changed(prop.name, int(v))
				value_label.text = str(int(v))
			)
			hbox.add_child(slider)
			hbox.add_child(value_label)
			
			return hbox
	
	var spin = SpinBox.new()
	spin.min_value = SPINBOX_MIN
	spin.max_value = SPINBOX_MAX
	spin.value = value
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.value_changed.connect(func(v): _on_property_changed(prop.name, int(v)))
	_add_draggable_to_spinbox(spin, prop.name)
	return spin

func _create_float_control(value: float, prop: Dictionary) -> Control:
	if prop.has("hint") and prop.hint == PROPERTY_HINT_RANGE:
		var hint_string = prop.hint_string
		var parts = hint_string.split(",")
		if parts.size() >= 2:
			var min_val = parts[0].to_float()
			var max_val = parts[1].to_float()
			var step = 0.01
			if parts.size() >= 3:
				step = parts[2].to_float()
			
			var hbox = HBoxContainer.new()
			
			var value_label = Label.new()
			value_label.text = "%.2f" % value
			value_label.custom_minimum_size.x = spinbox_min_x
			
			var slider = HSlider.new()
			slider.min_value = min_val
			slider.max_value = max_val
			slider.step = step
			slider.value = value
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.value_changed.connect(func(v): 
				_on_property_changed(prop.name, v)
				value_label.text = "%.2f" % v
			)
			hbox.add_child(slider)
			hbox.add_child(value_label)
			
			return hbox
	
	var spin = SpinBox.new()
	spin.min_value = SPINBOX_MIN
	spin.max_value = SPINBOX_MAX
	spin.step = 0.01
	spin.value = value
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.mouse_filter = Control.MOUSE_FILTER_PASS
	spin.value_changed.connect(func(v): _on_property_changed(prop.name, v))
	_add_draggable_to_spinbox(spin, prop.name)
	return spin

func _create_string_control(value: String, prop_name: String) -> LineEdit:
	var line_edit = LineEdit.new()
	line_edit.text = value
	line_edit.text_submitted.connect(func(text): _on_property_changed(prop_name, text))
	line_edit.focus_exited.connect(func(): _on_property_changed(prop_name, line_edit.text))
	return line_edit

func _create_vector2_control(value: Vector2, prop_name: String) -> HBoxContainer:
	var hbox = HBoxContainer.new()
	
	var x_label = Label.new()
	x_label.text = "X"
	x_label.custom_minimum_size.x = spinbox_min_x / 2
	hbox.add_child(x_label)
	
	var x_spin = SpinBox.new()
	x_spin.min_value = SPINBOX_MIN
	x_spin.max_value = SPINBOX_MAX
	x_spin.step = 0.01
	x_spin.value = value.x
	x_spin.allow_greater = true
	x_spin.allow_lesser = true
	x_spin.custom_minimum_size.x = spinbox_min_x / 2
	x_spin.value_changed.connect(func(v): 
		var vec = _current_target.get(prop_name)
		_on_property_changed(prop_name, Vector2(v, vec.y))
	)
	_add_draggable_to_spinbox(x_spin, prop_name, func(delta):
		x_spin.value += delta
	)
	hbox.add_child(x_spin)
	
	var y_label = Label.new()
	y_label.text = "Y"
	y_label.custom_minimum_size.x = spinbox_min_x / 2
	hbox.add_child(y_label)
	
	var y_spin = SpinBox.new()
	y_spin.min_value = SPINBOX_MIN
	y_spin.max_value = SPINBOX_MAX
	y_spin.step = 0.01
	y_spin.value = value.y
	y_spin.allow_greater = true
	y_spin.allow_lesser = true
	y_spin.custom_minimum_size.x = spinbox_min_x / 2
	y_spin.value_changed.connect(func(v): 
		var vec = _current_target.get(prop_name)
		_on_property_changed(prop_name, Vector2(vec.x, v))
	)
	_add_draggable_to_spinbox(y_spin, prop_name, func(delta):
		y_spin.value += delta
	)
	hbox.add_child(y_spin)
	
	return hbox

func _create_vector3_control(value: Vector3, prop_name: String) -> VBoxContainer:
	var vbox = VBoxContainer.new()
	
	for i in range(3):
		var hbox = HBoxContainer.new()
		var axis_name = ["X", "Y", "Z"][i]
		var axis_value = [value.x, value.y, value.z][i]
		
		var label = Label.new()
		label.text = axis_name
		label.custom_minimum_size.x = vector_axis_label_width
		hbox.add_child(label)
		
		var spin = SpinBox.new()
		spin.min_value = SPINBOX_MIN
		spin.max_value = SPINBOX_MAX
		spin.step = 0.01
		spin.allow_greater = true
		spin.allow_lesser = true
		spin.custom_minimum_size.x = vector_axis_spin_min_x
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.value = axis_value
		
		if i == 0:
			spin.value_changed.connect(func(v):
				var vec = _current_target.get(prop_name)
				_on_property_changed(prop_name, Vector3(v, vec.y, vec.z))
			)
		elif i == 1:
			spin.value_changed.connect(func(v):
				var vec = _current_target.get(prop_name)
				_on_property_changed(prop_name, Vector3(vec.x, v, vec.z))
			)
		else:
			spin.value_changed.connect(func(v):
				var vec = _current_target.get(prop_name)
				_on_property_changed(prop_name, Vector3(vec.x, vec.y, v))
			)
		
		_add_draggable_to_spinbox(spin, prop_name, func(delta):
			spin.value += delta
		)
		
		hbox.add_child(spin)
		vbox.add_child(hbox)
	
	return vbox

func _create_color_control(value: Color, prop_name: String) -> ColorPickerButton:
	var color_picker = ColorPickerButton.new()
	color_picker.color = value
	color_picker.edit_alpha = true
	color_picker.custom_minimum_size = Vector2(color_picker_width, color_picker_height)
	color_picker.color_changed.connect(func(color): _on_property_changed(prop_name, color))
	
	# Reposition the popup when it opens
	color_picker.get_popup().about_to_popup.connect(func():
		var popup := color_picker.get_popup()

		var global_pos = Vector2(0,100)
		popup.size = color_picker.size * .9
		popup.set_position(global_pos)
	)
	
	return color_picker

func _create_object_control(value, prop_name: String) -> RichTextLabel:
	var label = RichTextLabel.new()
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.scroll_active = false
	label.text = str(value) if value else "<null>"
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	return label

func _create_generic_control(value, prop_name: String) -> Label:
	var label = Label.new()
	label.text = str(value)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	return label

func _on_property_changed(prop_name: String, new_value):
	if _current_target:
		_current_target.set(prop_name, new_value)

func _add_draggable_to_spinbox(spin: SpinBox, prop_name: String, custom_drag_handler: Callable = Callable()) -> void:
	var draggable = DraggableComponent.new()
	draggable.name = "DragOverlay"
	draggable.base_drag_speed = spin.step * drag_speed_multiplier
	spin.add_child(draggable)
	
	if custom_drag_handler.is_valid():
		draggable.drag_changed.connect(custom_drag_handler)
	else:
		draggable.drag_changed.connect(func(delta):
			spin.value += delta  # No clamping needed - min/max are already INF
		)
	
	draggable.click_detected.connect(func():
		spin.grab_focus()
	)
