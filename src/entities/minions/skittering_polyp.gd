extends CharacterBody3D

@export var speed := 8.5
@export var acceleration := 25.0
@export var gravity := 24.0
@export var trigger_range := 2.4
@export var fuse_time := 0.75
@export var explosion_damage := 18.0
var target_position := Vector3.ZERO
var _armed := false
var _fuse := 0.0

func _ready() -> void:
	add_to_group("Enemies")
	SignalBus.player_position_updated.connect(_on_player_position)
	_build_body()

func _exit_tree() -> void:
	if SignalBus.player_position_updated.is_connected(_on_player_position):
		SignalBus.player_position_updated.disconnect(_on_player_position)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	var offset := target_position - global_position
	var horizontal := Vector3(offset.x, 0.0, offset.z)
	if not _armed:
		velocity = velocity.move_toward(horizontal.normalized() * speed, acceleration * delta)
		if horizontal.length() <= trigger_range:
			_armed = true
			_fuse = fuse_time
	else:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		_fuse -= delta
		scale = Vector3.ONE * (1.0 + (1.0 - _fuse / fuse_time) * 0.65)
		if _fuse <= 0.0:
			_explode()
	move_and_slide()

func take_damage(_amount: float, _damage_type := GameManager.ElementType.KINETIC) -> void:
	SignalBus.minion_destroyed.emit()
	queue_free()

func hitscan_hit(damage: float, _direction: Vector3, _position: Vector3) -> void:
	take_damage(damage)

func _explode() -> void:
	SignalBus.player_damage_requested.emit(explosion_damage, global_position, (target_position - global_position).normalized() * 8.0 + Vector3.UP * 3.0)
	queue_free()

func _on_player_position(position: Vector3) -> void:
	target_position = position

func _build_body() -> void:
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.45
	shape.height = 0.9
	collision.shape = shape
	add_child(collision)
	var mesh_instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.48
	mesh.height = 0.8
	mesh.radial_segments = 10
	mesh.rings = 6
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("68142d")
	material.roughness = 0.3
	mesh.material = material
	mesh_instance.mesh = mesh
	add_child(mesh_instance)

