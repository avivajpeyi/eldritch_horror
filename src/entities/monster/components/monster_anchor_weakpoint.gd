class_name MonsterAnchorWeakpoint
extends AnimatableBody3D
## Damage receiver only. MonsterCore owns anchor health and encounter rules.

@export var anchor_id: StringName


func _ready() -> void:
	add_to_group("Enemies")
	SignalBus.monster_anchor_state_changed.connect(_on_anchor_state_changed)


func _exit_tree() -> void:
	if SignalBus.monster_anchor_state_changed.is_connected(_on_anchor_state_changed):
		SignalBus.monster_anchor_state_changed.disconnect(_on_anchor_state_changed)


func hitscan_hit(damage: float, _direction: Vector3, _hit_position: Vector3) -> void:
	SignalBus.monster_anchor_hit.emit(anchor_id, damage, GameManager.ElementType.KINETIC)


func hitscan_hit_typed(damage: float, damage_type: int, _direction: Vector3, _hit_position: Vector3) -> void:
	SignalBus.monster_anchor_hit.emit(anchor_id, damage, damage_type)


func projectile_hit(damage: float, _direction: Vector3) -> void:
	SignalBus.monster_anchor_hit.emit(anchor_id, damage, GameManager.ElementType.KINETIC)


func projectile_hit_typed(damage: float, damage_type: int, _direction: Vector3) -> void:
	SignalBus.monster_anchor_hit.emit(anchor_id, damage, damage_type)


func _on_anchor_state_changed(changed_id: StringName, _element_type: int, _health: float, _maximum: float, broken: bool) -> void:
	if changed_id != anchor_id:
		return
	for child in get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", broken)
