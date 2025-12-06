extends PanelContainer
## Runtime Inspector - Automatically generates UI for @export variables
## Usage: Add this to your scene, then call inspect(your_node)
class_name RuntimeInspector

signal inspection_finished
signal property_changed(property_name:String, new_value:Variant)

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
	title.fit_content = true
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
	var avoid_props = [
		"process",
		"thread_group",
		"physics_interpolation",
		"auto_translate",
		"editor_description",
		"shader_setup.gd",
	]
	
	# Current group/category tracking for UI organization
	var current_group_name = ""
	var current_category_name = ""

	for prop in properties:
		
		
		# These properties are not actual variables; they are organizational hints
		if prop.usage & PROPERTY_USAGE_CATEGORY or prop.usage & PROPERTY_USAGE_GROUP or prop.usage & PROPERTY_USAGE_SUBGROUP:
			#if (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE): continue
			if prop.name.to_snake_case() in avoid_props:
				print("Skipped: %s" % prop.name)
				continue
			print("Group: %s" % prop.name)
			# Godot uses PROPERTY_USAGE_CATEGORY for groups, subgroups, and categories
			
			
			if prop.usage & PROPERTY_USAGE_CATEGORY:
				# Example: @export_category("Rendering")
				var new_category = prop.name.replace(":", "").replace("/", "") # Clean up name
				if new_category != current_category_name:
					current_category_name = new_category
					if new_category != target.get_class():
						_create_category_header(new_category)
					current_group_name = "" # Reset group when entering a new category
				continue
				
			elif prop.usage & PROPERTY_USAGE_GROUP or prop.usage & PROPERTY_USAGE_SUBGROUP:
				# Example: @export_group("Physics Properties")
				# Example: @export_subgroup("Movement")
				var new_group = prop.name.replace(":", "").replace("/", "") # Clean up name
				if new_group != current_group_name:
					_create_group_header(new_group, prop.usage & PROPERTY_USAGE_SUBGROUP)
					current_group_name = new_group
				continue
		if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if prop.usage & PROPERTY_USAGE_EDITOR == 0:
			continue

		if not show_private_properties and prop.name.begins_with("_"):
			continue

		if prop.name == "target":
			continue

		property_names.append(prop.name)
		_create_property_control(prop)
	print("Inspecting this property list: %s" % str(property_names))

func _process(_delta: float) -> void:
	refresh()

func refresh():
	if not _current_target:
		return
	
	# Iterate over all property controls currently in the UI
	for prop_name in _property_controls:
		var control = _property_controls[prop_name]
		var current_value = _current_target.get(prop_name)
		
		# Call a new helper function to set the control's value
		_update_control_value(control, current_value)

# New helper function to abstract the control updating logic
func _update_control_value(control: Control, value):
	# This is where you map the Godot type to the control property
	# Note: This is an incomplete example; you'd need cases for all control types
	match control.get_class():
		"SpinBox":
			# For SpinBox (Int/Float)
			if control.value != value:
				control.value = value
		"CheckButton":
			# For CheckButton (Bool)
			if control.button_pressed != value:
				control.button_pressed = value
		"LineEdit":
			# For LineEdit (String/NodePath)
			if control.text != value:
				control.text = value
		"ColorPickerButton":
			# For ColorPickerButton (Color)
			if control.color != value:
				control.color = value
		"VBoxContainer": # Assuming vector controls are inside a VBoxContainer
			if value is Vector2:
				# Assuming index 0 is X and index 1 is Y's HBoxContainer
				var x_hbox = control.get_child(0) as HBoxContainer
				var y_hbox = control.get_child(1) as HBoxContainer
				
				# Assuming the SpinBox is the second child of the HBoxContainer
				var x_spin = x_hbox.get_child(1) as SpinBox 
				var y_spin = y_hbox.get_child(1) as SpinBox
				
				if x_spin.value != value.x: x_spin.value = value.x
				if y_spin.value != value.y: y_spin.value = value.y
			elif value is Vector2i:
				# Assuming index 0 is X and index 1 is Y's HBoxContainer
				var x_hbox = control.get_child(0) as HBoxContainer
				var y_hbox = control.get_child(1) as HBoxContainer
				
				# Assuming the SpinBox is the second child of the HBoxContainer
				var x_spin = x_hbox.get_child(1) as SpinBox
				var y_spin = y_hbox.get_child(1) as SpinBox
				
				if x_spin.value != value.x: x_spin.value = value.x
				if y_spin.value != value.y: y_spin.value = value.y
			elif value is Vector3:
				# Assuming index 0 is X and index 1 is Y's HBoxContainer
				var x_hbox = control.get_child(0) as HBoxContainer
				var y_hbox = control.get_child(1) as HBoxContainer
				var z_hbox = control.get_child(2) as HBoxContainer
				
				# Assuming the SpinBox is the second child of the HBoxContainer
				var x_spin = x_hbox.get_child(1) as SpinBox
				var y_spin = y_hbox.get_child(1) as SpinBox
				var z_spin = z_hbox.get_child(1) as SpinBox
				
				if x_spin.value != value.x: x_spin.value = value.x
				if y_spin.value != value.y: y_spin.value = value.y
				if z_spin.value != value.z: y_spin.value = value.z
				
			#TODO Add vector3i
		_:
			# For other controls (Labels for Objects/Generics)
			pass

