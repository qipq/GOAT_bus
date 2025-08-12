extends RefCounted
class_name TimeWindowOperations

const VERSION := "4.2.0.69"
const MANIFEST := {
	"script_name": "TimeWindowOperations",
	"script_path": "res://goat_bus/core/time_windows.gd",
	"class_name": "TimeWindowOperations",
	"version": "1.0.0",
	"description": "Time window aggregations for GoatBus event system",
	"required_dependencies": [],
	"optional_dependencies": [],
	"features": ["sliding_windows", "tumbling_windows", "aggregations"],
	"api_version": "goatbus-v1.0.0",
	"last_updated": "2025-08-10"
}

# =============================================================================
# TIME WINDOW OPERATIONS
# =============================================================================

var _time_windows: Dictionary = {}  # window_id -> WindowConfig
var _window_events: Dictionary = {}  # window_id -> Array[EventData]
var _aggregations: Dictionary = {}   # window_id -> AggregationResult
var _logger: Callable

class WindowConfig extends RefCounted:
	var window_id: String
	var duration: float  # seconds
	var slide_interval: float  # seconds (0 = tumbling window)
	var event_filters: Array = []  # event names to include
	var aggregation_functions: Array = []  # "count", "avg", "sum", "min", "max"
	var max_events: int = 1000
	var created_at: float
	var last_slide: float
	
	func _init(id: String, window_duration: float):
		window_id = id
		duration = window_duration
		created_at = Time.get_time_dict_from_system().unix
		last_slide = created_at

class AggregationResult extends RefCounted:
	var window_id: String
	var window_start: float
	var window_end: float
	var event_count: int = 0
	var aggregated_data: Dictionary = {}
	var computed_at: float
	
	func _init(id: String, start: float, end: float):
		window_id = id
		window_start = start
		window_end = end
		computed_at = Time.get_time_dict_from_system().unix

func _init(logger: Callable):
	_logger = logger

func create_time_window(window_id: String, duration: float, slide_interval: float = 0.0, 
					   event_filters: Array = [], aggregations: Array = ["count"]) -> bool:
	if _time_windows.has(window_id):
		return false
	
	var config = WindowConfig.new(window_id, duration)
	config.slide_interval = slide_interval
	config.event_filters = event_filters
	config.aggregation_functions = aggregations
	
	_time_windows[window_id] = config
	_window_events[window_id] = []
	_aggregations[window_id] = AggregationResult.new(window_id, Time.get_time_dict_from_system().unix, 
													Time.get_time_dict_from_system().unix + duration)
	
	_logger.call("Created time window '%s': duration=%.1fs, slide=%.1fs, filters=%s" % 
		[window_id, duration, slide_interval, str(event_filters)], 1)
	
	return true

func add_event_to_windows(event_data: Dictionary):
	var current_time = Time.get_time_dict_from_system().unix
	var event_name = event_data.get("name", event_data.get("event_name", ""))
	
	for window_id in _time_windows:
		var config = _time_windows[window_id]
		
		# Check if event matches filters
		if not config.event_filters.is_empty() and event_name not in config.event_filters:
			continue
		
		# Check if we need to slide the window
		if config.slide_interval > 0 and (current_time - config.last_slide) >= config.slide_interval:
			_slide_window(window_id)
			config.last_slide = current_time
		
		# Add event to window
		var events = _window_events[window_id]
		events.append(event_data)
		
		# Remove events outside the window
		_cleanup_window_events(window_id)
		
		# Update aggregations
		_update_aggregations(window_id)

func _slide_window(window_id: String):
	var config = _time_windows[window_id]
	var current_time = Time.get_time_dict_from_system().unix
	
	# Create new aggregation for the sliding window
	var old_aggregation = _aggregations[window_id]
	_aggregations[window_id] = AggregationResult.new(
		window_id,
		current_time - config.duration,
		current_time
	)
	
	_logger.call("Slid window '%s' from %.1f-%.1f to %.1f-%.1f" % 
		[window_id, old_aggregation.window_start, old_aggregation.window_end,
		_aggregations[window_id].window_start, _aggregations[window_id].window_end], 0)

