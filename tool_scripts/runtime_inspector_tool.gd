@tool
extends EditorScript

## Configuration - Edit these variables before running
var target_object_path: String = "3DRK4_Att2"  # Path to the object you want to inspect
var parent_node_path: String = "UI"  # Path to parent node
var anchor_left: float = 0.0
var anchor_top: float = 0.0
var anchor_right: float = 0.3
var anchor_bottom: float = 1.0
var panel_min_width: int = 280
var panel_min_height: int = 400
var property_label_min_x: int = 130
var show_private_properties: bool = false

func _run():
	var editor_interface = get_editor_interface()
	var edited_scene_root = editor_interface.get_edited_scene_root()
	
	if not edited_scene_root:
		print("No scene is currently open in the editor")
		return
	
	# Find target object to inspect
	var target = edited_scene_root.get_node_or_null(target_object_path)
	if not target:
		print("Target object not found: ", target_object_path)
		return
	
	print("Inspecting: ", target.name)
	
	# Find or create parent node
	var parent = edited_scene_root.get_node_or_null(parent_node_path)
	if not parent:
		print("Parent node not found: ", parent_node_path)
		print("Creating CanvasLayer as parent...")
		parent = CanvasLayer.new()
		parent.name = "CanvasLayer"
		edited_scene_root.add_child(parent)
		parent.owner = edited_scene_root
	
	# Create the inspector panel with properties
	var inspector = _create_inspector_panel(target)
	#inspector.name = "RuntimeInspector_" + target.name
	inspector.name = "RuntimeInspector"
	
	# Remove old inspector if it exists
	var old_inspector = parent.get_node_or_null(NodePath(inspector.name))
	if old_inspector:
		old_inspector.free()
	
	parent.add_child(inspector)
	inspector.owner = edited_scene_root
	
	# Set ownership for all children recursively
	_set_owner_recursive(inspector, edited_scene_root)
	
	print("Inspector created successfully with properties for: ", target.name)

func _set_owner_recursive(node: Node, owner: Node):
	for child in node.get_children():
		child.owner = owner
		_set_owner_recursive(child, owner)

func _create_inspector_panel(target: Object) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(panel_min_width, panel_min_height)
	
	# Set anchors
	panel.set_anchors_preset(Control.PRESET_FULL_RECT, true)
	panel.set_anchor(SIDE_LEFT, anchor_left, false)
	panel.set_anchor(SIDE_TOP, anchor_top, false)
	panel.set_anchor(SIDE_RIGHT, anchor_right, false)
	panel.set_anchor(SIDE_BOTTOM, anchor_bottom, false)
	
	# Add margin container
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	margin.add_child(vbox)
	
	# Title
	var title = Label.new()
	title.text = "Inspector: " + target.name
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)
	
	var separator = HSeparator.new()
	vbox.add_child(separator)
	
	# Scroll container for properties
	var scroll_container = ScrollContainer.new()
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll_container)
	
	var property_container = VBoxContainer.new()
	property_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(property_container)
	
	# Generate property controls
	_generate_properties(target, property_container)
	
	return panel

func _generate_properties(target: Object, container: VBoxContainer):
	var properties = target.get_property_list()
	
	for prop in properties:
		# Only show exported properties
		if prop.usage & PROPERTY_USAGE_EDITOR == 0:
			continue
			
		# Skip private properties unless enabled
		if not show_private_properties and prop.name.begins_with("_"):
			continue
		
		_create_property_control(target, prop, container)

func _create_property_control(target: Object, prop: Dictionary, container: VBoxContainer):
	var prop_name = prop.name
	var prop_type = prop.type
	var current_value = target.get(prop_name)
	
	var row = HBoxContainer.new()
	container.add_child(row)
	
	# Property label
	var label = Label.new()
	label.text = prop_name.capitalize()
	label.custom_minimum_size.x = property_label_min_x
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.clip_text = true
	row.add_child(label)
	
	# Create appropriate control based on type
	var control = _create_control_for_type(prop_type, current_value, prop)
	if control:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(control)