func _create_category_header(_name: String):
	# Create a prominent header for Categories (e.g., bold, larger text, separator)
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.text = "[b][font_size=18]%s[/font_size][/b]" % _name.capitalize()
	label.custom_minimum_size.y = 30
	label.fit_content = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_property_container.add_child(label)
	_property_container.add_child(HSeparator.new())

func _create_group_header(_name: String, is_subgroup: bool = false):
	# Create a less prominent header for Groups/Subgroups (e.g., standard text)
	var prefix = "  " if is_subgroup else ""
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.text = "%s[b]%s[/b]" % [prefix, _name.capitalize()]
	label.custom_minimum_size.y = 20
	label.fit_content = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	print("Added header")
	_property_container.add_child(label)

func _clear_properties():
	if not _property_container: return
	for child in _property_container.get_children():
		child.queue_free()
	_property_controls.clear()

func _create_property_control(prop: Dictionary):
	var prop_name = prop.name
	var prop_type = prop.type
	var current_value = _current_target.get(prop_name)

	var container = HBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_FILL
	_property_container.add_child(container)
	container.tooltip_text = prop_name.capitalize()

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
		control.custom_minimum_size.x = 0
		_debug_log_control_sizes(control, prop_name)
		_property_controls[prop_name] = control

func _debug_log_control_sizes(control: Control, label: String):
	return
	await get_tree().process_frame  # wait for layout
	var min_size = control.get_combined_minimum_size()
	var actual_size = control.size
	print("[%s] min_size=%s actual_size=%s type=%s" %
		[label, min_size, actual_size, control])

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
		TYPE_VECTOR2I:
			return _create_vector2i_control(value, prop.name)
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
			slider.custom_minimum_size.x = 0
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
			value_label.size_flags_horizontal = Control.SIZE_SHRINK_END


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

func _create_vector2_control(value: Vector2, prop_name: String) -> VBoxContainer:
	var vbox = VBoxContainer.new()

	# X axis
	var hbox_x = HBoxContainer.new()
	var x_label = Label.new()
	x_label.text = "X"
	x_label.custom_minimum_size.x = vector_axis_label_width
	x_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hbox_x.add_child(x_label)

	var x_spin = SpinBox.new()
	x_spin.min_value = SPINBOX_MIN
	x_spin.max_value = SPINBOX_MAX
	x_spin.step = 0.01
	x_spin.value = value.x
	x_spin.allow_greater = true
	x_spin.allow_lesser = true
	x_spin.custom_minimum_size.x = vector_axis_spin_min_x
	x_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	x_spin.value_changed.connect(func(v):
		var vec = _current_target.get(prop_name)
		_on_property_changed(prop_name, Vector2(v, vec.y))
	)
	_add_draggable_to_spinbox(x_spin, prop_name, func(delta):
		x_spin.value += delta
	)
	hbox_x.add_child(x_spin)

	vbox.add_child(hbox_x)

	# Y axis
	var hbox_y = HBoxContainer.new()
	var y_label = Label.new()
	y_label.text = "Y"
	y_label.custom_minimum_size.x = vector_axis_label_width
	y_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hbox_y.add_child(y_label)

	var y_spin = SpinBox.new()
	y_spin.min_value = SPINBOX_MIN
	y_spin.max_value = SPINBOX_MAX
	y_spin.step = 0.01
	y_spin.value = value.y
	y_spin.allow_greater = true
	y_spin.allow_lesser = true
	y_spin.custom_minimum_size.x = vector_axis_spin_min_x
	y_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	y_spin.value_changed.connect(func(v):
		var vec = _current_target.get(prop_name)
		_on_property_changed(prop_name, Vector2(vec.x, v))
	)
	_add_draggable_to_spinbox(y_spin, prop_name, func(delta):
		y_spin.value += delta
	)
	hbox_y.add_child(y_spin)

	vbox.add_child(hbox_y)

	return vbox

