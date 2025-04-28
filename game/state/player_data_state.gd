class_name PlayerDataState

extends State

func _init() -> void:
	table_name = "player_data"
	query = "SELECT * FROM player_data"
	super._init()
