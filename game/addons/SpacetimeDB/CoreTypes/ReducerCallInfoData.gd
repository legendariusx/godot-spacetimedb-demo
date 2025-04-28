extends Resource
class_name ReducerCallInfoData

@export var reducer_name: String
@export var reducer_id: int # u32
@export var args: PackedByteArray # Raw BSATN bytes for arguments
@export var request_id: int # u32
@export var execution_time: int

func _init(): 
	set_meta("primary_key", "identity")
