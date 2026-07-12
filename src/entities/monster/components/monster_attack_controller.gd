extends Node
## Attack selection and lifecycle only. Movement requests and player damage remain
## decoupled through signals and SignalBus.

signal motion_override_changed(enabled: bool)
signal velocity_requested(velocity: Vector3)
signal visual_compression_requested(amount: float)

enum Attack { NONE, PILLAR_LEAP, TENDRIL_WHIP, SHRAPNEL, ANCHOR_SWEEP, EYE_SWARM }
enum Phase { IDLE, TELEGRAPH, ACTIVE, RECOVERY }

const ROAM_STATE = preload("res://src/entities/monster/states/state_roam.gd")
const ARTILLERY_STATE = preload("res://src/entities/monster/states/state_artillery.gd")
const NEST_STATE = preload("res://src/entities/monster/states/state_nest.gd")
const CombatArea = preload("res://src/entities/monster/components/combat_area.gd")
const PhysicalProjectile = preload("res://src/entities/monster/components/physical_projectile.gd")
const SWARM_EYE_SCENE: PackedScene = preload("res://src/entities/minions/swarm_eye.tscn")

@export_category("Timing")
@export var first_attack_delay := 1.8
@export var attack_cooldown := 1.75
@export var phase_change_delay := 0.55
@export_category("Damage")
@export var pillar_leap_damage := 34.0
@export var whip_damage := 28.0
@export var shrapnel_damage := 16.0
@export var sweep_damage := 32.0
@export_category("Eye Swarm")
@export_range(1, 8) var eye_swarm_limit := 6
@export_range(1, 4) var eye_swarm_spawn_count := 3
@export_range(1, 3) var eye_swarm_attack_slots := 2

var current_attack := Attack.NONE
var phase := Phase.IDLE
var player_position := Vector3.ZERO

var _timer := 0.0
var _cooldown := 0.0
var _launch_direction := Vector3.ZERO
var _locked_target_position := Vector3.ZERO
var _arena_root: Node3D
var _enabled := true
var _last_attack := Attack.NONE
var _encounter_state: GameManager.MonsterState = GameManager.MonsterState.ROAM
var _state_profile: RefCounted = ROAM_STATE.new()
var _active_eye_attackers: Dictionary = {}
var _pending_eye_attackers: Array[int] = []


func _ready() -> void:
	_cooldown = first_attack_delay
	SignalBus.player_position_updated.connect(_on_player_position)
	SignalBus.monster_state_changed.connect(_on_monster_state_changed)
	SignalBus.eye_swarm_attack_slot_requested.connect(_on_eye_attack_slot_requested)
	SignalBus.eye_swarm_attack_slot_released.connect(_on_eye_attack_slot_released)
	SignalBus.eye_swarm_member_removed.connect(_on_eye_member_removed)
	_arena_root = get_tree().current_scene
	if _arena_root == null and get_parent() != null:
		_arena_root = get_parent().get_parent() as Node3D
	_publish_phase(Phase.IDLE, _cooldown)


func _exit_tree() -> void:
	if SignalBus.player_position_updated.is_connected(_on_player_position):
		SignalBus.player_position_updated.disconnect(_on_player_position)
	if SignalBus.monster_state_changed.is_connected(_on_monster_state_changed):
		SignalBus.monster_state_changed.disconnect(_on_monster_state_changed)
	if SignalBus.eye_swarm_attack_slot_requested.is_connected(_on_eye_attack_slot_requested):
		SignalBus.eye_swarm_attack_slot_requested.disconnect(_on_eye_attack_slot_requested)
	if SignalBus.eye_swarm_attack_slot_released.is_connected(_on_eye_attack_slot_released):
		SignalBus.eye_swarm_attack_slot_released.disconnect(_on_eye_attack_slot_released)
	if SignalBus.eye_swarm_member_removed.is_connected(_on_eye_member_removed):
		SignalBus.eye_swarm_member_removed.disconnect(_on_eye_member_removed)