func _create_control_for_type(type: int, value, prop: Dictionary):
	match type:
		TYPE_BOOL:
			return _create_bool_control(value)
		TYPE_INT:
			return _create_int_control(value, prop)
		TYPE_FLOAT:
			return _create_float_control(value, prop)
		TYPE_STRING:
			return _create_string_control(value)
		TYPE_VECTOR2:
			return _create_vector2_control(value)
		TYPE_VECTOR3:
			return _create_vector3_control(value)
		TYPE_COLOR:
			return _create_color_control(value)
		TYPE_NODE_PATH:
			return _create_string_control(str(value))
		TYPE_OBJECT:
			return _create_object_control(value)
		_:
			return _create_generic_control(value)

func _create_bool_control(value: bool) -> CheckButton:
	var check = CheckButton.new()
	check.button_pressed = value
	return check

func _create_int_control(value: int, prop: Dictionary) -> Control:
	# Check for range hint
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
			
			var slider = HSlider.new()
			slider.min_value = min_val
			slider.max_value = max_val
			slider.step = step
			slider.value = value
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hbox.add_child(slider)
			
			var value_label = Label.new()
			value_label.text = str(value)
			value_label.custom_minimum_size.x = 40
			hbox.add_child(value_label)
			
			return hbox
	
	# Default spinbox
	var spin = SpinBox.new()
	spin.value = value
	spin.allow_greater = true
	spin.allow_lesser = true
	return spin

func _create_float_control(value: float, prop: Dictionary) -> Control:
	# Check for range hint
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
			
			var slider = HSlider.new()
			slider.min_value = min_val
			slider.max_value = max_val
			slider.step = step
			slider.value = value
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hbox.add_child(slider)
			
			var value_label = Label.new()
			value_label.text = "%.2f" % value
			value_label.custom_minimum_size.x = 50
			hbox.add_child(value_label)
			
			return hbox
	
	# Default spinbox
	var spin = SpinBox.new()
	spin.step = 0.01
	spin.value = value
	spin.allow_greater = true
	spin.allow_lesser = true
	return spin

func _create_string_control(value: String) -> LineEdit:
	var line_edit = LineEdit.new()
	line_edit.text = value
	return line_edit

func _create_vector2_control(value: Vector2) -> HBoxContainer:
	var hbox = HBoxContainer.new()
	
	var x_label = Label.new()
	x_label.text = "X"
	x_label.custom_minimum_size.x = 12
	hbox.add_child(x_label)
	
	var x_spin = SpinBox.new()
	x_spin.step = 0.01
	x_spin.value = value.x
	x_spin.allow_greater = true
	x_spin.allow_lesser = true
	x_spin.custom_minimum_size.x = 60
	hbox.add_child(x_spin)
	
	var y_label = Label.new()
	y_label.text = "Y"
	y_label.custom_minimum_size.x = 12
	hbox.add_child(y_label)
	
	var y_spin = SpinBox.new()
	y_spin.step = 0.01
	y_spin.value = value.y
	y_spin.allow_greater = true
	y_spin.allow_lesser = true
	y_spin.custom_minimum_size.x = 60
	hbox.add_child(y_spin)
	
	return hbox

func _create_vector3_control(value: Vector3) -> VBoxContainer:
	var vbox = VBoxContainer.new()
	
	# Create compact rows for each axis
	var axes = [
		{"name": "X", "value": value.x},
		{"name": "Y", "value": value.y},
		{"name": "Z", "value": value.z}
	]
	
	for axis in axes:
		var hbox = HBoxContainer.new()
		
		var label = Label.new()
		label.text = axis.name
		label.custom_minimum_size.x = 12
		hbox.add_child(label)
		
		var spin = SpinBox.new()
		spin.step = 0.01
		spin.allow_greater = true
		spin.allow_lesser = true
		spin.custom_minimum_size.x = 80
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.value = axis.value
		hbox.add_child(spin)
		
		vbox.add_child(hbox)
	
	return vbox

func _create_color_control(value: Color) -> ColorPickerButton:
	var color_picker = ColorPickerButton.new()
	color_picker.color = value
	color_picker.edit_alpha = true
	color_picker.custom_minimum_size = Vector2(60, 24)
	return color_picker

func _create_object_control(value) -> Label:
	var label = Label.new()
	if value:
		label.text = str(value)
	else:
		label.text = "<null>"
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	return label

func _create_generic_control(value) -> Label:
	var label = Label.new()
	label.text = str(value)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	return label
