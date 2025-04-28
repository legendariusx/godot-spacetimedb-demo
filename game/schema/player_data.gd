class_name PlayerData

extends Resource

@export var player: PackedByteArray
@export var position: Vector3
@export var rotation: Vector3
@export var car_type: String
@export var is_active: bool

func _init():
	set_meta("table_name", "player_data")
	set_meta("primary_key", "player")
	set_meta("bsatn_type_player", "identity")
