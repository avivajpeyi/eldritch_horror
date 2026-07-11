extends Node

signal motion_override_changed(enabled: bool)
signal velocity_requested(velocity: Vector3)
signal visual_compression_requested(amount: float)

enum Attack { NONE, PILLAR_LEAP, TENDRIL_WHIP, SHRAPNEL, ANCHOR_SWEEP, FLESH_PODS }
enum Phase { IDLE, TELEGRAPH, ACTIVE, RECOVERY }

@export var first_attack_delay := 3.0
@export var attack_cooldown := 3.5
@export var pillar_leap_damage := 30.0
@export var whip_damage := 24.0
@export var sweep_damage := 28.0

var current_attack := Attack.NONE
var phase := Phase.IDLE
var player_position := Vector3.ZERO
var _timer := 0.0
var _cooldown := 0.0
var _launch_direction := Vector3.ZERO
var _arena_root: Node3D

const CombatArea = preload("res://src/entities/monster/components/combat_area.gd")
const PhysicalProjectile = preload("res://src/entities/monster/components/physical_projectile.gd")
const SkitteringPolyp = preload("res://src/entities/minions/skittering_polyp.gd")

func _ready() -> void:
	_cooldown = first_attack_delay
	SignalBus.player_position_updated.connect(_on_player_position)
	_arena_root = get_tree().current_scene

func _exit_tree() -> void:
	if SignalBus.player_position_updated.is_connected(_on_player_position):
		SignalBus.player_position_updated.disconnect(_on_player_position)

func update_attack(delta: float, monster_position: Vector3, on_ceiling: bool) -> void:
	if phase == Phase.IDLE:
		_cooldown -= delta
		if _cooldown <= 0.0:
			_choose_attack(monster_position, on_ceiling)
		return
	_timer -= delta
	match current_attack:
		Attack.PILLAR_LEAP:
			_update_pillar_leap(monster_position)
		Attack.TENDRIL_WHIP:
			_update_whip(monster_position)
		Attack.SHRAPNEL:
			_update_shrapnel(monster_position)
		Attack.ANCHOR_SWEEP:
			_update_sweep(monster_position)
		Attack.FLESH_PODS:
			_update_pods(monster_position)

func is_overriding_motion() -> bool:
	return current_attack == Attack.PILLAR_LEAP and phase != Phase.IDLE

func _choose_attack(monster_position: Vector3, on_ceiling: bool) -> void:
	var choices: Array[int]
	if on_ceiling or monster_position.y > 8.0:
		choices = [Attack.TENDRIL_WHIP, Attack.SHRAPNEL, Attack.FLESH_PODS]
	else:
		choices = [Attack.PILLAR_LEAP, Attack.TENDRIL_WHIP, Attack.ANCHOR_SWEEP]
	_begin_attack(choices.pick_random(), monster_position)

func _begin_attack(attack: Attack, monster_position: Vector3) -> void:
	current_attack = attack
	phase = Phase.TELEGRAPH
	match attack:
		Attack.PILLAR_LEAP:
			_timer = 1.5
			_launch_direction = (player_position - monster_position)
			_launch_direction.y = 0.0
			_launch_direction = _launch_direction.normalized()
			visual_compression_requested.emit(0.55)
			motion_override_changed.emit(true)
			velocity_requested.emit(Vector3.ZERO)
			SignalBus.attack_telegraphed.emit(&"Pillar Leap", monster_position, _timer)
		Attack.TENDRIL_WHIP:
			_timer = 1.0
			_spawn_telegraph(player_position, 3.2, _timer)
			SignalBus.attack_telegraphed.emit(&"Tendril Whip", player_position, _timer)
		Attack.SHRAPNEL:
			_timer = 1.15
			SignalBus.attack_telegraphed.emit(&"Fleshy Shrapnel", monster_position, _timer)
		Attack.ANCHOR_SWEEP:
			_timer = 1.0
			SignalBus.attack_telegraphed.emit(&"Anchor Sweep", monster_position, _timer)
		Attack.FLESH_PODS:
			_timer = 1.0
			SignalBus.attack_telegraphed.emit(&"Flesh Pods", monster_position, _timer)

