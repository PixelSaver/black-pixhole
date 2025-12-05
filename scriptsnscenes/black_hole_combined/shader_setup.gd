extends Node
class_name ShaderSetup

# --- Core RIDs ---
signal shader_process_frame(delta:float, frame_time:float)
var is_dispatching := false

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var output_tex: RID
var uniform_set: RID
var sampler: RID # Permanent Sampler RID
var params_buffer: RID # Permanent Uniform Buffer RID
var noise_tex: RID # Permanent Noise Texture RID
var skybox_rd_tex: RID # Permanent Skybox Texture RID

# --- Export Variables (Updated) ---
# Rendering
const ASPECT = 16.0 / 9.0
@export_group("Rendering")
@export var resolution := Vector2i(1280, 720) :
	set(new_res):
		if not _setup_ready: resolution = new_res
		if resolution.y == new_res.y:
			resolution.x = new_res.x
			resolution.y = int(round(resolution.x / ASPECT))
		elif resolution.x == new_res.x:
			resolution.y = new_res.y
			resolution.x = int(round(resolution.y / ASPECT))
		res_changed = true
@export_range(10, 10000) var max_steps := 500
@export_range(0.0001, 10.0) var step_size := 0.1
@export_range(50.0, 50000.0) var escape_radius := 100.0
@export var skybox_texture: Texture2D = preload("res://scriptsnscenes/black_hole_combined/skybox_75.png")
@export_range(0.01, 5.0) var skybox_brightness := 1.5
var res_changed := false
const MIN_TEXTURE_SIZE := Vector2i(32, 18)
@onready var _resolution := resolution
var _paused := false

# Black Hole
@export_group("Black Hole")
@export var black_hole_position := Vector3(0, 0, 0)
@export_range(0.5, 10.0) var schwarzschild_radius := 2.0
@export var black_hole_color := Color(0.1, 0.1, 0.1, 1.0)

# Camera
@export_group("Camera")
@export_range(30.0, 120.0) var camera_fov := 60.0
@export var use_scene_camera := true
@export var camera_position := Vector3(0, 8, 20)
@export var camera_target := Vector3(0, 0, 0)

# Disc
@export_group("Accretion Disc")
@export var enable_disc := true
@export_range(1.0, 20.0) var disc_inner_radius := 4.0
@export_range(5.0, 50.0) var disc_outer_radius := 12.0
@export_range(0.1, 50.0) var disc_thickness := 0.3
@export_range(0.1, 100.0) var disc_emission_strength := 5.0
@export var disc_inner_color := Color(1.0, 0.3, 0.1, 1.0)
@export var disc_outer_color := Color(1.0, 0.8, 0.3, 1.0)
@export var disc_noise_texture: NoiseTexture2D

# Grid
@export_group("Spacetime Grid")
@export var show_grid := true
@export_range(0.5, 10.0) var grid_spacing := 2.0
@export_range(0.01, 10.) var grid_line_thickness := 0.08
@export_range(-50, 50) var grid_offset : float = 0
@export_range(0.0, 10.0) var grid_alpha := 0.5
@export_range(10.0, 100.0) var grid_range := 30.0
@export var grid_color := Color(0.3, 0.8, 1.0, 1.0)

# 🌌 Galaxy/Nebula (REPLACING Stars)
@export_group("Volumetric Galaxy")
@export var show_galaxy := true
@export_range(0.1, 100.) var galaxy_scale := 1.
@export var galaxy_rotation := Vector3.ZERO
@export_range(0.00001, 10.0) var galaxy_intensity_scale := 1.0
@export var galaxy_pos := Vector3(10, 0, 0)

var last_time = 0.
var frame_start_time = 0.
var update_noise_texture := false
var _setup_ready := false

# ----------------------------------------------------
# --- LIFECYCLE FUNCTIONS ---
# ----------------------------------------------------

func _ready():
	rd = RenderingServer.create_local_rendering_device()
	if not rd:
		push_error("Failed to create RenderingDevice")
		return

	_setup_shader()
	_setup_output_texture()
	sampler = _create_sampler() # Create permanent Sampler RID
	_setup_uniforms() # Create permanent Uniform Set, Buffers, and Textures

	last_time = Time.get_unix_time_from_system()
	_update_shader() # First dispatch
	update_noise_texture = true
	_setup_ready = true

