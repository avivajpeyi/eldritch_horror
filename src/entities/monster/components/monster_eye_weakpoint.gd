extends AnimatableBody3D
## Routes eye impacts through SignalBus; MonsterCore decides vulnerability.


func _ready() -> void:
	add_to_group("EnemiesHead")


func hitscan_hit(damage: float, _direction: Vector3, _hit_position: Vector3) -> void:
	SignalBus.monster_eye_hit.emit(damage, GameManager.ElementType.KINETIC)


func hitscan_hit_typed(damage: float, damage_type: int, _direction: Vector3, _hit_position: Vector3) -> void:
	SignalBus.monster_eye_hit.emit(damage, damage_type)


func projectile_hit(damage: float, _direction: Vector3) -> void:
	SignalBus.monster_eye_hit.emit(damage, GameManager.ElementType.KINETIC)


func projectile_hit_typed(damage: float, damage_type: int, _direction: Vector3) -> void:
	SignalBus.monster_eye_hit.emit(damage, damage_type)