func update_attack(delta: float, monster_position: Vector3, on_elevated_surface: bool) -> void:
	if not _enabled:
		return
	if phase == Phase.IDLE:
		_cooldown -= delta
		if _cooldown <= 0.0:
			_choose_attack(monster_position, on_elevated_surface)
		return

	_timer -= delta
	match phase:
		Phase.TELEGRAPH:
			if _timer <= 0.0:
				_activate_attack(monster_position)
		Phase.ACTIVE:
			_update_active_attack()
			if _timer <= 0.0:
				_begin_recovery()
		Phase.RECOVERY:
			if _timer <= 0.0:
				_finish_attack()


func set_attack_enabled(enabled_value: bool) -> void:
	if _enabled == enabled_value:
		return
	_enabled = enabled_value
	if not _enabled:
		cancel_attack()
	else:
		_cooldown = maxf(_cooldown, phase_change_delay)


func cancel_attack() -> void:
	motion_override_changed.emit(false)
	velocity_requested.emit(Vector3.ZERO)
	visual_compression_requested.emit(0.0)
	current_attack = Attack.NONE
	phase = Phase.IDLE
	_timer = 0.0
	SignalBus.attack_phase_changed.emit(&"", &"IDLE", _cooldown)


func is_overriding_motion() -> bool:
	return current_attack == Attack.PILLAR_LEAP and phase in [Phase.TELEGRAPH, Phase.ACTIVE]


func get_attack_name() -> StringName:
	return _attack_display_name(current_attack)


func get_phase_name() -> StringName:
	return StringName(Phase.keys()[phase])


func get_time_remaining() -> float:
	return _cooldown if phase == Phase.IDLE else _timer


func _choose_attack(monster_position: Vector3, on_elevated_surface: bool) -> void:
	var names: Array[StringName] = _state_profile.attack_pool(on_elevated_surface)
	var pool: Array[int] = []
	for attack_name in names:
		var attack := _attack_from_profile_name(attack_name)
		if attack == Attack.ANCHOR_SWEEP and monster_position.distance_to(player_position) > 11.0:
			continue
		if attack != Attack.NONE and attack != _last_attack:
			pool.append(attack)
	if pool.is_empty():
		for attack_name in names:
			var attack := _attack_from_profile_name(attack_name)
			if attack != Attack.NONE:
				pool.append(attack)
	if pool.is_empty():
		_cooldown = 1.0
		return
	_begin_attack(pool.pick_random() as Attack, monster_position)


func _begin_attack(attack: Attack, monster_position: Vector3) -> void:
	current_attack = attack
	var attack_name := _attack_display_name(attack)
	var telegraph_time := _telegraph_duration(attack)
	var telegraph_position := monster_position

	match attack:
		Attack.PILLAR_LEAP:
			_launch_direction = player_position - monster_position
			_launch_direction.y = 0.0
			_launch_direction = _launch_direction.normalized()
			visual_compression_requested.emit(0.55)
			motion_override_changed.emit(true)
			velocity_requested.emit(Vector3.ZERO)
			_spawn_line_effect(monster_position, monster_position + _launch_direction * 10.0, 0.16, Color(0.95, 0.08, 0.04, 0.72), telegraph_time)
		Attack.TENDRIL_WHIP:
			_locked_target_position = player_position
			telegraph_position = _locked_target_position
			_spawn_telegraph(_locked_target_position, 3.2, telegraph_time)
			visual_compression_requested.emit(0.22)
		Attack.SHRAPNEL:
			_locked_target_position = player_position
			_spawn_pulse_sphere(monster_position, 3.4, Color(0.72, 0.03, 0.14, 0.48), telegraph_time)
			_spawn_telegraph(_locked_target_position, 4.2, telegraph_time)
			visual_compression_requested.emit(0.34)
		Attack.ANCHOR_SWEEP:
			_spawn_telegraph(monster_position, 8.5, telegraph_time)
			visual_compression_requested.emit(0.3)
		Attack.EYE_SWARM:
			_spawn_pulse_sphere(monster_position, 2.7, Color(0.46, 0.02, 0.24, 0.5), telegraph_time)
			visual_compression_requested.emit(0.4)

	SignalBus.attack_telegraphed.emit(attack_name, telegraph_position, telegraph_time)
	_set_phase(Phase.TELEGRAPH, telegraph_time)


