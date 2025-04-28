# addons/spacetimedb_client/SpacetimeDBConnection.gd
class_name SpacetimeDBConnection extends Node

var _websocket := WebSocketPeer.new()
var _target_url: String
var _token: String
var _is_connected := false
var _connection_requested := false
var _debug_mode := false
# Protocol constants
const BSATN_PROTOCOL = "v1.bsatn.spacetimedb"

enum CompressionPreference { NONE = 0, BROTLI = 1, GZIP = 2 }
var preferred_compression: CompressionPreference = CompressionPreference.NONE # Default to None

signal connected
signal disconnected
signal connection_error(code: int, reason: String)
signal message_received(data: PackedByteArray) # Always BSATN

func _init(compression:int, debug_mode:bool):
	preferred_compression = compression
	self._debug_mode = debug_mode
	set_process(false) # Don't process until connect is called
	
func print_log(log_message:String):
	if _debug_mode:
		print(log_message)
	pass;
	
func set_token(token: String):
	self._token = token

func set_compression_preference(preference: CompressionPreference):
	self.preferred_compression = preference

func connect_to_database(base_url: String, database_name: String, connection_id: String, compression:CompressionPreference): # Added connection_id
	if _is_connected or _connection_requested:
		print_log("SpacetimeDBConnection: Already connected or connecting.")
		return

	if _token.is_empty():
		print_log("SpacetimeDBConnection: Cannot connect without auth token.")
		return

	if connection_id.is_empty():
		printerr("SpacetimeDBConnection: Cannot connect without Connection ID.")
		return

	# Construct WebSocket URL base
	var ws_url_base := base_url.replace("http", "ws").replace("https", "wss")
	ws_url_base = ws_url_base.path_join("/v1/database").path_join(database_name).path_join("subscribe")

	# --- Add Query Parameters ---
	# Start with connection_id
	var query_params := "?connection_id=" + connection_id
	# Add compression preference
	# Convert enum value to string for the URL parameter
	var compression_str : String
	match preferred_compression:
		CompressionPreference.NONE: compression_str = "None" # Use string "None" as seen in C# enum
		CompressionPreference.BROTLI: compression_str = "Brotli"
		CompressionPreference.GZIP: compression_str = "Gzip"
		_: compression_str = "None" # Fallback

	query_params += "&compression=" + compression_str
	# Add light mode parameter if needed (based on C# code)
	# var light_mode = false # Example
	# if light_mode:
	#	 query_params += "&light=true"

	_target_url = ws_url_base + query_params

	print_log("SpacetimeDBConnection: Attempting to connect to: " + _target_url)

	var auth_header := "Authorization: Bearer " + _token
	# --- Remove Compression Header ---
	# _websocket.handshake_headers = [auth_header, compression_header] # OLD
	_websocket.handshake_headers = [auth_header] # ONLY Auth header needed now

	_websocket.supported_protocols = [BSATN_PROTOCOL]

	var err := _websocket.connect_to_url(_target_url)
	if err != OK:
		printerr("SpacetimeDBConnection: Error initiating connection: ", err)
		emit_signal("connection_error", err, "Failed to initiate connection")
	else:
		print_log("SpacetimeDBConnection: Connection initiated.")
		_connection_requested = true
		set_process(true)

func disconnect_from_server(code: int = 1000, reason: String = "Client initiated disconnect"):
	if _websocket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		print_log("SpacetimeDBConnection: Closing connection...")
		_websocket.close(code, reason)
	_is_connected = false
	_connection_requested = false
	set_process(false)

func is_connected_db() -> bool:
	return _is_connected

func send_bsatn_message(client_message_resource: Resource):
	if not _is_connected:
		printerr("SpacetimeDBConnection: Cannot send message, not connected.")
		return FAILED

	# TODO: Need a BSATN *Serializer* to convert the Resource back to bytes
	# For now, this function is a placeholder.
	printerr("SpacetimeDBConnection: BSATN Serialization not implemented yet!")
	return FAILED
	# var bsatn_parser = BSATNParser.new() # Or a dedicated serializer class
	# var bytes : PackedByteArray = bsatn_parser.serialize_client_message(client_message_resource)
	# if bsatn_parser.has_error():
	#	 printerr("SpacetimeDBConnection: Failed to serialize message: ", bsatn_parser.get_last_error())
	#	 return FAILED
	# var err = _websocket.send(bytes)
	# if err != OK:
	#	 printerr("SpacetimeDBConnection: Error sending BSATN message: ", err)
	#	 return err
	# return OK

func _process(delta: float) -> void:
	if _websocket == null: return

	_websocket.poll()
	var state := _websocket.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			if not _is_connected:
				print_log("SpacetimeDBConnection: Connection established.")
				_is_connected = true
				_connection_requested = false
				emit_signal("connected")

			# Process incoming packets
			while _websocket.get_available_packet_count() > 0:
				var packet_bytes := _websocket.get_packet()
				# We only support BSATN now
				emit_signal("message_received", packet_bytes)

		WebSocketPeer.STATE_CONNECTING:
			# Still trying to connect
			pass

		WebSocketPeer.STATE_CLOSING:
			# Connection is closing
			pass

		WebSocketPeer.STATE_CLOSED:
			var code := _websocket.get_close_code()
			var reason := _websocket.get_close_reason()
			if _is_connected or _connection_requested: # Only report if we were connected or trying
				if code == -1: # Abnormal closure
					printerr("SpacetimeDBConnection: Connection closed unexpectedly.")
					emit_signal("connection_error", code, "Abnormal closure")
				else:
					print_log("SpacetimeDBConnection: Connection closed (Code: %d, Reason: %s)" % [code, reason])
					emit_signal("disconnected") # Normal closure signal

			_is_connected = false
			_connection_requested = false
			set_process(false) # Stop polling
