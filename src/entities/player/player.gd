extends CharacterBody3D
@export var move_speed := 7.0
@export var look_sensitivity := 0.0025
@export var vertical_speed := 5.0
@onready var camera: Camera3D = $Camera3D
var pitch := -0.15

func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * look_sensitivity)
		pitch = clamp(pitch - event.relative.y * look_sensitivity, -1.35, 1.35)
		camera.rotation.x = pitch
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(_delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	velocity.y = Input.get_axis("move_down", "move_up") * vertical_speed
	move_and_slide()
	SignalBus.player_position_updated.emit(global_position)
