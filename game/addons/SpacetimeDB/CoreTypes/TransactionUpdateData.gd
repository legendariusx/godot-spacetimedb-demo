extends Resource
class_name TransactionUpdateData

@export var status: UpdateStatusData
@export var timestamp_ns: int # i64 (Timestamp)
@export var caller_identity: PackedByteArray # 32 bytes
@export var caller_connection_id: PackedByteArray # 16 bytes
@export var reducer_call: ReducerCallInfoData
@export var energy_quanta_used: int # u64
@export var total_host_execution_duration_ns: int # i64 (TimeDuration)
