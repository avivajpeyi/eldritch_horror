extends CharacterBody3D
@export var speed := 2.2
@export var steering_acceleration := 2.5
@export var stopping_distance := 4.0
@export var hover_height := 3.5
var current_state: GameManager.MonsterState = GameManager.MonsterState.ROAM
var player_position := Vector3.ZERO

func _ready() -> void:
	SignalBus.player_position_updated.connect(_on_player_position_updated)
	SignalBus.monster_state_changed.emit(current_state)

func _exit_tree() -> void:
	if SignalBus.player_position_updated.is_connected(_on_player_position_updated):
		SignalBus.player_position_updated.disconnect(_on_player_position_updated)

func _on_player_position_updated(position: Vector3) -> void:
	player_position = position

func _physics_process(delta: float) -> void:
	match current_state:
		GameManager.MonsterState.ROAM:
			_roam(delta)
		GameManager.MonsterState.COLLAPSED:
			velocity = velocity.move_toward(Vector3.ZERO, steering_acceleration * delta)
	move_and_slide()

func _roam(delta: float) -> void:
	var offset := player_position + Vector3.UP * hover_height - global_position
	if offset.length() <= stopping_distance:
		velocity = velocity.move_toward(Vector3.ZERO, steering_acceleration * delta)
		return
	velocity = velocity.move_toward(offset.normalized() * speed, steering_acceleration * delta)

func set_state(next_state: GameManager.MonsterState) -> void:
	if current_state != next_state:
		current_state = next_state
		SignalBus.monster_state_changed.emit(current_state)