func _process(_delta):
	if res_changed:
		res_changed = false
		# Defer by one frame
		call_deferred("_apply_resolution_change")
func _apply_resolution_change():
	var view : Vector2i = get_viewport().get_visible_rect().size
	# if resolution.x > lim:
	# 	var ratio = lim / resolution.x
	# 	resolution *= ratio
	# if resolution.y > lim:
	# 	var ratio = lim / resolution.y
	# 	resolution *= ratio
	if resolution.x > view.x || resolution.y > view.y:
		resolution.x = view.x
		print("Changed to: %s" % resolution)
	elif resolution.x < MIN_TEXTURE_SIZE.x || resolution.y < MIN_TEXTURE_SIZE.y:
		resolution.x = MIN_TEXTURE_SIZE.x
		print("Changed to: %s" % resolution)
	_resolution = resolution  # update internal resolution
	
	_resize_output()          # rebuild texture + uniform_set
# ----------------------------------------------------
# --- SETUP FUNCTIONS (Called Once) ---
# ----------------------------------------------------

func _setup_shader():
	var shader_file := load("res://scriptsnscenes/black_hole_combined/bhcompute.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)

func _setup_output_texture():
	# Output texture (Remains the same - created once)
	var fmt := RDTextureFormat.new()
	fmt.width = _resolution.x
	fmt.height = _resolution.y
	fmt.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
					 RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | \
					 RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | \
					 RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	output_tex = rd.texture_create(fmt, RDTextureView.new())

func _create_sampler() -> RID:
	# Sampler is now guaranteed to be permanent.
	var sampler_state := RDSamplerState.new()
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	return rd.sampler_create(sampler_state)

func _setup_uniforms():
	var uniforms := []

	# Binding 0: Output image
	var u_output := RDUniform.new()
	u_output.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_output.binding = 0
	u_output.add_id(output_tex)
	uniforms.append(u_output)

	# Binding 1: Skybox Texture
	skybox_rd_tex = _create_skybox_texture_rid()
	var u_skybox := RDUniform.new()
	u_skybox.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_skybox.binding = 1
	u_skybox.add_id(sampler)
	u_skybox.add_id(skybox_rd_tex)
	uniforms.push_back(u_skybox)

	# Binding 2: Disc noise texture (2D)
	noise_tex = _create_noise_texture_rid()
	var u_noise := RDUniform.new()
	u_noise.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_noise.binding = 2
	u_noise.add_id(sampler)
	u_noise.add_id(noise_tex)
	uniforms.append(u_noise)

	# Binding 3: Uniform buffer
	params_buffer = _create_params_buffer_rid()
	var u_params := RDUniform.new()
	u_params.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u_params.binding = 3
	u_params.add_id(params_buffer)
	uniforms.append(u_params)


	# Create the uniform set once
	uniform_set = rd.uniform_set_create(uniforms, shader, 0)

# ----------------------------------------------------
# --- PERMANENT RID CREATION HELPERS ---
# ----------------------------------------------------

func _create_skybox_texture_rid() -> RID:
	var image_file : Texture2D = skybox_texture
	var image := image_file.get_image()
	image.convert(Image.FORMAT_RGBAH)
	var fmt = RDTextureFormat.new()
	fmt.width = image.get_width()
	fmt.height = image.get_height()
	fmt.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	# Must allow update if brightness or other properties are changed later
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | \
					 RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | \
					 RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	var view = RDTextureView.new()
	return rd.texture_create(fmt, view, [image.get_data()])

func _create_noise_texture_rid() -> RID:
	var img: Image = _get_noise_image_data_full() # Use the data getter
	var fmt := RDTextureFormat.new()
	fmt.width = img.get_width()
	fmt.height = img.get_height()
	fmt.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | \
					 RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT

	var data := img.get_data()
	return rd.texture_create(fmt, RDTextureView.new(), [data])

func _create_params_buffer_rid() -> RID:
	var params_data: PackedByteArray = _get_params_data()
	# Create the buffer once and return its RID
	return rd.uniform_buffer_create(params_data.size(), params_data)

# ----------------------------------------------------
# --- PER-FRAME DATA GETTERS ---
# ----------------------------------------------------

# Gets the full image data for the noise texture (for initial creation)
func _get_noise_image_data_full() -> Image:
	var img: Image
	if disc_noise_texture and disc_noise_texture.noise:
		img = disc_noise_texture.get_image()

	if not img: # Fallback
		img = Image.create(256, 256, false, Image.FORMAT_L8)
		img.fill(Color(0.5, 0.5, 0.5))

	img.convert(Image.FORMAT_R8) # Convert to format matching R8_UNORM
	return img

# Gets the raw byte array for buffer update
func _get_params_data() -> PackedByteArray:
	var params := PackedFloat32Array()

	# Block 1: Black Hole
	params.append_array([black_hole_position.x, black_hole_position.y, black_hole_position.z])
	params.append(schwarzschild_radius)

	# Block 2: Black Hole Color
	params.append_array([black_hole_color.r, black_hole_color.g, black_hole_color.b, black_hole_color.a])

	# Block 3: Camera Position/FOV
	var cam_pos := camera_position
	var cam_target := camera_target
	if use_scene_camera and get_viewport().get_camera_3d():
		cam_pos = get_viewport().get_camera_3d().global_position
		cam_target = black_hole_position

	params.append_array([cam_pos.x, cam_pos.y, cam_pos.z])
	params.append(camera_fov)

	# Block 4: Camera Target / Time
	params.append_array([cam_target.x, cam_target.y, cam_target.z])
	params.append(Time.get_ticks_msec() / 1000.0)

	# Block 5: Rendering Params
	params.append(float(_resolution.x))
	params.append(float(_resolution.y))
	params.append(float(max_steps))
	params.append(step_size)

	# Block 6: Escape/Skybox (with padding)
	params.append(escape_radius)
	params.append(skybox_brightness)
	params.append(0.0) # _pad1.x
	params.append(0.0) # _pad1.y

	# Block 7: Disc Radii/Thickness/Emission
	params.append(disc_inner_radius)
	params.append(disc_outer_radius)
	params.append(disc_thickness)
	params.append(disc_emission_strength * 0.01)

	# Block 8 & 9: Disc Colors
	params.append_array([disc_inner_color.r, disc_inner_color.g, disc_inner_color.b, disc_inner_color.a])
	params.append_array([disc_outer_color.r, disc_outer_color.g, disc_outer_color.b, disc_outer_color.a])

	# Block 10: Disc Enable (with padding)
	params.append(1.0 if enable_disc else 0.0)
	params.append(0.0) # _pad2.x
	params.append(0.0) # _pad2.y
	params.append(0.0) # _pad2.z

	# Block 11: Grid Values
	params.append(1.0 if show_grid else 0.0)
	params.append(grid_spacing)
	params.append(grid_line_thickness)
	params.append(grid_alpha)

	# Block 12: Grid Range/Offset (with padding)
	params.append(grid_range)
	params.append(-grid_offset)
	params.append(0.0) # _pad3.x
	params.append(0.0) # _pad3.y

	# Block 13: Grid Color
	params.append_array([grid_color.r, grid_color.g, grid_color.b, grid_color.a])


	# --- BLOCKS 14 & 15: REMOVED STARS, ADDED GALAXY ---

	# Block 14: Galaxy (Replaces Star Density/Brightness)
	# The Galaxy effect uses three float values: Radius, Height, and Intensity Scale.
	params.append(1.0 if show_galaxy else 0.0)
	params.append(0.0)
	params.append(galaxy_intensity_scale)
	params.append(.01) # _nebula_step_size_start (Padding to fill the vec4/Block 14)

	# Block 15
	params.append_array([
		galaxy_pos.x,
		galaxy_pos.y,
		galaxy_pos.z,
	])
	params.append(0.0) # pad 4

	# Block 16
	params.append(galaxy_scale)
	params.append_array([
		galaxy_rotation.x,
		galaxy_rotation.y,
		galaxy_rotation.z,
	])


	return params.to_byte_array()

# ----------------------------------------------------
# --- PER-FRAME UPDATE (OPTIMIZED) ---
# ----------------------------------------------------

func _resize_output():
	# 1. Create new texture
	_setup_output_texture()

	# 2. Rebuild the first uniform: output image
	var u_output := RDUniform.new()
	u_output.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_output.binding = 0
	u_output.add_id(output_tex)

	# 3. Recreate uniform set (bindings 1–3 reused)
	var uniforms = []

	uniforms.append(u_output)

	# Reuse skybox, noise, and params_buffer bindings
	var u_skybox := RDUniform.new()
	u_skybox.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_skybox.binding = 1
	u_skybox.add_id(sampler)
	u_skybox.add_id(skybox_rd_tex)
	uniforms.append(u_skybox)

	var u_noise := RDUniform.new()
	u_noise.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_noise.binding = 2
	u_noise.add_id(sampler)
	u_noise.add_id(noise_tex)
	uniforms.append(u_noise)

	var u_params := RDUniform.new()
	u_params.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u_params.binding = 3
	u_params.add_id(params_buffer)
	uniforms.append(u_params)

	# 4. Replace old uniform set
	if uniform_set.is_valid():
		rd.free_rid(uniform_set)

	uniform_set = rd.uniform_set_create(uniforms, shader, 0)

func _update_shader():
	if not rd or not pipeline or not uniform_set.is_valid():
		return
	if is_dispatching or _paused: return
	is_dispatching = true
	frame_start_time = Time.get_unix_time_from_system()

	# 1. UPDATE UNIFORM BUFFER DATA (O(1) buffer write)
	var new_params_data: PackedByteArray = _get_params_data()
	if params_buffer.is_valid():
		# Update the contents of the existing buffer RID
		rd.buffer_update(params_buffer, 0, new_params_data.size(), new_params_data)

	 # Only updates once since it takes ages to load, its smooth at first but then loads in
	if update_noise_texture:
		var new_noise_image: Image = _get_noise_image_data_full()
		if noise_tex.is_valid():
			rd.texture_update(noise_tex, 0, new_noise_image.get_data())
		update_noise_texture = false
	
	#if res_changed:
		#_resize_output()
		#var curr = Time.get_unix_time_from_system()
		#var delta = curr-last_time
		#var frame_time = curr-frame_start_time
		#call_deferred("_emit_signal", delta, frame_time)
		#_resolution = resolution
		#return

	# 3. DISPATCH
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	# Uniform Set is PERMANENT and does not need to be recreated!
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)

	# Calculate group count
	var group_x = ceili(_resolution.x / 8.0)
	var group_y = ceili(_resolution.y / 8.0)
	rd.compute_list_dispatch(compute_list, group_x, group_y, 1)
	rd.compute_list_end()

	rd.submit()
	rd.sync()
	is_dispatching = false

	var curr = Time.get_unix_time_from_system()
	var delta = curr-last_time
	var frame_time = curr-frame_start_time
	var frame_delay = rd.get_frame_delay()
	last_time = curr

	_display_result()
	call_deferred("_emit_signal", delta, frame_time, frame_delay)

