extends TextureRect

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var output_tex: RID
var uniform_set: RID

@export var resolution := Vector2i(1280, 720)
@export var black_hole_position := Vector3(0, 0, 0)
@export var schwarzschild_radius := 2.0
@export var camera_fov := 60.0

func _ready():
	rd = RenderingServer.create_local_rendering_device()
	if not rd:
		push_error("Failed to create RenderingDevice")
		return
	
	_setup_shader()
	_setup_textures()
	_setup_uniforms()

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
	
	# Binding 1: Skybox cubemap (placeholder)
	var skybox_tex := _create_placeholder_cubemap()
	var u_skybox := RDUniform.new()
	u_skybox.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_skybox.binding = 1
	u_skybox.add_id(_create_sampler())
	u_skybox.add_id(skybox_tex)
	uniforms.append(u_skybox)
	
	# Binding 2: Disc noise texture (placeholder)
	var noise_tex := _create_noise_texture()
	var u_noise := RDUniform.new()
	u_noise.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_noise.binding = 2
	u_noise.add_id(_create_sampler())
	u_noise.add_id(noise_tex)
	uniforms.append(u_noise)
	
	# Binding 3: Uniform buffer
	var params := _create_params_buffer()
	var u_params := RDUniform.new()
	u_params.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u_params.binding = 3
	u_params.add_id(params)
	uniforms.append(u_params)
	
	uniform_set = rd.uniform_set_create(uniforms, shader, 0)

func _create_params_buffer() -> RID:
	var params := PackedFloat32Array()
	
	# Black hole (16 bytes alignment)
	params.append_array([black_hole_position.x, black_hole_position.y, black_hole_position.z, schwarzschild_radius])
	params.append_array([0.0, 0.0, 0.0, 1.0])  # black_hole_color
	
	# Camera
	var cam_pos := get_viewport().get_camera_3d().global_position if get_viewport().get_camera_3d() else Vector3(0, 5, 10)
	var cam_target := black_hole_position
	params.append_array([cam_pos.x, cam_pos.y, cam_pos.z, camera_fov])
	params.append_array([cam_target.x, cam_target.y, cam_target.z, Time.get_ticks_msec() / 1000.0])
	
	# Rendering
	params.append_array([float(resolution.x), float(resolution.y), 200.0, 0.5])  # resolution, max_steps, step_size
	params.append_array([1000.0, 2.0, 0.0, 0.0])  # escape_radius, skybox_brightness, padding
	
	# Disc
	params.append_array([4.0, 8.0, 0.2, 3.0])  # inner, outer, thickness, emission
	params.append_array([1.0, 0.5, 0.0, 1.0])  # inner_color
	params.append_array([1.0, 0.8, 0.3, 1.0])  # outer_color
	params.append_array([1.0, 0.0, 0.0, 0.0])  # enable_disc, padding
	
	# Grid
	params.append_array([1.0, 2.0, 0.1, 0.3])  # show_grid, spacing, thickness, alpha
	params.append_array([20.0, 2.0, 0.0, 0.0])  # range, warp_offset, padding
	params.append_array([0.0, 1.0, 1.0, 1.0])  # grid_color
	
	# Stars
	params.append_array([0.001, 1.0, 0.0, 0.0])  # density, brightness, padding
	params.append_array([1.0, 1.0, 1.0, 1.0])  # star_color
	
	return rd.uniform_buffer_create(params.size() * 4, params.to_byte_array())

func _create_sampler() -> RID:
	var sampler_state := RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	return rd.sampler_create(sampler_state)

func _create_placeholder_cubemap() -> RID:
	var fmt := RDTextureFormat.new()
	fmt.width = 64
	fmt.height = 64
	fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt.texture_type = RenderingDevice.TEXTURE_TYPE_CUBE
	fmt.array_layers = 6
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | \
					 RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	
	# Create 6 separate faces for cubemap
	var faces := []
	for i in 6:
		var data := PackedByteArray()
		data.resize(64 * 64 * 4)
		data.fill(50)  # Gray placeholder
		faces.append(data)
	
	return rd.texture_create(fmt, RDTextureView.new(), faces)

func _create_noise_texture() -> RID:
	var fmt := RDTextureFormat.new()
	fmt.width = 256
	fmt.height = 256
	fmt.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | \
					 RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	var data := PackedByteArray()
	for y in 256:
		for x in 256:
			var val := (noise.get_noise_2d(x, y) + 1.0) * 0.5
			data.append(int(val * 255))
	
	return rd.texture_create(fmt, RDTextureView.new(), [data])

func _process(_delta):
	if not rd or not pipeline or not uniform_set.is_valid():
		return
	
	# Dispatch compute shader
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, ceili(resolution.x / 8.0), ceili(resolution.y / 8.0), 1)
	rd.compute_list_end()
	
	rd.submit()
	rd.sync()
	
	# Copy result to viewport (optional - for display)
	_display_result()

func _display_result():
	# Get texture data and display it
	var byte_data := rd.texture_get_data(output_tex, 0)
	var img := Image.create_from_data(resolution.x, resolution.y, false, Image.FORMAT_RGBAH, byte_data)
	
	# Display on a sprite or viewport
	texture = ImageTexture.create_from_image(img) if has_node("Sprite2D") else null

func _exit_tree():
	if rd:
		rd.free_rid(output_tex)
		rd.free_rid(shader)
		rd.free_rid(pipeline)
		rd.free()