func _activate_attack(monster_position: Vector3) -> void:
	visual_compression_requested.emit(0.0)
	var active_time := _active_duration(current_attack)
	match current_attack:
		Attack.PILLAR_LEAP:
			velocity_requested.emit(_launch_direction * 28.0)
			_spawn_attached_hit_area(Vector3(2.8, 2.4, 3.6), pillar_leap_damage, active_time)
		Attack.TENDRIL_WHIP:
			_spawn_lock_flash(_locked_target_position, 3.2)
			_spawn_hit_area(_locked_target_position, Vector3(4.0, 1.5, 4.0), whip_damage, active_time)
			_spawn_line_effect(monster_position, _locked_target_position, 0.38, Color(0.78, 0.015, 0.055, 0.95), active_time)
		Attack.SHRAPNEL:
			_spawn_lock_flash(_locked_target_position, 4.2)
			_spawn_shrapnel_volley(monster_position, _locked_target_position)
		Attack.ANCHOR_SWEEP:
			_spawn_hit_area(monster_position + Vector3.DOWN, Vector3(9.0, 0.75, 9.0), sweep_damage, active_time)
			_spawn_sweep_effect(monster_position, active_time)
		Attack.EYE_SWARM:
			_spawn_eye_swarm(monster_position)
	_set_phase(Phase.ACTIVE, active_time)


func _update_active_attack() -> void:
	if current_attack == Attack.PILLAR_LEAP:
		velocity_requested.emit(_launch_direction * 28.0)


func _begin_recovery() -> void:
	if current_attack == Attack.PILLAR_LEAP:
		motion_override_changed.emit(false)
		velocity_requested.emit(Vector3.ZERO)
	visual_compression_requested.emit(0.12)
	_set_phase(Phase.RECOVERY, _recovery_duration(current_attack))


func _finish_attack() -> void:
	_last_attack = current_attack
	visual_compression_requested.emit(0.0)
	motion_override_changed.emit(false)
	velocity_requested.emit(Vector3.ZERO)
	current_attack = Attack.NONE
	phase = Phase.IDLE
	_cooldown = (attack_cooldown + randf_range(-0.35, 0.8)) * _state_profile.cooldown_multiplier()
	SignalBus.attack_phase_changed.emit(&"", &"IDLE", _cooldown)


func _set_phase(next_phase: Phase, duration: float) -> void:
	phase = next_phase
	_timer = duration
	_publish_phase(next_phase, duration)


func _publish_phase(next_phase: Phase, duration: float) -> void:
	SignalBus.attack_phase_changed.emit(_attack_display_name(current_attack), StringName(Phase.keys()[next_phase]), duration)


func _telegraph_duration(attack: Attack) -> float:
	match attack:
		Attack.PILLAR_LEAP: return 1.55
		Attack.TENDRIL_WHIP: return 1.35
		Attack.SHRAPNEL: return 1.5
		Attack.ANCHOR_SWEEP: return 1.3
		Attack.EYE_SWARM: return 1.35
	return 0.5


func _active_duration(attack: Attack) -> float:
	match attack:
		Attack.PILLAR_LEAP: return 0.72
		Attack.TENDRIL_WHIP: return 0.32
		Attack.SHRAPNEL: return 0.4
		Attack.ANCHOR_SWEEP: return 0.45
		Attack.EYE_SWARM: return 0.5
	return 0.25


func _recovery_duration(attack: Attack) -> float:
	match attack:
		Attack.PILLAR_LEAP: return 0.8
		Attack.TENDRIL_WHIP: return 0.65
		Attack.SHRAPNEL: return 1.0
		Attack.ANCHOR_SWEEP: return 0.8
		Attack.EYE_SWARM: return 1.0
	return 0.5


func _attack_display_name(attack: Attack) -> StringName:
	match attack:
		Attack.PILLAR_LEAP: return &"Pillar Surge"
		Attack.TENDRIL_WHIP: return &"Tendril Whip"
		Attack.SHRAPNEL: return &"Fleshy Shrapnel"
		Attack.ANCHOR_SWEEP: return &"Tail Sweep"
		Attack.EYE_SWARM: return &"Eye Swarm"
	return &""


func _attack_from_profile_name(attack_name: StringName) -> Attack:
	match attack_name:
		&"PILLAR_LEAP": return Attack.PILLAR_LEAP
		&"TENDRIL_WHIP": return Attack.TENDRIL_WHIP
		&"SHRAPNEL": return Attack.SHRAPNEL
		&"ANCHOR_SWEEP": return Attack.ANCHOR_SWEEP
		&"EYE_SWARM": return Attack.EYE_SWARM
	return Attack.NONE


