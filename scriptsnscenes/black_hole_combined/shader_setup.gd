extends Node
class_name ShaderSetup

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var output_tex: RID
var uniform_set: RID
var skybox_tex: RID
var skybox_tex_local: RID = RID()
var skybox_ready := false
var noise_tex: RID
var sampler: RID
var params_buffer: RID

# Rendering
@export_group("Rendering")
@export var resolution := Vector2i(1280, 720)
@export_range(100, 2000) var max_steps := 500
@export_range(0.01, 1.0) var step_size := 0.1
@export_range(50.0, 500.0) var escape_radius := 100.0
@export_range(0.1, 5.0) var skybox_brightness := 1.5

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
@export_range(0.1, 5.0) var disc_thickness := 0.3
@export_range(0.1, 20.0) var disc_emission_strength := 5.0
@export var disc_inner_color := Color(1.0, 0.3, 0.1, 1.0)
@export var disc_outer_color := Color(1.0, 0.8, 0.3, 1.0)
@export var disc_noise_texture: NoiseTexture2D

# Grid
@export_group("Spacetime Grid")
@export var show_grid := true
@export_range(0.5, 10.0) var grid_spacing := 2.0
@export_range(0.01, 0.5) var grid_line_thickness := 0.08
@export_range(-50, 50) var grid_offset : float = 0
@export_range(0.0, 1.0) var grid_alpha := 0.5
@export_range(10.0, 100.0) var grid_range := 30.0
@export var grid_color := Color(0.3, 0.8, 1.0, 1.0)

# Stars
@export_group("Stars")
@onready var skybox_texture = preload("uid://b0askaxfx5mvr")
#@export var skybox_texture : Texture2D
@export_range(0.0, 0.01) var star_density := 0.002
@export_range(0.0, 5.0) var star_brightness := 2.0
@export var star_color := Color(1.0, 1.0, 1.0, 1.0)

func _ready():
	rd = RenderingServer.create_local_rendering_device()
	if not rd:
		push_error("Failed to create RenderingDevice")
		return
	sampler = _create_sampler()
	_setup_shader()
	_setup_textures()
	
	_upload_skybox_when_ready()
	skybox_tex_local = await _create_local_skybox_texture(skybox_texture.get_image())
	_setup_uniforms()

	# Debug: print camera info
	var cam = get_viewport().get_camera_3d()
	if cam:
		print("Camera pos: ", cam.global_position)
		print("Black hole pos: ", black_hole_position)
	else:
		print("WARNING: No camera found!")

	_update_shader()

