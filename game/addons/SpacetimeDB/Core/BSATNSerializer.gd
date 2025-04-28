# bsatn_serializer.gd
class_name BSATNSerializer extends RefCounted

# --- Constants ---
# Re-use constants from parser if they are in a shared location, otherwise redefine
const IDENTITY_SIZE := 32
const CONNECTION_ID_SIZE := 16

const CLIENT_MSG_VARIANT_TAG_CALL_REDUCER  := 0x00
const CLIENT_MSG_VARIANT_TAG_SUBSCRIBE     := 0x01
const CLIENT_MSG_VARIANT_TAG_ONEOFF_QUERY  := 0x02
const CLIENT_MSG_VARIANT_TAG_SUBSCRIBE_SINGLE := 0x03
const CLIENT_MSG_VARIANT_TAG_SUBSCRIBE_MULTI  := 0x04
const CLIENT_MSG_VARIANT_TAG_UNSUBSCRIBE   := 0x05
const CLIENT_MSG_VARIANT_TAG_UNSUBSCRIBE_MULTI := 0x06
# Max string/vector length checks are less critical on serialization
# unless you need to enforce outgoing limits.

# --- Properties ---
var _last_error: String = ""
var _spb: StreamPeerBuffer # Internal buffer for writing

# Maps Variant.Type to specialized property writer methods
var _property_writers: Dictionary = {}

# --- Initialization ---

func _init() -> void:
	_initialize_property_writers()
	_spb = StreamPeerBuffer.new()
	_spb.big_endian = false # Default to Little-Endian for all writes

# Initialize the dictionary mapping Variant types to their writer functions.
func _initialize_property_writers() -> void:
	_property_writers = {
		TYPE_PACKED_BYTE_ARRAY: Callable(self, "_write_property_packed_byte_array"),
		TYPE_INT: Callable(self, "_write_property_int"),
		TYPE_FLOAT: Callable(self, "_write_property_float"),
		TYPE_STRING: Callable(self, "_write_property_string"),
		TYPE_BOOL: Callable(self, "_write_property_bool"),
		TYPE_VECTOR3: Callable(self, "_write_property_vector3"),
		TYPE_VECTOR2: Callable(self, "_write_property_vector2"),
		TYPE_COLOR: Callable(self, "_write_property_color"),
		TYPE_QUATERNION: Callable(self, "_write_property_quaternion"), # Example for new type
		TYPE_ARRAY: Callable(self, "_write_property_array"),
		# Add other supported types here
	}


# --- Error Handling ---

func has_error() -> bool:
	return _last_error != ""

func get_last_error() -> String:
	var err := _last_error
	_last_error = "" # Clear error after getting
	return err

func clear_error() -> void:
	_last_error = ""
	
# Sets the error message if not already set. Internal use.
func _set_error(msg: String) -> void:
	if _last_error == "": # Prevent overwriting the first error
		_last_error = "BSATNSerializer Error: %s" % msg
		printerr(_last_error) # Always print errors

# --- Primitive Value Writers ---
# Write basic BSATN types to the internal StreamPeerBuffer.

func write_i8(value: int) -> void:
	if value < -128 or value > 127:
		_set_error("Value %d out of range for i8" % value)
		value = 0 # Write default on error? Or stop?
	# Convert to u8 range
	var uval = value if value >= 0 else value + 256
	_spb.put_u8(uval)

func write_i16_le(value: int) -> void:
	if value < -32768 or value > 32767:
		_set_error("Value %d out of range for i16" % value)
		value = 0
	var uval = value if value >= 0 else value + 65536
	_spb.put_u16(uval)

func write_i32_le(value: int) -> void:
	# Note: GDScript 'int' is 64-bit, direct check is fine
	if value < -2147483648 or value > 2147483647:
		_set_error("Value %d out of range for i32" % value)
		value = 0
	# StreamPeerBuffer handles the two's complement conversion correctly for put_u32
	# when the input is negative within the i32 range.
	_spb.put_u32(value)

func write_i64_le(value: int) -> void:
	# GDScript int is i64, direct write
	_spb.put_u64(value) # put_u64 handles negative numbers correctly