func _profile_for_state(state: GameManager.MonsterState) -> RefCounted:
	match state:
		GameManager.MonsterState.ARTILLERY: return ARTILLERY_STATE.new()
		GameManager.MonsterState.NEST: return NEST_STATE.new()
	return ROAM_STATE.new()


func _spawn_hit_area(position: Vector3, size: Vector3, damage: float, duration: float) -> void:
	var area := CombatArea.new()
	area.damage = damage
	area.active_time = duration
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size * 2.0
	collision.shape = shape
	area.add_child(collision)
	_effect_root().add_child(area)
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
	mesh.material = _effect_material(Color(1.0, 0.58, 0.04, 0.58), 4.0)
	marker.mesh = mesh
	_effect_root().add_child(marker)
	marker.global_position = Vector3(position.x, 0.55, position.z)
	var tween := marker.create_tween()
	tween.set_parallel(true)
	tween.tween_property(marker, "scale", Vector3(0.12, 1.0, 0.12), duration).from(Vector3.ONE)
	tween.tween_property(marker, "transparency", 1.0, duration).from(0.0)
	tween.chain().tween_callback(marker.queue_free)


func _spawn_lock_flash(position: Vector3, radius: float) -> void:
	var marker := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.06
	mesh.radial_segments = 48
	mesh.material = _effect_material(Color(1.0, 0.015, 0.01, 0.88), 7.0)
	marker.mesh = mesh
	_effect_root().add_child(marker)
	marker.global_position = Vector3(position.x, 0.58, position.z)
	var tween := marker.create_tween()
	tween.set_parallel(true)
	tween.tween_property(marker, "scale", Vector3(1.12, 1.0, 1.12), 0.18).from(Vector3.ONE * 0.78)
	tween.tween_property(marker, "transparency", 1.0, 0.18).from(0.0)
	tween.chain().tween_callback(marker.queue_free)


func _spawn_pulse_sphere(position: Vector3, radius: float, color: Color, duration: float) -> void:
	var marker := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 20
	mesh.rings = 12
	mesh.material = _effect_material(color, 3.0)
	marker.mesh = mesh
	_effect_root().add_child(marker)
	marker.global_position = position
	var tween := marker.create_tween()
	tween.set_parallel(true)
	tween.tween_property(marker, "scale", Vector3.ONE, duration).from(Vector3.ONE * 0.18)
	tween.tween_property(marker, "transparency", 1.0, duration).from(0.15)
	tween.chain().tween_callback(marker.queue_free)


func _spawn_line_effect(from: Vector3, to: Vector3, radius: float, color: Color, duration: float) -> void:
	var delta := to - from
	if delta.length_squared() < 0.01:
		return
	var marker := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.55
	mesh.bottom_radius = radius
	mesh.height = delta.length()
	mesh.radial_segments = 9
	mesh.material = _effect_material(color, 4.0)
	marker.mesh = mesh
	_effect_root().add_child(marker)
	marker.global_position = (from + to) * 0.5
	var up := delta.normalized()
	var right := up.cross(Vector3.FORWARD).normalized()
	if right.length_squared() < 0.01:
		right = up.cross(Vector3.RIGHT).normalized()
	marker.global_basis = Basis(right, up, right.cross(up).normalized()).orthonormalized()
	var tween := marker.create_tween()
	tween.tween_property(marker, "transparency", 1.0, duration).from(0.0)
	tween.tween_callback(marker.queue_free)


func _spawn_sweep_effect(position: Vector3, duration: float) -> void:
	var marker := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.86
	mesh.outer_radius = 1.0
	mesh.rings = 32
	mesh.ring_segments = 8
	mesh.material = _effect_material(Color(0.85, 0.02, 0.07, 0.82), 5.0)
	marker.mesh = mesh
	_effect_root().add_child(marker)
	marker.global_position = Vector3(position.x, 0.62, position.z)
	var tween := marker.create_tween()
	tween.set_parallel(true)
	tween.tween_property(marker, "scale", Vector3(9.0, 1.0, 9.0), duration).from(Vector3.ONE)
	tween.tween_property(marker, "transparency", 1.0, duration).from(0.0)
	tween.chain().tween_callback(marker.queue_free)


