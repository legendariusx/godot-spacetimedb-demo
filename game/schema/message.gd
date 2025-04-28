class_name Message

extends Resource

@export var id: int;
@export var sender: PackedByteArray;
@export var sent: int;
@export var text: String;

func _init() -> void:
	set_meta("table_name", "message")
	set_meta("primary_key", "id")
	set_meta("bsatn_type_sender", "identity")
	set_meta("bsatn_type_id", "i32")
	set_meta("bsatn_type_sent", "timestamp")
