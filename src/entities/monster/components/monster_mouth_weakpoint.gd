class_name MonsterMouthWeakpoint
extends AnimatableBody3D
## Collision and hit routing for the throat weakpoint. Vulnerability is driven by
## public attack phases; MonsterCore remains the sole owner of boss health.

@export var required_element: GameManager.ElementType = GameManager.ElementType.BLUE
@export var vulnerable_attacks: Array[StringName] = [&"Fleshy Shrapnel", &"Eye Swarm"]

@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var is_open := false


func _ready() -> void:
	add_to_group("EnemiesHead")
	collision_shape.set_deferred("disabled", true)
	SignalBus.attack_phase_changed.connect(_on_attack_phase_changed)


func _exit_tree() -> void:
	if SignalBus.attack_phase_changed.is_connected(_on_attack_phase_changed):
		SignalBus.attack_phase_changed.disconnect(_on_attack_phase_changed)


func hitscan_hit(damage: float, _direction: Vector3, _hit_position: Vector3) -> void:
	_report_hit(damage, GameManager.ElementType.KINETIC)


func hitscan_hit_typed(damage: float, damage_type: int, _direction: Vector3, _hit_position: Vector3) -> void:
	_report_hit(damage, damage_type)


func projectile_hit(damage: float, _direction: Vector3) -> void:
	_report_hit(damage, GameManager.ElementType.KINETIC)


func projectile_hit_typed(damage: float, damage_type: int, _direction: Vector3) -> void:
	_report_hit(damage, damage_type)


func _report_hit(damage: float, damage_type: int) -> void:
	if is_open and damage > 0.0:
		SignalBus.monster_mouth_hit.emit(damage, damage_type)


func _on_attack_phase_changed(attack_name: StringName, phase_name: StringName, _duration: float) -> void:
	var next_open := attack_name in vulnerable_attacks and phase_name in [&"TELEGRAPH", &"ACTIVE"]
	if next_open == is_open:
		return
	is_open = next_open
	collision_shape.set_deferred("disabled", not is_open)
	SignalBus.monster_mouth_exposure_changed.emit(is_open, required_element)