func _effect_material(color: Color, emission_strength: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = emission_strength
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _spawn_projectile(position: Vector3, initial_velocity: Vector3) -> void:
	var projectile := PhysicalProjectile.new()
	projectile.damage = shrapnel_damage
	projectile.velocity = initial_velocity
	_effect_root().add_child(projectile)
	projectile.global_position = position


func _spawn_shrapnel_volley(monster_position: Vector3, target_position: Vector3) -> void:
	# Most shards use a ballistic solution around the player's telegraphed position;
	# the remainder seed nearby floor hazards and keep the volley visually irregular.
	for index in 10:
		var spread := 0.4 if index < 3 else 2.6
		var target_offset := Vector3(randf_range(-spread, spread), randf_range(-0.15, 0.6), randf_range(-spread, spread))
		var velocity_value := _ballistic_velocity(monster_position, target_position + target_offset, randf_range(13.0, 17.0))
		_spawn_projectile(monster_position + velocity_value.normalized() * 2.8, velocity_value)
	for index in 4:
		var hazard_direction := Vector3(randf_range(-0.7, 0.7), randf_range(-1.0, -0.25), randf_range(-0.7, 0.7)).normalized()
		_spawn_projectile(monster_position + hazard_direction * 2.8, hazard_direction * randf_range(9.0, 13.0))


func _ballistic_velocity(origin: Vector3, target: Vector3, horizontal_speed: float) -> Vector3:
	var delta := target - origin
	var horizontal_distance := Vector2(delta.x, delta.z).length()
	var flight_time := clampf(horizontal_distance / maxf(horizontal_speed, 0.01), 0.45, 1.8)
	return Vector3(
		delta.x / flight_time,
		delta.y / flight_time + 0.5 * 18.0 * flight_time,
		delta.z / flight_time
	)


func _spawn_eye_swarm(position: Vector3) -> void:
	var available_slots := maxi(eye_swarm_limit - get_tree().get_node_count_in_group("eye_swarm"), 0)
	var spawn_count := mini(eye_swarm_spawn_count, available_slots)
	for index in spawn_count:
		var eye := SWARM_EYE_SCENE.instantiate() as CharacterBody3D
		_effect_root().add_child(eye)
		var angle := TAU * float(index) / maxf(float(spawn_count), 1.0)
		var offset := Vector3(cos(angle), randf_range(-0.8, 1.3), sin(angle)) * randf_range(1.8, 3.2)
		eye.global_position = position + offset


func _on_eye_attack_slot_requested(member_id: int) -> void:
	if _active_eye_attackers.has(member_id) or _pending_eye_attackers.has(member_id):
		return
	_pending_eye_attackers.append(member_id)
	_grant_pending_eye_slots()


func _on_eye_attack_slot_released(member_id: int) -> void:
	_active_eye_attackers.erase(member_id)
	_grant_pending_eye_slots()


func _on_eye_member_removed(member_id: int) -> void:
	_active_eye_attackers.erase(member_id)
	_pending_eye_attackers.erase(member_id)
	_grant_pending_eye_slots()


func _grant_pending_eye_slots() -> void:
	while _active_eye_attackers.size() < eye_swarm_attack_slots and not _pending_eye_attackers.is_empty():
		var member_id: int = _pending_eye_attackers.pop_front()
		_active_eye_attackers[member_id] = true
		SignalBus.eye_swarm_attack_slot_granted.emit(member_id)


func _effect_root() -> Node3D:
	if is_instance_valid(_arena_root):
		return _arena_root
	return get_parent().get_parent() as Node3D


func _on_player_position(position: Vector3) -> void:
	player_position = position


func _on_monster_state_changed(new_state: GameManager.MonsterState) -> void:
	if new_state == GameManager.MonsterState.COLLAPSED:
		set_attack_enabled(false)
		return
	var changed := new_state != _encounter_state
	_encounter_state = new_state
	_state_profile = _profile_for_state(new_state)
	set_attack_enabled(true)
	if changed:
		cancel_attack()
		_cooldown = phase_change_delay