func write_u8(value: int) -> void:
	if value < 0 or value > 255:
		_set_error("Value %d out of range for u8" % value)
		value = 0
	_spb.put_u8(value)

func write_u16_le(value: int) -> void:
	if value < 0 or value > 65535:
		_set_error("Value %d out of range for u16" % value)
		value = 0
	_spb.put_u16(value)

func write_u32_le(value: int) -> void:
	# Use u64 range check as GDScript int is 64-bit
	if value < 0 or value > 4294967295:
		_set_error("Value %d out of range for u32" % value)
		value = 0
	_spb.put_u32(value)

func write_u64_le(value: int) -> void:
	if value < 0: # Cannot represent negative in u64 correctly from i64 without conversion
		_set_error("Value %d out of range for u64" % value)
		value = 0
	_spb.put_u64(value)

func write_f32_le(value: float) -> void:
	_spb.put_float(value)

func write_f64_le(value: float) -> void:
	_spb.put_double(value)

func write_bool(value: bool) -> void:
	_spb.put_u8(1 if value else 0)

func write_bytes(value: PackedByteArray) -> void:
	var result = _spb.put_data(value)
	if result != OK:
		_set_error("StreamPeerBuffer.put_data failed with code %d" % result)

func write_string_with_u32_len(value: String) -> void:
	if value == null: # Handle null string case? Assume empty.
		push_warning("Attempted to serialize null string, writing as empty.")
		value = ""

	var str_bytes := value.to_utf8_buffer()
	var length := str_bytes.size()
	# Add length limit check if necessary
	# if length > MAX_STRING_LEN: ...

	write_u32_le(length)
	if length > 0:
		write_bytes(str_bytes)

func write_identity(value: PackedByteArray) -> void:
	if value == null or value.size() != IDENTITY_SIZE:
		_set_error("Invalid Identity value (null or size != %d)" % IDENTITY_SIZE)
		# Write default/empty identity?
		write_bytes(PackedByteArray()) # Write empty bytes or handle error differently
		return
	write_bytes(value)

func write_timestamp(value: int) -> void:
	# Timestamp is i64
	write_i64_le(value)

# --- Vector/Array Writer ---

# Writes a vector (dynamic array) using a provided writer function for the elements.
func write_vec(array_value: Array, element_writer_func: Callable) -> void:
	if array_value == null:
		push_warning("Attempted to serialize null array, writing as empty vector.")
		write_u32_le(0) # Write zero length
		return

	var length := array_value.size()
	# Add length limit check if necessary
	# if length > MAX_VEC_LEN: ...

	write_u32_le(length)

	for element in array_value:
		# Check for errors before writing each element
		if has_error(): return # Stop writing if previous step failed
		# Call the specific writer for the element type
		element_writer_func.call(element) # Pass only the value

# --- Main Serialization Logic ---

# Serializes a single Resource instance into a PackedByteArray.
func serialize_resource(resource: Resource) -> PackedByteArray:
	_last_error = "" # Clear previous errors
	_spb.data_array = PackedByteArray() # Reset buffer
	_spb.seek(0)

	if not resource or not resource.get_script():
		_set_error("Cannot serialize null or scriptless resource")
		return PackedByteArray()

	var properties: Array = resource.get_script().get_script_property_list()

	for prop in properties:
		if not (prop.usage & PROPERTY_USAGE_STORAGE):
			continue # Skip non-serialized properties

		var prop_name: StringName = prop.name
		var prop_type: Variant.Type = prop.type
		var value = resource.get(prop_name) # Get current value from resource

		# 1. Get the appropriate writer function
		var writer_callable: Callable = _get_property_writer(resource, prop)

		if not writer_callable.is_valid():
			# Error already set by _get_property_writer
			return PackedByteArray() # Stop serialization on unsupported type

		# 2. Call the writer function with the value
		#    Array writer needs the array value directly.
		#    Others need the value passed.
		if prop_type == TYPE_ARRAY:
			writer_callable.call(value, resource, prop) # Pass value and context
		else:
			writer_callable.call(value) # Pass only the value

		# 3. Check for errors after attempting to write
		if has_error():
			# Error should have been set by the writer function
			# Add context if missing
			if not _last_error.contains(str(prop_name)):
				_set_error("Failed writing value for property '%s'. Cause: %s" % [prop_name, get_last_error()])
			return PackedByteArray() # Stop serialization

	# Return the accumulated bytes
	return _spb.data_array

