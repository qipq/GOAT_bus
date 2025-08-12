# ===== goat_bus/core/persistent_queue.gd =====
extends RefCounted
class_name PersistentEventQueue

const VERSION := "4.2.0.69"
const MANIFEST := {
	"script_name": "PersistentEventQueue",
	"script_path": "res://goat_bus/core/persistent_queue.gd",
	"class_name": "PersistentEventQueue",
	"version": "1.0.0",
	"description": "Persistent event queue management for GoatBus",
	"required_dependencies": [],
	"optional_dependencies": [],
	"features": ["backpressure_control", "drop_policies", "queue_metrics"],
	"api_version": "goatbus-v1.0.0",
	"last_updated": "2025-08-10"
}

# =============================================================================
# PERSISTENT EVENT QUEUE
# =============================================================================

var _event_queues: Dictionary = {}  # subscription_id -> Array[Dictionary]
var _global_backlog: Array = []     # All events for replay
var _max_backlog_size: int = 10000
var _max_queue_size_per_subscriber: int = 1000
var _backpressure_enabled: bool = true
var _backpressure_threshold: float = 0.8  # 80% full triggers backpressure
var _drop_policy: String = "drop_oldest"  # "drop_oldest", "drop_newest", "block"
var _queue_metrics: Dictionary = {}
var _total_queued_events: int = 0
var _logger: Callable

enum DropPolicy { DROP_OLDEST, DROP_NEWEST, BLOCK }

func _init(logger: Callable):
	_logger = logger

func create_subscriber_queue(subscription_id: String, max_size: int = 1000) -> bool:
	if _event_queues.has(subscription_id):
		return false
	
	_event_queues[subscription_id] = []
	_queue_metrics[subscription_id] = {
		"queued_count": 0,
		"processed_count": 0,
		"dropped_count": 0,
		"last_processed": 0.0,
		"max_queue_depth": 0,
		"avg_queue_depth": 0.0,
		"backpressure_events": 0
	}
	_max_queue_size_per_subscriber = max_size
	_logger.call("Created persistent queue for subscriber: %s (max: %d)" % [subscription_id, max_size], 1)
	return true

func remove_subscriber_queue(subscription_id: String) -> bool:
	if not _event_queues.has(subscription_id):
		return false
	
	var queue_size = _event_queues[subscription_id].size()
	_total_queued_events -= queue_size
	_event_queues.erase(subscription_id)
	_queue_metrics.erase(subscription_id)
	_logger.call("Removed persistent queue for subscriber: %s (%d events discarded)" % [subscription_id, queue_size], 1)
	return true

func queue_event_for_subscriber(subscription_id: String, event_data: Dictionary) -> bool:
	if not _event_queues.has(subscription_id):
		return false
	
	var queue = _event_queues[subscription_id]
	var metrics = _queue_metrics[subscription_id]
	
	# Check backpressure
	if _backpressure_enabled and queue.size() >= (_max_queue_size_per_subscriber * _backpressure_threshold):
		metrics.backpressure_events += 1
		
		match _drop_policy:
			"drop_oldest":
				if queue.size() >= _max_queue_size_per_subscriber:
					queue.pop_front()
					metrics.dropped_count += 1
					_total_queued_events -= 1
			"drop_newest":
				if queue.size() >= _max_queue_size_per_subscriber:
					metrics.dropped_count += 1
					return false  # Don't add the new event
			"block":
				if queue.size() >= _max_queue_size_per_subscriber:
					return false  # Reject the event
	
	# Add timestamp for queue management
	event_data["_queue_meta"] = {
		"queued_at": Time.get_time_dict_from_system().unix,
		"subscription_id": subscription_id,
		"queue_depth": queue.size()
	}
	
	queue.append(event_data)
	metrics.queued_count += 1
	metrics.max_queue_depth = max(metrics.max_queue_depth, queue.size())
	_total_queued_events += 1
	
	return true