func _emit_signal(delta: float, frame_time:float, frame_delay:float):
	shader_process_frame.emit(delta, frame_time, frame_delay)

# ----------------------------------------------------
# --- DISPLAY / CLEANUP ---
# ----------------------------------------------------

func _display_result():
	var byte_data := rd.texture_get_data(output_tex, 0)
	if byte_data.size() == 0:
		return

	var img := Image.create_from_data(_resolution.x, _resolution.y, false, Image.FORMAT_RGBAH, byte_data)
	
	var px = img.get_pixel(0, 0)
	#print("First pixel RGBA: ", px)
	
	# Cast is necessary for safety when accessing parent
	var parent_node = get_parent()
	if parent_node is TextureRect:
		(parent_node as TextureRect).texture = ImageTexture.create_from_image(img)
	else:
		# Fallback if the parent isn't a TextureRect (good practice)
		print("WARNING: Parent is not a TextureRect. Cannot display result.")

func _exit_tree():
	if rd:
		# Free all permanent RIDs
		rd.free_rid(output_tex)
		rd.free_rid(shader)
		rd.free_rid(pipeline)
		rd.free_rid(sampler)
		rd.free_rid(params_buffer)
		rd.free_rid(noise_tex)
		rd.free_rid(skybox_rd_tex)
		if uniform_set.is_valid():
			rd.free_rid(uniform_set)
		# Free the local rendering device itself last
		rd.free()