# Helper to determine the correct writer function for a property.
func _get_property_writer(resource: Resource, prop: Dictionary) -> Callable:
	var prop_name: StringName = prop.name
	var prop_type: Variant.Type = prop.type

	# 1. Check for specific BSATN type override via metadata
	var meta_key := "bsatn_type_" + prop_name
	var specific_writer_callable: Callable = _get_specific_bsatn_writer(resource, meta_key)

	if specific_writer_callable.is_valid():
		return specific_writer_callable

	# 2. Fallback to default writer based on property type
	if _property_writers.has(prop_type):
		return _property_writers[prop_type]
	else:
		_set_error("Unsupported property type '%s' for BSATN serialization of property '%s' in resource '%s'" % [type_string(prop_type), prop_name, resource.resource_path])
		return Callable() # Return invalid Callable

# Helper to get a specific writer based on "bsatn_type_" metadata.
func _get_specific_bsatn_writer(resource: Resource, meta_key: String) -> Callable:
	if resource.has_meta(meta_key):
		var bsatn_type_str: String = resource.get_meta(meta_key).to_lower()
		match bsatn_type_str:
			"u64": return Callable(self, "write_u64_le")
			"i64": return Callable(self, "write_i64_le")
			"u32": return Callable(self, "write_u32_le")
			"i32": return Callable(self, "write_i32_le")
			"u16": return Callable(self, "write_u16_le")
			"i16": return Callable(self, "write_i16_le")
			"u8": return Callable(self, "write_u8")
			"i8": return Callable(self, "write_i8")
			"identity": return Callable(self, "write_identity")
			"timestamp": return Callable(self, "write_timestamp")
			"f64": return Callable(self, "write_f64_le") # Handle float override
			# Add other specific types if needed
			_:
				push_warning("Unknown 'bsatn_type' metadata value for serialization: '%s'" % bsatn_type_str)
	return Callable() # Return invalid Callable if no specific writer found


# --- Property Type Writers (Called by serialize_resource) ---
# Write specific Variant types to the internal buffer (_spb).

func _write_property_packed_byte_array(value: PackedByteArray) -> void:
	# Note: This function is called ONLY if specific metadata (like 'identity')
	# was NOT found by _get_property_writer -> _get_specific_bsatn_writer.
	# Therefore, we implement the default behavior here, which is length-prefixed bytes.

	if value == null:
		push_warning("Serializing null PackedByteArray property as empty Vec<u8>.")
		value = PackedByteArray()

	# Default behavior: Write as Vec<u8> (u32 length + bytes)
	write_u32_le(value.size())
	write_bytes(value)

func _write_property_int(value: int) -> void:
	# Default integer type is i64. Metadata handles overrides.
	write_i64_le(value)

func _write_property_float(value: float) -> void:
	# Default float is f32. Metadata handles f64 override.
	write_f32_le(value)

func _write_property_string(value: String) -> void:
	write_string_with_u32_len(value)

func _write_property_bool(value: bool) -> void:
	write_bool(value)

func _write_property_vector3(value: Vector3) -> void:
	if value == null: value = Vector3.ZERO # Handle potential null?
	write_f32_le(value.x)
	write_f32_le(value.y)
	write_f32_le(value.z)

func _write_property_vector2(value: Vector2) -> void:
	if value == null: value = Vector2.ZERO
	write_f32_le(value.x)
	write_f32_le(value.y)

func _write_property_color(value: Color) -> void:
	if value == null: value = Color.BLACK
	write_f32_le(value.r)
	write_f32_le(value.g)
	write_f32_le(value.b)
	write_f32_le(value.a)

