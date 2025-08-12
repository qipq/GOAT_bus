# ===== goat_bus/core/backpressure.gd =====
extends RefCounted
class_name BackpressureController

const VERSION := "4.2.0.69"
const MANIFEST := {
	"script_name": "BackpressureController",
	"script_path": "res://goat_bus/core/backpressure.gd",
	"class_name": "BackpressureController",
	"version": "1.0.0",
	"description": "Backpressure control for GoatBus event system",
	"required_dependencies": [],
	"optional_dependencies": [],
	"features": ["adaptive_throttling", "pressure_monitoring", "action_control"],
	"api_version": "goatbus-v1.0.0",
	"last_updated": "2025-08-10"
}

# =============================================================================
# BACKPRESSURE CONTROLLER
# =============================================================================

var _enabled: bool = true
var _thresholds: Dictionary = {
	"queue_utilization": 0.8,    # 80% of max queue size
	"processing_rate": 0.9,      # 90% of max processing capacity
	"memory_pressure": 0.85,     # 85% of allocated memory
	"frame_budget": 0.8          # 80% of frame processing budget
}
var _current_metrics: Dictionary = {}
var _backpressure_actions: Array = []
var _throttle_factor: float = 1.0  # 1.0 = no throttling, 0.5 = 50% throttle
var _adaptive_throttling: bool = true
var _logger: Callable
var _backpressure_callbacks: Array = []

enum BackpressureAction {
	THROTTLE_PUBLISHERS,
	DROP_LOW_PRIORITY,
	BATCH_AGGRESSIVELY,
	DEFER_NON_CRITICAL,
	EMERGENCY_FLUSH
}

func _init(logger: Callable):
	_logger = logger
	_reset_metrics()

func _reset_metrics():
	_current_metrics = {
		"queue_utilization": 0.0,
		"processing_rate": 0.0,
		"memory_pressure": 0.0,
		"frame_budget_used": 0.0,
		"events_per_second": 0.0,
		"failed_events_rate": 0.0
	}

func update_metrics(metrics: Dictionary):
	for key in metrics:
		if _current_metrics.has(key):
			_current_metrics[key] = metrics[key]
	
	if _enabled:
		_evaluate_backpressure()

func _evaluate_backpressure():
	var pressure_level = _calculate_pressure_level()
	var old_throttle = _throttle_factor
	
	if _adaptive_throttling:
		_throttle_factor = _calculate_adaptive_throttle(pressure_level)
	
	# Determine required actions
	_backpressure_actions.clear()
	
	if pressure_level > 0.9:
		_backpressure_actions.append(BackpressureAction.EMERGENCY_FLUSH)
		_backpressure_actions.append(BackpressureAction.DROP_LOW_PRIORITY)
	elif pressure_level > 0.8:
		_backpressure_actions.append(BackpressureAction.THROTTLE_PUBLISHERS)
		_backpressure_actions.append(BackpressureAction.BATCH_AGGRESSIVELY)
	elif pressure_level > 0.6:
		_backpressure_actions.append(BackpressureAction.DEFER_NON_CRITICAL)
	
	# Notify callbacks if throttle changed significantly
	if abs(old_throttle - _throttle_factor) > 0.1:
		_notify_backpressure_change(pressure_level, old_throttle, _throttle_factor)

func _calculate_pressure_level() -> float:
	var max_pressure = 0.0
	
	for metric_name in _thresholds:
		if _current_metrics.has(metric_name):
			var current_value = _current_metrics[metric_name]
			var threshold = _thresholds[metric_name]
			var pressure = current_value / threshold
			max_pressure = max(max_pressure, pressure)
	
	return clamp(max_pressure, 0.0, 2.0)  # Allow up to 200% pressure

func _calculate_adaptive_throttle(pressure_level: float) -> float:
	if pressure_level <= 0.5:
		return 1.0  # No throttling
	elif pressure_level <= 1.0:
		# Linear throttle from 100% to 50%
		return 1.0 - (pressure_level - 0.5) * 1.0
	else:
		# Heavy throttling for extreme pressure
		return max(0.1, 0.5 - (pressure_level - 1.0) * 0.4)

func _notify_backpressure_change(pressure_level: float, old_throttle: float, new_throttle: float):
	var change_data = {
		"pressure_level": pressure_level,
		"old_throttle": old_throttle,
		"new_throttle": new_throttle,
		"active_actions": _backpressure_actions.duplicate(),
		"timestamp": Time.get_time_dict_from_system().unix
	}
	
	for callback in _backpressure_callbacks:
		if callback.is_valid():
			callback.call(change_data)
	
	_logger.call("Backpressure changed: pressure=%.2f, throttle %.2f→%.2f, actions=%s" % 
		[pressure_level, old_throttle, new_throttle, str(_backpressure_actions)], 2)

func should_throttle_publisher(publisher_priority: int = 1) -> bool:
	if not _enabled:
		return false
	
	# Higher priority publishers are less affected by throttling
	var priority_factor = 1.0 / max(publisher_priority, 1)
	var effective_throttle = _throttle_factor * priority_factor
	
	return randf() > effective_throttle

func should_drop_event(event_priority: int = 1) -> bool:
	if not _enabled:
		return false
	
	if BackpressureAction.DROP_LOW_PRIORITY in _backpressure_actions:
		# Drop low priority events when under pressure
		return event_priority <= 1 and randf() > _throttle_factor
	
	return false

func should_batch_aggressively() -> bool:
	return _enabled and BackpressureAction.BATCH_AGGRESSIVELY in _backpressure_actions

func should_defer_non_critical(event_name: String) -> bool:
	if not _enabled:
		return false
	
	if BackpressureAction.DEFER_NON_CRITICAL in _backpressure_actions:
		var non_critical_events = [
			"debug_info_updated", "metrics_collected", "status_report",
			"performance_stats", "subscription_stats"
		]
		return event_name in non_critical_events
	
	return false

func needs_emergency_flush() -> bool:
	return _enabled and BackpressureAction.EMERGENCY_FLUSH in _backpressure_actions

func add_backpressure_callback(callback: Callable):
	_backpressure_callbacks.append(callback)

func remove_backpressure_callback(callback: Callable):
	_backpressure_callbacks.erase(callback)

func set_threshold(metric_name: String, threshold: float):
	_thresholds[metric_name] = clamp(threshold, 0.1, 2.0)
	_logger.call("Backpressure threshold updated: %s = %.2f" % [metric_name, threshold], 1)

func get_current_status() -> Dictionary:
	return {
		"enabled": _enabled,
		"throttle_factor": _throttle_factor,
		"pressure_level": _calculate_pressure_level(),
		"active_actions": _backpressure_actions.duplicate(),
		"current_metrics": _current_metrics.duplicate(),
		"thresholds": _thresholds.duplicate(),
		"adaptive_throttling": _adaptive_throttling
	}

func enable_backpressure(enabled: bool):
	_enabled = enabled
	if not enabled:
		_throttle_factor = 1.0
		_backpressure_actions.clear()
	_logger.call("Backpressure control: %s" % ("enabled" if enabled else "disabled"), 1)

func enable_adaptive_throttling(enabled: bool):
	_adaptive_throttling = enabled
	_logger.call("Adaptive throttling: %s" % ("enabled" if enabled else "disabled"), 1)
