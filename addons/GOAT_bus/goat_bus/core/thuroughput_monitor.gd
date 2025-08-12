# ===== goat_bus/core/throughput_monitor.gd =====
extends RefCounted
class_name ThroughputMonitor

const VERSION := "4.2.0.69"
const MANIFEST := {
	"script_name": "ThroughputMonitor",
	"script_path": "res://goat_bus/core/throughput_monitor.gd",
	"class_name": "ThroughputMonitor",
	"version": "1.0.0",
	"description": "Throughput monitoring for GoatBus event system",
	"required_dependencies": [],
	"optional_dependencies": [],
	"features": ["frame_monitoring", "performance_tracking", "event_statistics"],
	"api_version": "goatbus-v1.0.0",
	"last_updated": "2025-08-10"
}

# =============================================================================
# THROUGHPUT MONITOR
# =============================================================================

var _event_counts: Dictionary = {}  # event_name -> count
var _processing_times: Dictionary = {}  # event_name -> Array[processing_time]
var _frame_times: Array = []
var _max_history_size: int = 1000
var _current_frame_events: int = 0
var _frame_start_time: float = 0.0
var _total_events_processed: int = 0
var _start_time: float
var _logger: Callable

func _init(logger: Callable):
	_logger = logger
	_start_time = Time.get_time_dict_from_system().unix

func _get_time_us() -> int:
	return Time.get_time_dict_from_system().unix * 1000000  # Convert to microseconds

func start_frame_monitoring():
	_frame_start_time = _get_time_us()
	_current_frame_events = 0

func end_frame_monitoring():
	if _frame_start_time > 0:
		var frame_time = _get_time_us() - _frame_start_time
		_frame_times.append(frame_time)
		
		if _frame_times.size() > _max_history_size:
			_frame_times.pop_front()
		
		_frame_start_time = 0.0

func record_event_processed(event_name: String):
	_event_counts[event_name] = _event_counts.get(event_name, 0) + 1
	_current_frame_events += 1
	_total_events_processed += 1

func record_handler_performance(event_name: String, processing_time_us: int):
	if not _processing_times.has(event_name):
		_processing_times[event_name] = []
	
	var times = _processing_times[event_name]
	times.append(processing_time_us)
	
	if times.size() > _max_history_size:
		times.pop_front()

func is_frame_budget_exceeded(budget_ms: float) -> bool:
	if _frame_times.is_empty():
		return false
	
	var last_frame_time_ms = _frame_times[-1] / 1000.0
	return last_frame_time_ms > budget_ms

func get_performance_report() -> Dictionary:
	var current_time = Time.get_time_dict_from_system().unix
	var uptime = current_time - _start_time
	
	var report = {
		"total_events_processed": _total_events_processed,
		"uptime_seconds": uptime,
		"average_events_per_second": _total_events_processed / max(uptime, 1.0),
		"recent_events_per_frame": _calculate_recent_events_per_frame(),
		"recent_frame_avg_ms": _calculate_recent_frame_avg_ms(),
		"event_counts": _event_counts.duplicate(),
		"processing_time_stats": _calculate_processing_time_stats()
	}
	
	return report

func _calculate_recent_events_per_frame() -> float:
	if _frame_times.size() < 10:
		return 0.0
	
	# Use last 10 frames
	var recent_frames = min(10, _frame_times.size())
	return float(_current_frame_events) / recent_frames

func _calculate_recent_frame_avg_ms() -> float:
	if _frame_times.is_empty():
		return 0.0
	
	var recent_frames = min(60, _frame_times.size())  # Last 60 frames
	var total_time = 0.0
	
	for i in range(_frame_times.size() - recent_frames, _frame_times.size()):
		total_time += _frame_times[i]
	
	return (total_time / recent_frames) / 1000.0  # Convert to milliseconds

func _calculate_processing_time_stats() -> Dictionary:
	var stats = {}
	
	for event_name in _processing_times:
		var times = _processing_times[event_name]
		if times.is_empty():
			continue
		
		var total_time = 0.0
		var min_time = times[0]
		var max_time = times[0]
		
		for time in times:
			total_time += time
			min_time = min(min_time, time)
			max_time = max(max_time, time)
		
		stats[event_name] = {
			"avg_us": total_time / times.size(),
			"min_us": min_time,
			"max_us": max_time,
			"sample_count": times.size()
		}
	
	return stats