func _write_property_quaternion(value: Quaternion) -> void: # Example for new type
	if value == null: value = Quaternion.IDENTITY
	write_f32_le(value.x)
	write_f32_le(value.y)
	write_f32_le(value.z)
	write_f32_le(value.w)

# Handles writing arrays by finding the element writer and calling write_vec
func _write_property_array(array_value: Array, resource: Resource, prop: Dictionary) -> void:
	# Determine the element writer function based on hint_string or metadata
	var element_writer_func: Callable = _get_array_element_writer(resource, prop)

	if not element_writer_func.is_valid():
		# Error is set by _get_array_element_writer
		return # Stop serialization for this property/resource

	# Write the vector using the determined element writer
	write_vec(array_value, element_writer_func)


# Helper to determine the correct writer function for array elements.
func _get_array_element_writer(resource: Resource, prop: Dictionary) -> Callable:
	var prop_name: StringName = prop.name
	var hint: int = prop.hint
	var hint_string: String = prop.hint_string

	if hint != PROPERTY_HINT_TYPE_STRING or ":" not in hint_string:
		_set_error("Array property '%s' requires a typed hint (e.g., Array[String], Array[Vector3]) for serialization." % prop_name)
		return Callable()

	var hint_parts := hint_string.split(":", true, 1)
	if hint_parts.size() != 2:
		_set_error("Could not parse hint_string '%s' for array property '%s'" % [hint_string, prop_name])
		return Callable()

	var element_type_code: int = int(hint_parts[0])

	# Check for specific element type override first (e.g., for int/float subtypes)
	var element_meta_key := "bsatn_vec_element_type_" + prop_name
	var specific_element_writer := _get_specific_bsatn_writer(resource, element_meta_key)
	if specific_element_writer.is_valid():
		return specific_element_writer

	# Fallback to writer based on the element's Variant.Type from hint_string
	match element_type_code:
		TYPE_STRING: return Callable(self, "_write_string_element")
		TYPE_INT:
			push_warning("No 'bsatn_vec_element_type_%s' metadata found for Array[int] serialization. Assuming element BSATN type 'i64'." % prop_name)
			return Callable(self, "_write_i64_element")
		TYPE_FLOAT:
			# Default to f32. Add check for f64 metadata if needed.
			return Callable(self, "_write_f32_element")
		TYPE_BOOL: return Callable(self, "_write_bool_element")
		TYPE_VECTOR3: return Callable(self, "_write_vector3_element")
		TYPE_VECTOR2: return Callable(self, "_write_vector2_element")
		TYPE_COLOR: return Callable(self, "_write_color_element")
		TYPE_QUATERNION: return Callable(self, "_write_quaternion_element") # Example
		TYPE_PACKED_BYTE_ARRAY:
			# Need metadata (e.g., 'identity') - already checked above
			_set_error("Cannot serialize Array[PackedByteArray] element type for '%s'. Specify element type via '%s' metadata." % [prop_name, element_meta_key])
			return Callable()
		_:
			_set_error("Unsupported element type code '%d' for array serialization of property '%s'" % [element_type_code, prop_name])
			return Callable()


# --- Helper Element Writers (for write_vec) ---
# Simple wrappers calling the main primitive/complex writers.
# These methods now only take the value to be written.

func _write_string_element(value: String) -> void: write_string_with_u32_len(value)
func _write_i64_element(value: int) -> void: write_i64_le(value)
func _write_f32_element(value: float) -> void: write_f32_le(value)
func _write_bool_element(value: bool) -> void: write_bool(value)
func _write_vector3_element(value: Vector3) -> void: _write_property_vector3(value)
func _write_vector2_element(value: Vector2) -> void: _write_property_vector2(value)
func _write_color_element(value: Color) -> void: _write_property_color(value)
func _write_quaternion_element(value: Quaternion) -> void: _write_property_quaternion(value) # Example
func _write_identity_element(value: PackedByteArray) -> void: write_identity(value)
# Add other element writers as needed (u8, i32, etc.)