func _create_vector2i_control(value: Vector2i, prop_name: String) -> VBoxContainer:
	var vbox = VBoxContainer.new()

	# X axis
	var hbox_x = HBoxContainer.new()
	var x_label = Label.new()
	x_label.text = "X"
	x_label.custom_minimum_size.x = vector_axis_label_width
	x_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hbox_x.add_child(x_label)

	var x_spin = SpinBox.new()
	x_spin.min_value = SPINBOX_MIN
	x_spin.max_value = SPINBOX_MAX
	x_spin.step = 1
	x_spin.value = value.x
	x_spin.allow_greater = true
	x_spin.allow_lesser = true
	x_spin.custom_minimum_size.x = vector_axis_spin_min_x
	x_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	x_spin.value_changed.connect(func(v):
		var vec = _current_target.get(prop_name)
		_on_property_changed(prop_name, Vector2i(int(v), vec.y))
	)

	_add_draggable_to_spinbox(x_spin, prop_name, func(delta):
		x_spin.value += delta
	)

	hbox_x.add_child(x_spin)
	vbox.add_child(hbox_x)

	# Y axis
	var hbox_y = HBoxContainer.new()
	var y_label = Label.new()
	y_label.text = "Y"
	y_label.custom_minimum_size.x = vector_axis_label_width
	y_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hbox_y.add_child(y_label)

	var y_spin = SpinBox.new()
	y_spin.min_value = SPINBOX_MIN
	y_spin.max_value = SPINBOX_MAX
	y_spin.step = 1
	y_spin.value = value.y
	y_spin.allow_greater = true
	y_spin.allow_lesser = true
	y_spin.custom_minimum_size.x = vector_axis_spin_min_x
	y_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	y_spin.value_changed.connect(func(v):
		var vec = _current_target.get(prop_name)
		_on_property_changed(prop_name, Vector2i(vec.x, int(v)))
	)

	_add_draggable_to_spinbox(y_spin, prop_name, func(delta):
		y_spin.value += delta
	)

	hbox_y.add_child(y_spin)
	vbox.add_child(hbox_y)

	return vbox

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

## Sets a property value on the current target object.
## @param prop_name The name of the property to set.
## @param new_value The new value to assign to the property.
func set_target_prop(prop_name: String, new_value) -> bool:
	if _current_target:
		# Check if the property exists before attempting to set
		if _current_target.has_method("set") and _current_target.has_method("get"):
			# Use the engine's built-in set function for safety and efficiency
			if _current_target.get(prop_name) == new_value: return false
			_current_target.set(prop_name, new_value)
			refresh()
			var control = _property_controls[prop_name]
			print("GOING")
			_update_control_value(control, new_value)
			return true
		else:
			# Fallback or error log if the object doesn't support 'set' (unlikely for Object descendants)
			push_warning("Current target does not support property setting.")
	else:
		push_warning("Cannot set property: No target object inspected.")
	return false


## Gets a property value from the current target object.
## @param prop_name The name of the property to get.
## @return The value of the property, or null if no target is inspected or property doesn't exist.
func get_target_prop(prop_name: String):
	if _current_target:
		# Check if the property exists before attempting to get
		if _current_target.has_method("get"):
			# Use the engine's built-in get function
			return _current_target.get(prop_name)
		else:
			push_warning("Current target does not support property getting.")
			return null
	else:
		# This will be useful if other parts of the system want to read a property
		return null

func _on_property_changed(prop_name: String, new_value):
	if _current_target:
		_current_target.set(prop_name, new_value)
		property_changed.emit(prop_name, new_value)

func _add_draggable_to_spinbox(spin: SpinBox, prop_name: String, custom_drag_handler: Callable = Callable()) -> void:
	var draggable = DraggableComponent.new()
	draggable.name = "DragOverlay"
	draggable.base_drag_speed = spin.step * drag_speed_multiplier
	spin.add_child(draggable)
	draggable.custom_init()

	if custom_drag_handler.is_valid():
		draggable.drag_changed.connect(custom_drag_handler)
	else:
		draggable.drag_changed.connect(func(delta):
			spin.value += delta  # No clamping needed - min/max are already INF
		)

	draggable.click_detected.connect(func():
		#draggable.grab_click_focus()
		pass
	)
