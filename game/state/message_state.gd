class_name MessageState

extends State

func _init() -> void:
	table_name = "message"
	query = "SELECT * FROM message WHERE Sent > '%s.000000+00:00'" % Time.get_datetime_string_from_system(true)
	super._init()
