extends Control
class_name BlackPixhole

@export var vpcont : SubViewportContainer
@export var vp : SubViewport
@export var rect : ColorRect
@export var target_fps : float = 30
var _accum := 0.0
var _time := 0.0
var shader_mat : ShaderMaterial

func _ready():
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	shader_mat = rect.material

func _process(delta):
	# FPS Calculations
	_accum += delta
	
	var interval := 1.0 / target_fps
	if _accum >= interval:
		_accum -= interval
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	
	# Shader time setup
	_time += delta
	shader_mat.set_shader_parameter("time", _time)
