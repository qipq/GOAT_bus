# ===== goat_bus/core/batch_processor.gd =====
extends RefCounted
class_name EventBatchProcessor

const VERSION := "4.2.0.69"
const MANIFEST := {
	"script_name": "EventBatchProcessor",
	"script_path": "res://goat_bus/core/batch_processor.gd",
	"class_name": "EventBatchProcessor",
	"version": "1.0.0",
	"description": "Batch event processing for GoatBus system",
	"required_dependencies": [],
	"optional_dependencies": [],
	"features": ["phase_batching", "integration_batching", "high_throughput_mode"],
	"api_version": "goatbus-v1.0.0",
	"last_updated": "2025-08-10"
}

# =============================================================================
# BATCH PROCESSOR
# =============================================================================

var _phase_batches: Dictionary = {}  # phase_name -> Array[EventData]
var _integration_batches: Dictionary = {}  # integration_type -> Array[EventData]
var _max_batch_size: int = 50
var _batch_timeout: float = 0.1  # seconds
var _last_batch_time: Dictionary = {}
var _frame_budget: float = 8.0  # milliseconds per frame
var _max_events_per_frame: int = 20
var _high_throughput_mode: bool = false
var _coroutine_yield_threshold: int = 100
var _integration_batch_types: Array = ["schema_updates", "config_adjustments", "template_updates", "resource_optimizations"]
var _node_wrapper: Node
var _logger: Callable
var _frame_start_time: float = 0.0

func _init(logger: Callable):
	_logger = logger
	_setup_integration_batches()

func _setup_integration_batches():
	for batch_type in _integration_batch_types:
		_integration_batches[batch_type] = []
		_last_batch_time[batch_type] = Time.get_time_dict_from_system().unix

func set_node_wrapper(node: Node):
	_node_wrapper = node

func queue_phase_event(phase_name: String, event_data: Dictionary):
	if not _phase_batches.has(phase_name):
		_phase_batches[phase_name] = []
	
	_phase_batches[phase_name].append(event_data)
	
	if _should_process_phase_batch(phase_name):
		_process_phase_batch(phase_name)

func queue_integration_event(integration_type: String, event_data: Dictionary):
	if not _integration_batches.has(integration_type):
		_integration_batches[integration_type] = []
	
	_integration_batches[integration_type].append(event_data)
	
	if _should_process_integration_batch(integration_type):
		_process_integration_batch(integration_type)

func _should_process_phase_batch(phase_name: String) -> bool:
	var batch = _phase_batches[phase_name]
	return batch.size() >= _max_batch_size or _is_batch_timeout_reached(phase_name)

func _should_process_integration_batch(integration_type: String) -> bool:
	var batch = _integration_batches[integration_type]
	var last_time = _last_batch_time.get(integration_type, 0.0)
	var current_time = Time.get_time_dict_from_system().unix
	
	return batch.size() >= _max_batch_size or (current_time - last_time) >= _batch_timeout

func _is_batch_timeout_reached(phase_name: String) -> bool:
	var last_time = _last_batch_time.get(phase_name, 0.0)
	var current_time = Time.get_time_dict_from_system().unix
	return (current_time - last_time) >= _batch_timeout

func _process_phase_batch(phase_name: String):
	var batch = _phase_batches[phase_name]
	if batch.is_empty():
		return
	
	_logger.call("Processing phase batch: %s (%d events)" % [phase_name, batch.size()], 1)
	
	if _high_throughput_mode and batch.size() > _coroutine_yield_threshold:
		_process_batch_with_coroutine(batch, "phase", phase_name)
	else:
		_process_batch_immediate(batch, "phase", phase_name)
	
	_phase_batches[phase_name].clear()
	_last_batch_time[phase_name] = Time.get_time_dict_from_system().unix

