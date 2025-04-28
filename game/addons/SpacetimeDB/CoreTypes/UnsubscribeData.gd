extends Resource
class_name UnsubscribeData

## The request ID of the single subscription to unsubscribe from.
@export var request_id: int # u32

func _init(p_request_id: int = 0):
	request_id = p_request_id
	set_meta("bsatn_type_request_id", "u32")
	pass
