extends Area3D

@export var damage := 12.0
@export var lifetime := 7.0
@export var projectile_gravity := 18.0
@export var hazardous_duration := 5.0
var velocity := Vector3.ZERO
var _stuck := false

func _ready() -> void:
	collision_layer = 0
	# Layer 1 catches architecture; layer 2 catches the FPS player.
	collision_mask = 3
	monitoring = true
	body_entered.connect(_on_body_entered)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.28
	shape.shape = sphere
	add_child(shape)
	var mesh_instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.85
	mesh.radial_segments = 7
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("721a35")
	material.emission_enabled = true
	material.emission = Color("3d0717")
	material.emission_energy_multiplier = 2.0
	mesh.material = material
	mesh_instance.mesh = mesh
	add_child(mesh_instance)

func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	if _stuck:
		return
	velocity += Vector3.DOWN * projectile_gravity * delta
	global_position += velocity * delta
	rotation.x += delta * 9.0
	if global_position.y <= 0.45:
		_stick_to_floor()

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		SignalBus.player_damage_requested.emit(damage, global_position, velocity.normalized() * 7.0)
		queue_free()
	elif not _stuck:
		_stick_to_floor()

func _stick_to_floor() -> void:
	_stuck = true
	global_position.y = maxf(global_position.y, 0.32)
	lifetime = hazardous_duration
	scale = Vector3(1.7, 0.35, 1.7)