func serialize_client_message(variant_tag: int, payload_resource: Resource) -> PackedByteArray:
	clear_error() # Start clean for this message
	_spb.data_array = PackedByteArray() # Reset main buffer
	_spb.seek(0)

	# 1. Write the SumType variant tag
	write_u8(variant_tag)
	if has_error(): return PackedByteArray()

	# 2. Serialize the payload resource fields *into the current buffer*
	if not _serialize_resource_fields(payload_resource):
		# Error should be set by _serialize_resource_fields
		if not has_error(): # Ensure error is set if helper somehow didn't
			_set_error("Failed to serialize payload resource for tag %d" % variant_tag)
		return PackedByteArray()

	if has_error(): # Double check after serialization
		return PackedByteArray()

	return _spb.data_array

# Serializes the fields of a Resource instance into the *current* _spb.
# Does NOT write a message tag or clear the buffer beforehand.
# Returns true on success, false on failure.
func _serialize_resource_fields(resource: Resource) -> bool:
	# DO NOT clear error or reset _spb here.

	if not resource or not resource.get_script():
		_set_error("Cannot serialize fields of null or scriptless resource")
		return false

	var properties: Array = resource.get_script().get_script_property_list()

	for prop in properties:
		if not (prop.usage & PROPERTY_USAGE_STORAGE):
			continue # Skip non-serialized properties

		var prop_name: StringName = prop.name
		var prop_type: Variant.Type = prop.type
		var value = resource.get(prop_name) # Get current value from resource

		# 1. Get the appropriate writer function
		var writer_callable: Callable = _get_property_writer(resource, prop)

		if not writer_callable.is_valid():
			# Error already set by _get_property_writer
			return false # Stop serialization on unsupported type

		# 2. Call the writer function with the value
		#    Need to handle how arguments are passed to writers consistently
		#    Let's assume writers called via this path only need the value.
		#    Array writer (_write_property_array) needs special handling if called from here.
		#    It might be simpler to have _write_property_array ONLY take the value,
		#    and resolve its element writer internally or assume it's pre-resolved?
		#    Let's stick to the current _write_property_array signature for now,
		#    but it's not used directly when serializing resource fields here.
		#    TODO: Review if _write_property_array needs adjustment if resource fields can be arrays.

		if prop_type == TYPE_ARRAY:
			# How should arrays be written when they are fields of a resource payload?
			# We need the element writer. We can reuse the logic from _write_property_array
			var element_writer_func: Callable = _get_array_element_writer(resource, prop)
			if not element_writer_func.is_valid():
				return false # Error set by getter
			write_vec(value, element_writer_func) # Call write_vec directly
		elif writer_callable.is_valid():
			# For non-array types, call the simple writer
			writer_callable.call(value)
		else:
			# This case should ideally not be reached if _get_property_writer works correctly
			_set_error("Internal error: No writer found for property '%s' type %s" % [prop_name, type_string(prop_type)])
			return false


		# 3. Check for errors after attempting to write
		if has_error():
			# Error should have been set by the writer function
			# Add context if missing
			if not _last_error.contains(str(prop_name)):
				_set_error("Failed writing value for property '%s'. Cause: %s" % [prop_name, get_last_error()])
			return false # Stop serialization

	return true # Success
# Serializes a reducer call into the standard ClientMessage format.
# Matches the C# CallReducer structure for field order AFTER the variant tag.
func serialize_reducer_call(reducer_name: String, args_array: Array, request_id: int, flags: int) -> PackedByteArray:
	clear_error() # Start clean for this operation

	# 1. Serialize arguments into a single byte block first
	var args_bytes := _serialize_arguments(args_array)
	if has_error(): # Check if argument serialization failed
		return PackedByteArray()

	# 2. Serialize the final message using the main buffer
	_spb.data_array = PackedByteArray() # Clear main buffer
	_spb.seek(0)

	# --- Write the ClientMessage structure for CallReducer ---
	# a) Write the overall message type tag (discriminant for the SumType)
	write_u8(CLIENT_MSG_VARIANT_TAG_CALL_REDUCER)
	# b) Write the fields corresponding to the CallReducer structure itself
	write_string_with_u32_len(reducer_name) # Reducer (string)
	write_u32_le(args_bytes.size())           # Length prefix for Args (List<byte> -> Vec<u8>)
	write_bytes(args_bytes)                 # Args bytes
	write_u32_le(request_id)                # RequestId (uint -> u32)
	write_u8(flags)                         # Flags (byte -> u8)
	# --- End of CallReducer structure ---

	if has_error(): # Check for errors during final message assembly
		return PackedByteArray()

	return _spb.data_array

	