func _cleanup_window_events(window_id: String):
	var config = _time_windows[window_id]
	var events = _window_events[window_id]
	var current_time = Time.get_time_dict_from_system().unix
	var window_start = current_time - config.duration
	
	# Remove events outside the time window
	for i in range(events.size() - 1, -1, -1):
		var event = events[i]
		var event_timestamp = event.get("timestamp", current_time)
		if event_timestamp < window_start:
			events.remove_at(i)
	
	# Limit number of events to prevent memory issues
	while events.size() > config.max_events:
		events.pop_front()

func _update_aggregations(window_id: String):
	var config = _time_windows[window_id]
	var events = _window_events[window_id]
	var aggregation = _aggregations[window_id]
	
	aggregation.event_count = events.size()
	aggregation.computed_at = Time.get_time_dict_from_system().unix
	
	for func_name in config.aggregation_functions:
		match func_name:
			"count":
				aggregation.aggregated_data["count"] = events.size()
			"avg_processing_time":
				aggregation.aggregated_data["avg_processing_time"] = _compute_avg_processing_time(events)
			"event_rate":
				aggregation.aggregated_data["event_rate"] = _compute_event_rate(events, config.duration)
			"unique_events":
				aggregation.aggregated_data["unique_events"] = _count_unique_events(events)
			"priority_distribution":
				aggregation.aggregated_data["priority_distribution"] = _compute_priority_distribution(events)
			"error_rate":
				aggregation.aggregated_data["error_rate"] = _compute_error_rate(events)

func _compute_avg_processing_time(events: Array) -> float:
	if events.is_empty():
		return 0.0
	
	var total_time = 0.0
	var count = 0
	
	for event in events:
		var processing_time = event.get("processing_time", 0.0)
		if processing_time > 0:
			total_time += processing_time
			count += 1
	
	return total_time / max(count, 1)

func _compute_event_rate(events: Array, duration: float) -> float:
	return events.size() / max(duration, 1.0)

func _count_unique_events(events: Array) -> int:
	var unique_names = {}
	for event in events:
		var event_name = event.get("name", event.get("event_name", ""))
		unique_names[event_name] = true
	return unique_names.size()

func _compute_priority_distribution(events: Array) -> Dictionary:
	var distribution = {}
	for event in events:
		var priority = event.get("priority", 1)
		distribution[priority] = distribution.get(priority, 0) + 1
	return distribution

func _compute_error_rate(events: Array) -> float:
	if events.is_empty():
		return 0.0
	
	var error_count = 0
	for event in events:
		var has_error = event.get("error", false) or event.get("failed", false)
		if has_error:
			error_count += 1
	
	return float(error_count) / events.size()

func get_window_aggregation(window_id: String) -> Dictionary:
	var aggregation = _aggregations.get(window_id, null)
	if not aggregation:
		return {}
	
	return {
		"window_id": aggregation.window_id,
		"window_start": aggregation.window_start,
		"window_end": aggregation.window_end,
		"event_count": aggregation.event_count,
		"aggregated_data": aggregation.aggregated_data.duplicate(),
		"computed_at": aggregation.computed_at
	}

func get_events_in_window(window_id: String) -> Array:
	return _window_events.get(window_id, []).duplicate()

func get_all_window_summaries() -> Dictionary:
	var summaries = {}
	for window_id in _time_windows:
		var config = _time_windows[window_id]
		var aggregation = _aggregations[window_id]
		var events = _window_events[window_id]
		
		summaries[window_id] = {
			"config": {
				"duration": config.duration,
				"slide_interval": config.slide_interval,
				"event_filters": config.event_filters.duplicate(),
				"aggregation_functions": config.aggregation_functions.duplicate(),
				"created_at": config.created_at
			},
			"current_events": events.size(),
			"latest_aggregation": get_window_aggregation(window_id)
		}
	
	return summaries

func remove_time_window(window_id: String) -> bool:
	if not _time_windows.has(window_id):
		return false
	
	var events_removed = _window_events[window_id].size()
	_time_windows.erase(window_id)
	_window_events.erase(window_id)
	_aggregations.erase(window_id)
	
	_logger.call("Removed time window '%s' (%d events discarded)" % [window_id, events_removed], 1)
	return true

func clear_all_windows():
	var total_events = 0
	for events in _window_events.values():
		total_events += events.size()
	
	_time_windows.clear()
	_window_events.clear()
	_aggregations.clear()
	
	_logger.call("Cleared all time windows (%d events discarded)" % total_events, 1)