func _process_integration_batch(integration_type: String):
	var batch = _integration_batches[integration_type]
	if batch.is_empty():
		return
	
	_logger.call("Processing integration batch: %s (%d events)" % [integration_type, batch.size()], 1)
	
	if _high_throughput_mode and batch.size() > _coroutine_yield_threshold:
		_process_batch_with_coroutine(batch, "integration", integration_type)
	else:
		_process_batch_immediate(batch, "integration", integration_type)
	
	_integration_batches[integration_type].clear()
	_last_batch_time[integration_type] = Time.get_time_dict_from_system().unix

func _process_batch_immediate(batch: Array, batch_type: String, batch_name: String):
	var successful = 0
	var failed = 0
	var start_time = Time.get_time_dict_from_system().unix
	
	for event_data in batch:
		if _process_single_batch_event(event_data):
			successful += 1
		else:
			failed += 1
	
	var duration = Time.get_time_dict_from_system().unix - start_time
	_emit_batch_completion_event(batch_type, batch_name, successful, failed, duration)

func _process_batch_with_coroutine(batch: Array, batch_type: String, batch_name: String):
	if not _node_wrapper:
		_process_batch_immediate(batch, batch_type, batch_name)
		return
	
	# Start coroutine for high-throughput processing
	_node_wrapper.call_deferred("_process_batch_coroutine", batch, batch_type, batch_name)

func _process_batch_coroutine(batch: Array, batch_type: String, batch_name: String):
	var successful = 0
	var failed = 0
	var start_time = Time.get_time_dict_from_system().unix
	var events_processed = 0
	
	for event_data in batch:
		if _process_single_batch_event(event_data):
			successful += 1
		else:
			failed += 1
		
		events_processed += 1
		
		# Yield after processing threshold number of events
		if events_processed >= _coroutine_yield_threshold:
			await _node_wrapper.get_tree().process_frame
			events_processed = 0
	
	var duration = Time.get_time_dict_from_system().unix - start_time
	_emit_batch_completion_event(batch_type, batch_name, successful, failed, duration)

func _process_single_batch_event(event_data: Dictionary) -> bool:
	# This would typically delegate to the main event bus publish method
	# For now, we'll simulate processing
	var event_name = event_data.get("event_name", "")
	var data = event_data.get("data", {})
	
	# Simulate processing time
	if randf() < 0.95:  # 95% success rate
		return true
	else:
		_logger.call("Failed to process batch event: %s" % event_name, 3)
		return false

func _emit_batch_completion_event(batch_type: String, batch_name: String, 
								 successful: int, failed: int, duration: float):
	if batch_type == "integration":
		# Emit integration_batch_completed signal (would be connected to event bus)
		_logger.call("Integration batch completed: %s (%d success, %d failed, %.3fs)" % 
			[batch_name, successful, failed, duration], 1)
	else:
		# Emit phase_batch_completed signal
		_logger.call("Phase batch completed: %s (%d success, %d failed, %.3fs)" % 
			[batch_name, successful, failed, duration], 1)

func enable_high_throughput_mode(enabled: bool, yield_threshold: int = 100):
	_high_throughput_mode = enabled
	_coroutine_yield_threshold = yield_threshold
	_logger.call("High-throughput mode: %s (yield threshold: %d)" % 
		[("enabled" if enabled else "disabled"), yield_threshold], 1)

func set_frame_budget(budget_ms: float):
	_frame_budget = budget_ms

func get_frame_budget_ms() -> float:
	return _frame_budget

func set_events_per_frame(count: int):
	_max_events_per_frame = count

func set_coroutine_yield_threshold(threshold: int):
	_coroutine_yield_threshold = threshold

func force_process_all_batches():
	# Process all phase batches
	for phase_name in _phase_batches:
		if not _phase_batches[phase_name].is_empty():
			_process_phase_batch(phase_name)
	
	# Process all integration batches
	for integration_type in _integration_batches:
		if not _integration_batches[integration_type].is_empty():
			_process_integration_batch(integration_type)
