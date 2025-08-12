# ===== goat_bus/utils/helpers.gd =====
extends RefCounted
class_name GoatBusHelpers

const VERSION := "4.2.0.69"
const MANIFEST := {
	"script_name": "GoatBusHelpers",
	"script_path": "res://goat_bus/utils/helpers.gd",
	"class_name": "GoatBusHelpers",
	"version": "1.0.0",
	"description": "Helper utilities for GoatBus event system",
	"required_dependencies": [],
	"optional_dependencies": [],
	"features": ["test_helpers", "validation", "mock_data"],
	"api_version": "goatbus-v1.0.0",
	"last_updated": "2025-08-10"
}

# =============================================================================
# HELPER UTILITIES
# =============================================================================

# Helper function to create test subscriptions
static func create_test_subscription(event_name: String, callback: Callable, owner: Object = null) -> String:
	"""Helper function for creating test subscriptions"""
	var subscription = EventSubscription.new(callback, owner)
	return subscription.subscription_id

# Helper function to validate event data structures
static func validate_event_data(event_data: Dictionary) -> bool:
	"""Validate that event data has required fields"""
	var required_fields = ["event_name", "data"]
	for field in required_fields:
		if not event_data.has(field):
			return false
	return true

# Helper function to calculate health scores
static func calculate_health_score(failure_probability: float, response_time_ms: float = 0.0, 
						   error_rate: float = 0.0) -> float:
	"""Calculate overall health score from various metrics"""
	var base_score = 1.0 - failure_probability
	
	# Adjust for response time (penalty for slow responses)
	if response_time_ms > 100.0:  # More than 100ms is considered slow
		var time_penalty = min(0.3, (response_time_ms - 100.0) / 1000.0)
		base_score -= time_penalty
	
	# Adjust for error rate
	if error_rate > 0.0:
		var error_penalty = min(0.4, error_rate)
		base_score -= error_penalty
	
	return clamp(base_score, 0.0, 1.0)

# Helper function to format performance statistics
static func format_performance_stats(stats: Dictionary) -> String:
	"""Format performance statistics for logging"""
	var lines = []
	lines.append("=== PERFORMANCE STATISTICS ===")
	lines.append("Total Events: %d" % stats.get("total_events_processed", 0))
	lines.append("Events/Second: %.2f" % stats.get("average_events_per_second", 0.0))
	lines.append("Frame Time: %.2fms" % stats.get("recent_frame_avg_ms", 0.0))
	lines.append("Active Subscriptions: %d" % stats.get("active_subscriptions", 0))
	
	var throughput = stats.get("throughput_data", {})
	if not throughput.is_empty():
		lines.append("--- Throughput Details ---")
		lines.append("Recent Events/Frame: %.2f" % throughput.get("recent_events_per_frame", 0.0))
		lines.append("Processing Time Stats: %s" % str(throughput.get("processing_time_stats", {})))
	
	return "\n".join(lines)

# Helper function to create mock health data
static func create_mock_health_data(system_name: String, health_score: float) -> Dictionary:
	"""Create mock health data for testing"""
	return {
		"system_name": system_name,
		"failure_probability": 1.0 - clamp(health_score, 0.0, 1.0),
		"response_time_ms": randf() * 200.0,
		"error_rate": randf() * 0.1,
		"current_state": "RUNNING" if health_score > 0.5 else "DEGRADED",
		"last_updated": Time.get_time_dict_from_system().unix
	}

# Helper function to create integration event data
static func create_integration_event(integration_type: String, event_name: String, 
							 data: Dictionary = {}) -> Dictionary:
	"""Create properly formatted integration event data"""
	var integration_data = data.duplicate()
	integration_data["_integration_meta"] = {
		"integration_type": integration_type,
		"event_name": event_name,
		"timestamp": Time.get_time_dict_from_system().unix,
		"source": "integration_helper"
	}
	
	return {
		"event_name": event_name,
		"data": integration_data,
		"priority": 2,  # Normal priority for integration events
		"integration_type": integration_type
	}

# Helper function to simulate system load
static func simulate_system_load(base_load: float, spike_probability: float = 0.1, 
						 spike_multiplier: float = 3.0) -> float:
	"""Simulate realistic system load with occasional spikes"""
	var load = base_load
	
	# Add random variation
	load += (randf() - 0.5) * 0.2
	
	# Occasional load spikes
	if randf() < spike_probability:
		load *= spike_multiplier
	
	return clamp(load, 0.0, 10.0)

# Helper function for batch processing metrics
static func calculate_batch_efficiency(batch_size: int, processing_time: float, 
							   success_rate: float) -> Dictionary:
	"""Calculate batch processing efficiency metrics"""
	var events_per_second = batch_size / max(processing_time, 0.001)
	var efficiency_score = success_rate * (events_per_second / 100.0)  # Normalize to typical throughput
	
	return {
		"events_per_second": events_per_second,
		"efficiency_score": clamp(efficiency_score, 0.0, 1.0),
		"success_rate": success_rate,
		"avg_time_per_event": processing_time / max(batch_size, 1),
		"recommendation": "increase_batch_size" if efficiency_score < 0.5 else "optimal"
	}

# Helper function to create time-based event filters
static func create_time_based_filter(start_time: float, end_time: float, 
							 event_names: Array = []) -> Dictionary:
	"""Create filter for time-based event queries"""
	return {
		"start_timestamp": start_time,
		"end_timestamp": end_time,
		"event_filters": event_names,
		"created_at": Time.get_time_dict_from_system().unix
	}

# Helper function to validate subscription configuration
static func validate_subscription_config(config: Dictionary) -> Dictionary:
	"""Validate subscription configuration and return validation result"""
	var result = {"valid": true, "errors": [], "warnings": []}
	
	# Check required fields
	if not config.has("event_name") or config.event_name.is_empty():
		result.errors.append("event_name is required")
		result.valid = false
	
	if not config.has("handler") or not config.handler.is_valid():
		result.errors.append("valid handler is required")
		result.valid = false
	
	# Check optional field ranges
	var max_concurrent = config.get("max_concurrent", 1)
	if max_concurrent < 1 or max_concurrent > 100:
		result.warnings.append("max_concurrent should be between 1 and 100")
	
	var queue_size = config.get("queue_size", 100)
	if queue_size < 10 or queue_size > 10000:
		result.warnings.append("queue_size should be between 10 and 10000")
	
	return result
