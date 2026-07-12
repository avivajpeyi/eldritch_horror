extends PlayerCharacter

## Project adapter for the bundled FPS controller.
## Keeps gameplay systems decoupled by publishing player movement through SignalBus.
@export_category("Combat")
@export var max_health := 100.0
@export var damage_invulnerability := 0.35

var health := 0.0
var _invulnerability_timer := 0.0
var _defeated := false
var _last_ammo_in_magazine := -1
var _last_ammo_reserve := -1

@onready var weapon_manager: Node = $WeaponManager

func _ready() -> void:
	super._ready()
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	health = max_health
	SignalBus.player_damage_requested.connect(_on_damage_requested)
	call_deferred("_emit_initial_health")
	call_deferred("_publish_ammo_if_changed")

func _physics_process(delta: float) -> void:
	_invulnerability_timer = maxf(_invulnerability_timer - delta, 0.0)
	super._physics_process(delta)
	SignalBus.player_position_updated.emit(global_position)
	_publish_ammo_if_changed()

func _exit_tree() -> void:
	if SignalBus.player_damage_requested.is_connected(_on_damage_requested):
		SignalBus.player_damage_requested.disconnect(_on_damage_requested)

func take_damage(amount: float, source_position := Vector3.ZERO, impulse := Vector3.ZERO) -> void:
	if _defeated or _invulnerability_timer > 0.0 or amount <= 0.0:
		return
	health = clampf(health - amount, 0.0, max_health)
	_invulnerability_timer = damage_invulnerability
	var away := global_position - source_position
	if impulse.is_zero_approx() and away.length_squared() > 0.01:
		impulse = away.normalized() * 5.0 + Vector3.UP * 2.0
	velocity += impulse
	SignalBus.player_health_changed.emit(health, max_health)
	if health <= 0.0:
		_defeated = true
		SignalBus.player_defeated.emit()
		set_physics_process(false)

func _on_damage_requested(amount: float, source_position: Vector3, impulse: Vector3) -> void:
	take_damage(amount, source_position, impulse)


func _emit_initial_health() -> void:
	SignalBus.player_health_changed.emit(health, max_health)


## Adapts the bundled weapon's mutable magazine into a project-level event. The
## HUD never needs to know where the weapon scene lives or how it stores ammo.
func _publish_ammo_if_changed() -> void:
	if weapon_manager == null or weapon_manager.get("current_weapon") == null:
		return
	var weapon: Node = weapon_manager.get("current_weapon")
	var weapon_resource: Resource = weapon.get("resources")
	if weapon_resource == null:
		return
	var in_magazine: int = int(weapon_resource.get("total_ammo_in_mag"))
	var ammo_type: int = int(weapon_resource.get("ammo_type"))
	var ammo_manager: Node = weapon_manager.get("ammo_manager")
	if ammo_manager == null:
		return
	var ammo_values: Dictionary = ammo_manager.get("ammo_dict")
	var reserve: int = int(ammo_values.get(ammo_type, 0))
	if in_magazine == _last_ammo_in_magazine and reserve == _last_ammo_reserve:
		return
	_last_ammo_in_magazine = in_magazine
	_last_ammo_reserve = reserve
	SignalBus.player_ammo_changed.emit(in_magazine, reserve)