func _update_pillar_leap(monster_position: Vector3) -> void:
	if phase == Phase.TELEGRAPH and _timer <= 0.0:
		phase = Phase.ACTIVE
		_timer = 0.9
		visual_compression_requested.emit(0.0)
		velocity_requested.emit(_launch_direction * 28.0)
		_spawn_attached_hit_area(Vector3(2.4, 2.2, 3.2), pillar_leap_damage, 0.9)
	elif phase == Phase.ACTIVE:
		velocity_requested.emit(_launch_direction * 28.0)
		if _timer <= 0.0:
			_finish_attack()

func _update_whip(monster_position: Vector3) -> void:
	if phase == Phase.TELEGRAPH and _timer <= 0.0:
		_spawn_hit_area(player_position, Vector3(3.2, 1.1, 3.2), whip_damage, 0.3)
		phase = Phase.RECOVERY
		_timer = 0.65
	elif phase == Phase.RECOVERY and _timer <= 0.0:
		_finish_attack()

func _update_shrapnel(monster_position: Vector3) -> void:
	if phase == Phase.TELEGRAPH and _timer <= 0.0:
		for index in 14:
			var direction := Vector3(randf_range(-0.65, 0.65), -1.0, randf_range(-0.65, 0.65)).normalized()
			_spawn_projectile(monster_position + direction, direction * randf_range(9.0, 14.0))
		phase = Phase.RECOVERY
		_timer = 1.0
	elif phase == Phase.RECOVERY and _timer <= 0.0:
		_finish_attack()

func _update_sweep(monster_position: Vector3) -> void:
	if phase == Phase.TELEGRAPH and _timer <= 0.0:
		_spawn_hit_area(monster_position + Vector3.DOWN * 1.0, Vector3(9.0, 0.75, 9.0), sweep_damage, 0.45)
		phase = Phase.RECOVERY
		_timer = 0.8
	elif phase == Phase.RECOVERY and _timer <= 0.0:
		_finish_attack()

func _update_pods(monster_position: Vector3) -> void:
	if phase == Phase.TELEGRAPH and _timer <= 0.0:
		for index in 5:
			_spawn_polyp(monster_position + Vector3(randf_range(-2.5, 2.5), 0.0, randf_range(-2.5, 2.5)))
		phase = Phase.RECOVERY
		_timer = 1.0
	elif phase == Phase.RECOVERY and _timer <= 0.0:
		_finish_attack()

func _finish_attack() -> void:
	current_attack = Attack.NONE
	phase = Phase.IDLE
	_cooldown = attack_cooldown + randf_range(-0.5, 1.2)
	motion_override_changed.emit(false)
	visual_compression_requested.emit(0.0)

func _spawn_hit_area(position: Vector3, size: Vector3, damage: float, duration: float) -> void:
	var area := CombatArea.new()
	area.damage = damage
	area.active_time = duration
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size * 2.0
	collision.shape = shape
	area.add_child(collision)
	_arena_root.add_child(area)
	area.global_position = position

func _spawn_attached_hit_area(size: Vector3, damage: float, duration: float) -> void:
	var area := CombatArea.new()
	area.damage = damage
	area.active_time = duration
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size * 2.0
	collision.shape = shape
	area.add_child(collision)
	get_parent().add_child(area)
	area.position = Vector3.ZERO

func _spawn_telegraph(position: Vector3, radius: float, duration: float) -> void:
	var marker := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.035
	mesh.radial_segments = 48
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.9, 0.02, 0.04, 0.5)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color("d50024")
	material.emission_energy_multiplier = 4.0
	mesh.material = material
	marker.mesh = mesh
	_arena_root.add_child(marker)
	marker.global_position = Vector3(position.x, 0.55, position.z)
	var tween := marker.create_tween()
	tween.tween_property(marker, "scale", Vector3(0.12, 1.0, 0.12), duration).from(Vector3.ONE)
	tween.tween_callback(marker.queue_free)

func _spawn_projectile(position: Vector3, initial_velocity: Vector3) -> void:
	var projectile := PhysicalProjectile.new()
	projectile.velocity = initial_velocity
	_arena_root.add_child(projectile)
	projectile.global_position = position

func _spawn_polyp(position: Vector3) -> void:
	var polyp := SkitteringPolyp.new()
	_arena_root.add_child(polyp)
	polyp.global_position = position

func _on_player_position(position: Vector3) -> void:
	player_position = position