func _setup_shader():
	var shader_file := load("res://scriptsnscenes/black_hole_combined/bhcompute.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)

func _setup_textures():
	# Output texture
	var fmt := RDTextureFormat.new()
	fmt.width = resolution.x
	fmt.height = resolution.y
	fmt.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
					 RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | \
					 RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | \
					 RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT

	output_tex = rd.texture_create(fmt, RDTextureView.new())

func _setup_uniforms():
	var uniforms := []

	# Binding 0: Output image
	var u_output := RDUniform.new()
	u_output.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_output.binding = 0
	u_output.add_id(output_tex)
	uniforms.append(u_output)

	# Binding 1: Skybox Texture
	var u_skybox = RDUniform.new()
	u_skybox.binding = 1
	u_skybox.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_skybox.add_id(sampler)
	u_skybox.add_id(_get_skybox_rid_for_shader())
	uniforms.append(u_skybox)

	# Binding 2: Disc noise texture
	var noise_tex_rid := _create_noise_texture() # The RID of the texture
	var u_noise := RDUniform.new()
	u_noise.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_noise.binding = 2
	u_noise.add_id(sampler)
	u_noise.add_id(noise_tex_rid)
	uniforms.append(u_noise)

	# Binding 3: Uniform buffer
	var params := _create_params_buffer()
	var u_params := RDUniform.new()
	u_params.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u_params.binding = 3
	u_params.add_id(params)
	uniforms.append(u_params)

	uniform_set = rd.uniform_set_create(uniforms, shader, 0)

# ------------------------------------------------------------------
# NEW: This function keeps trying until the image is actually ready
# ------------------------------------------------------------------
func _upload_skybox_when_ready():
	if skybox_ready:
		return

	if not skybox_texture:
		push_error("skybox_texture is null!")
		return

	var img := skybox_texture.get_image()
	if img and img.get_width() > 0 and img.get_height() > 0:
		# SUCCESS – finally got the real image data
		if skybox_tex_local.is_valid():
			rd.free_rid(skybox_tex_local)

		skybox_tex_local = await _create_local_skybox_texture(img)
		skybox_ready = true
		print("Skybox successfully uploaded to local RD (", img.get_width(), "×", img.get_height(), ")")
	else:
		# Still not ready → try again next frame
		get_tree().process_frame.connect(_upload_skybox_when_ready, CONNECT_ONE_SHOT)

# ------------------------------------------------------------------
# Separate function that ALWAYS returns a valid RID (black fallback if needed)
# ------------------------------------------------------------------
func _get_skybox_rid_for_shader() -> RID:
	if skybox_ready and skybox_tex_local.is_valid():
		return skybox_tex_local

	# Return a tiny valid black texture so the shader never gets an invalid RID
	if not skybox_tex_local.is_valid():
		var black := Image.create(1, 1, false, Image.FORMAT_RGB8)
		black.fill(Color(0,0,0))

		var tf := RDTextureFormat.new()
		tf.width = 1
		tf.height = 1
		tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
		tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D

		skybox_tex_local = rd.texture_create(tf, RDTextureView.new(), [black.get_data()])

	return skybox_tex_local

func _create_params_buffer() -> RID:
	var params := PackedFloat32Array()

	# Block 1
	params.append_array([black_hole_position.x, black_hole_position.y, black_hole_position.z])
	params.append(schwarzschild_radius)

	# Block 2
	params.append_array([black_hole_color.r, black_hole_color.g, black_hole_color.b, black_hole_color.a])

	# Block 3: Camera
	var cam_pos := camera_position
	var cam_target := camera_target
	if use_scene_camera and get_viewport().get_camera_3d():
		cam_pos = get_viewport().get_camera_3d().global_position
		# If you want camera to look at BH, keep target as BH pos
		cam_target = black_hole_position

	params.append_array([cam_pos.x, cam_pos.y, cam_pos.z])
	params.append(camera_fov)

	# Block 4
	params.append_array([cam_target.x, cam_target.y, cam_target.z])
	params.append(Time.get_ticks_msec() / 1000.0)

	# Block 5: Rendering
	params.append(float(resolution.x))
	params.append(float(resolution.y))
	params.append(float(max_steps)) # Float!
	params.append(step_size)

	# Block 6 (With padding)
	params.append(escape_radius)
	params.append(skybox_brightness)
	params.append(0.0) # _pad1.x
	params.append(0.0) # _pad1.y

	# Block 7: Disc Values
	params.append(disc_inner_radius)
	params.append(disc_outer_radius)
	params.append(disc_thickness)
	params.append(disc_emission_strength)

	# Block 8 & 9: Colors
	params.append_array([disc_inner_color.r, disc_inner_color.g, disc_inner_color.b, disc_inner_color.a])
	params.append_array([disc_outer_color.r, disc_outer_color.g, disc_outer_color.b, disc_outer_color.a])

	# Block 10: Disc Enable (With padding)
	params.append(1.0 if enable_disc else 0.0) # Float!
	params.append(0.0) # _pad2.x
	params.append(0.0) # _pad2.y
	params.append(0.0) # _pad2.z

	# Block 11: Grid Values
	params.append(1.0 if show_grid else 0.0) # Float!
	params.append(grid_spacing)
	params.append(grid_line_thickness)
	params.append(grid_alpha)

	# Block 12: Grid Range (With padding)
	params.append(grid_range)
	params.append(grid_offset) # warp offset
	params.append(0.0) # _pad3.x
	params.append(0.0) # _pad3.y

	# Block 13: Grid Color
	params.append_array([grid_color.r, grid_color.g, grid_color.b, grid_color.a])

	# Block 14: Stars (With padding)
	params.append(star_density)
	params.append(star_brightness)
	params.append(0.0) # _pad4.x
	params.append(0.0) # _pad4.y

	# Block 15: Star Color (Offset 224)
	params.append_array([star_color.r, star_color.g, star_color.b, star_color.a])

	# Block 16: FINAL PADDING (Offset 240) - Total size MUST be 256 bytes
	params.append_array([0.0, 0.0, 0.0, 0.0]) # vec4 _final_padding
	return rd.uniform_buffer_create(params.size() * 4, params.to_byte_array())

func _create_sampler() -> RID:
	var sampler_state := RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR

	# Store the RID in the member variable
	return rd.sampler_create(sampler_state)

func _create_local_skybox_texture(img:Image) -> RID:
	
	# Sometimes get_image() returns null on first frame (especially with .hdr imports)
	if not img:
		push_warning("Skybox image not ready yet, waiting one frame...")
		await get_tree().process_frame
		img = skybox_texture.get_image()
	
	if not img:
		push_error("Still no image! Creating fallback.")
		img = Image.create(2, 1, false, Image.FORMAT_RGB8)
		img.fill(Color(0.1, 0.0, 0.2))  # Dark purple fallback

	var tf := RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM    # Change if you use HDR!
	tf.width = img.get_width()
	tf.height = img.get_height()
	tf.depth = 1
	tf.array_layers = 1
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT

	var view := RDTextureView.new()
	# Optional: if source is sRGB (like .png/.jpg), enable SRGB
	view.format_override = RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB

	var texture_data: PackedByteArray = img.get_data()

	return rd.texture_create(tf, view, [texture_data])

func _create_noise_texture() -> RID:
	var img: Image

	if disc_noise_texture and disc_noise_texture.noise:
		# Force generation if not ready, or get current data
		img = disc_noise_texture.get_image()

	# Fallback if image is null (not generated yet)
	if not img:
		img = Image.create(256, 256, false, Image.FORMAT_L8)
		img.fill(Color(0.5, 0.5, 0.5)) # Mid-grey noise fallback

	var fmt := RDTextureFormat.new()
	fmt.width = img.get_width()
	fmt.height = img.get_height()
	# The shader sampler is float/norm, so R8_UNORM is fine
	fmt.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | \
					 RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT

	var data := img.get_data()
	return rd.texture_create(fmt, RDTextureView.new(), [data])

func _update_shader():
	if not rd or not pipeline or not uniform_set.is_valid():
		return

	# Recreate uniform buffer each frame to pick up changes
	var params := _create_params_buffer()
	var u_params := RDUniform.new()
	u_params.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u_params.binding = 3
	u_params.add_id(params)

	# Get existing output
	var uniforms := []
	var u_output := RDUniform.new()
	u_output.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_output.binding = 0
	u_output.add_id(output_tex)
	uniforms.append(u_output)

	# Binding 1: Skybox Texture
	var skybox_rid: RID
	if skybox_texture and skybox_texture.get_rid().is_valid():
		skybox_rid = skybox_texture.get_rid()

	var sampler = _create_sampler()

	var u_skybox := RDUniform.new()
	u_skybox.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_skybox.binding = 1
	u_skybox.add_id(sampler)
	u_skybox.add_id(skybox_rid)
	uniforms.append(u_skybox)

	# Binding 2: Disc noise texture
	var noise_tex_rid := _create_noise_texture()
	var u_noise := RDUniform.new()
	u_noise.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_noise.binding = 2
	u_noise.add_id(sampler)
	u_noise.add_id(noise_tex_rid)
	uniforms.append(u_noise)

	uniforms.append(u_params)

	# Recreate uniform set
	if uniform_set.is_valid():
		rd.free_rid(uniform_set)
	uniform_set = rd.uniform_set_create(uniforms, shader, 0)

	# Dispatch compute shader
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, ceili(resolution.x / 8.0), ceili(resolution.y / 8.0), 1)
	rd.compute_list_end()

	rd.submit()
	rd.sync()

	# Copy result to viewport
	_display_result()

func _display_result():
	# Get texture data and display it
	var byte_data := rd.texture_get_data(output_tex, 0)
	if byte_data.size() == 0:
		print("ERROR: No texture data!")
		return

	var img := Image.create_from_data(resolution.x, resolution.y, false, Image.FORMAT_RGBAH, byte_data)
	(get_parent() as TextureRect).texture = ImageTexture.create_from_image(img)

func _exit_tree():
	if rd:
		rd.free_rid(output_tex)
		rd.free_rid(shader)
		rd.free_rid(pipeline)
		if uniform_set.is_valid():
			rd.free_rid(uniform_set)
		rd.free()