# Internal helper to serialize an array of arguments into a single PackedByteArray block.
# Used to prepare the 'args' field for CallReducerData.
# Returns the bytes, or empty PackedByteArray on error (and sets error).
func _serialize_arguments(args_array: Array) -> PackedByteArray:
	var args_spb := StreamPeerBuffer.new() # Temporary buffer for args
	args_spb.big_endian = false

	var original_main_spb := _spb # Store the main buffer reference
	_spb = args_spb             # Temporarily redirect primitive writes to args_spb

	# --- Serialization Loop ---
	for i in range(args_array.size()):
		var arg_value = args_array[i]
		if not _write_argument(arg_value): # Write argument to the *current* _spb (which is args_spb)
			push_error("Failed to serialize argument %d for reducer call." % i) # Add context
			_spb = original_main_spb # Restore original buffer before returning
			# _write_argument should have set _last_error
			return PackedByteArray()
	# --- End Loop ---

	_spb = original_main_spb # IMPORTANT: Restore the main buffer reference

	if has_error(): # Check if any error occurred during the loop
		return PackedByteArray()

	return args_spb.data_array # Return the bytes accumulated in the temp args buffer

# Internal helper to write a single argument value to the *current* _spb.
# Returns true on success, false on failure (and sets _last_error).
func _write_argument(value) -> bool:
	# ... (код без изменений) ...
	var value_type := typeof(value)
	var writer_callable: Callable

	match value_type:
		TYPE_NIL:
			_set_error("Cannot serialize null/nil argument directly.")
			return false
		TYPE_BOOL:
			writer_callable = Callable(self, "write_bool")
		TYPE_INT:
			writer_callable = Callable(self, "write_i64_le")
		TYPE_FLOAT:
			writer_callable = Callable(self, "write_f32_le")
		TYPE_STRING:
			writer_callable = Callable(self, "write_string_with_u32_len")
		TYPE_VECTOR2:
			writer_callable = Callable(self, "_write_property_vector2")
		TYPE_VECTOR3:
			writer_callable = Callable(self, "_write_property_vector3")
		TYPE_COLOR:
			writer_callable = Callable(self, "_write_property_color")
		TYPE_QUATERNION:
			writer_callable = Callable(self, "_write_property_quaternion")
		TYPE_PACKED_BYTE_ARRAY:
			if value.size() == IDENTITY_SIZE:
				writer_callable = Callable(self, "write_identity")
			else:
				writer_callable = Callable(self, "_write_length_prefixed_bytes")
		TYPE_ARRAY:
			_set_error("Cannot serialize Array as direct argument. Pass elements individually or wrap in a Resource.")
			return false
		TYPE_OBJECT:
			if value is Resource:
				var serializer_for_resource := BSATNSerializer.new()
				var resource_bytes := serializer_for_resource.serialize_resource(value)
				if serializer_for_resource.has_error():
					_set_error("Failed to serialize nested Resource argument. Cause: %s" % serializer_for_resource.get_last_error())
					return false
				write_u32_le(resource_bytes.size())
				write_bytes(resource_bytes)
				return not has_error()
			else:
				_set_error("Cannot serialize non-Resource Object argument of type %s." % value.get_class())
				return false
		_:
			_set_error("Unsupported argument type for serialization: %s" % type_string(value_type))
			return false

	if writer_callable.is_valid():
		writer_callable.call(value)
		return not has_error()
	else:
		_set_error("Internal error: No valid writer found for argument type %s" % type_string(value_type))
		return false
	
# Helper specifically for length-prefixed PackedByteArray arguments
func _write_length_prefixed_bytes(value: PackedByteArray) -> void:
	if value == null: value = PackedByteArray()
	write_u32_le(value.size())
	write_bytes(value)