func dequeue_event_for_subscriber(subscription_id: String) -> Dictionary:
	if not _event_queues.has(subscription_id):
		return {}
	
	var queue = _event_queues[subscription_id]
	if queue.is_empty():
		return {}
	
	var event_data = queue.pop_front()
	var metrics = _queue_metrics[subscription_id]
	metrics.processed_count += 1
	metrics.last_processed = Time.get_time_dict_from_system().unix
	_total_queued_events -= 1
	
	# Update average queue depth
	var total_measurements = metrics.queued_count
	if total_measurements > 0:
		metrics.avg_queue_depth = (metrics.avg_queue_depth * (total_measurements - 1) + queue.size()) / total_measurements
	
	return event_data

func get_queue_size(subscription_id: String) -> int:
	var queue = _event_queues.get(subscription_id, [])
	return queue.size()

func has_queued_events(subscription_id: String) -> bool:
	return get_queue_size(subscription_id) > 0

func get_queue_metrics(subscription_id: String) -> Dictionary:
	return _queue_metrics.get(subscription_id, {})

func get_all_queue_metrics() -> Dictionary:
	var summary = {
		"total_queued_events": _total_queued_events,
		"total_queues": _event_queues.size(),
		"backpressure_enabled": _backpressure_enabled,
		"backpressure_threshold": _backpressure_threshold,
		"drop_policy": _drop_policy,
		"max_queue_size": _max_queue_size_per_subscriber,
		"subscriber_metrics": _queue_metrics.duplicate()
	}
	
	var total_dropped = 0
	var total_backpressure = 0
	for metrics in _queue_metrics.values():
		total_dropped += metrics.dropped_count
		total_backpressure += metrics.backpressure_events
	
	summary.total_dropped_events = total_dropped
	summary.total_backpressure_events = total_backpressure
	
	return summary

func clear_subscriber_queue(subscription_id: String) -> int:
	if not _event_queues.has(subscription_id):
		return 0
	
	var queue = _event_queues[subscription_id]
	var cleared_count = queue.size()
	queue.clear()
	_total_queued_events -= cleared_count
	_queue_metrics[subscription_id].queued_count = 0
	
	return cleared_count

func set_backpressure_config(enabled: bool, threshold: float = 0.8, policy: String = "drop_oldest"):
	_backpressure_enabled = enabled
	_backpressure_threshold = clamp(threshold, 0.1, 1.0)
	_drop_policy = policy
	_logger.call("Backpressure config updated: enabled=%s, threshold=%.1f%%, policy=%s" % 
		[enabled, threshold * 100, policy], 1)

func add_to_global_backlog(event_data: Dictionary):
	# Add to global backlog for replay functionality
	if _global_backlog.size() >= _max_backlog_size:
		_global_backlog.pop_front()  # Remove oldest
	
	event_data["_backlog_meta"] = {
		"backlog_timestamp": Time.get_time_dict_from_system().unix,
		"backlog_index": _global_backlog.size()
	}
	
	_global_backlog.append(event_data)

func get_events_since(timestamp: float) -> Array:
	var filtered_events = []
	for event_data in _global_backlog:
		var event_timestamp = event_data.get("timestamp", 0.0)
		if event_timestamp >= timestamp:
			filtered_events.append(event_data)
	return filtered_events

func get_events_in_window(start_timestamp: float, end_timestamp: float) -> Array:
	var windowed_events = []
	for event_data in _global_backlog:
		var event_timestamp = event_data.get("timestamp", 0.0)
		if event_timestamp >= start_timestamp and event_timestamp <= end_timestamp:
			windowed_events.append(event_data)
	return windowed_events

func get_recent_events(count: int) -> Array:
	if count <= 0:
		return []
	
	var start_index = max(0, _global_backlog.size() - count)
	return _global_backlog.slice(start_index)

func clear_global_backlog():
	_global_backlog.clear()
	_logger.call("Global event backlog cleared", 1)

func set_max_backlog_size(size: int):
	_max_backlog_size = max(100, size)  # Minimum 100 events
	
	# Trim if necessary
	while _global_backlog.size() > _max_backlog_size:
		_global_backlog.pop_front()
	
	_logger.call("Max backlog size set to: %d" % _max_backlog_size, 1)
