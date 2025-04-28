class_name MessageState

extends State

func _init() -> void:
	table_name = "message"
	query = "SELECT * FROM message"
	super._init()
