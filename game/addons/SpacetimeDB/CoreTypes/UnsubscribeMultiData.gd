extends Resource
class_name UnsubscribeMultiData

## The request ID of the multi-subscription to unsubscribe from.
@export var request_id: int # u32

func _init(p_request_id: int = 0):
	request_id = p_request_id
	# Add metadata for correct BSATN integer serialization
	set_meta("bsatn_type_request_id", "u32")
	pass
