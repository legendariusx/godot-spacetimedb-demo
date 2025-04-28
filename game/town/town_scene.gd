extends Node3D

@onready var car_container: Node3D = $CarContainer
@onready var minivan_scene: PackedScene = preload("res://vehicles/car_base.tscn")
@onready var trailer_truck_scene: PackedScene = preload("res://vehicles/trailer_truck.tscn")
@onready var tow_truck_scene: PackedScene = preload("res://vehicles/tow_truck.tscn")
@onready var player_data_state: PlayerDataState = preload("res://state/player_data_state.gd").new()

func _ready() -> void:
	add_child(player_data_state)
	player_data_state.update.connect(_on_player_data_update)
	UserState.update.connect(_on_user_update)
	get_window().focus_entered.connect(_on_window_focus_entered)
	get_window().focus_exited.connect(_on_window_focus_exited)

func _exit_tree() -> void:
	player_data_state.reset()
			
func _on_window_focus_entered():
	var tween = get_tree().create_tween()
	tween.tween_callback(AudioServer.set_bus_mute.bind(0, false))
	tween.tween_method(func(v): AudioServer.set_bus_volume_db(0, v), -80, 0, 0.5)
	
func _on_window_focus_exited():
	var tween = get_tree().create_tween()
	tween.tween_method(func(v): AudioServer.set_bus_volume_db(0, v), 0, -80, 0.5)
	tween.tween_callback(AudioServer.set_bus_mute.bind(0, true))

func create_new_vehicle(user: User, data: PlayerData):
	var new_vehicle := get_vehicle_scene(data.car_type).instantiate()
	var body = new_vehicle.get_node("Body")
	body.set_owner_data(user.identity, user.identity == SpacetimeDB.get_local_identity().identity, user.name)
	car_container.add_child(new_vehicle)
	new_vehicle.global_position = data.position
	new_vehicle.global_rotation = data.rotation

func remove_vehicle(node: Node3D):
	car_container.remove_child(node)
	node.queue_free()

func get_vehicle_scene(car_type: String) -> PackedScene:
	if car_type == "MINIVAN":
		return minivan_scene
	if car_type == "TRAILER_TRUCK":
		return trailer_truck_scene
	if car_type == "TOW_TRUCK":
		return tow_truck_scene
	return minivan_scene

func _on_player_data_update(player_data: PlayerData):
	if player_data.player == GameState.identity: return
	var user := UserState.find_by_pk(State.get_pk_val(player_data)) as User
	if not user or not user.online: return
	
	var cars = car_container.get_children().filter(func(car): return not not car)
	var car_index = cars.find_custom(func(car): return car and car.get_node("Body").owner_identity == player_data.player)
	if car_index == -1:
		if player_data.is_active:
			create_new_vehicle(user, player_data)
	elif not player_data.is_active:
		remove_vehicle(cars[car_index])
	elif cars[car_index].get_node("Body").car_type != player_data.car_type:
		remove_vehicle(cars[car_index])
		create_new_vehicle(user, player_data)
	else:
		cars[car_index].get_node("Body").global_position = player_data.position
		cars[car_index].get_node("Body").global_rotation = player_data.rotation

func _on_user_update(user: User):
	var cars := car_container.get_children()
	var car_index := cars.find_custom(func(car): return car.get_node("Body").owner_identity == user.identity)
	if car_index == -1: return
	
	if user.online:
		cars[car_index].get_node("Body").set_owner_name(user.name)
	else:
		remove_vehicle(cars[car_index])
