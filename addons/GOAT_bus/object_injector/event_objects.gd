# =============================================================================
# EVENT OBJECTS - TYPE-SAFE EVENT CREATION SYSTEM
# =============================================================================
# Provides structured event creation with type safety and autocomplete support
# Integrates with GoatBus for dictionary-based event publishing
# =============================================================================

@tool
extends RefCounted
class_name EventObjects

const VERSION := "1.0.0"
const MANIFEST := {
	"script_name": "event_objects.gd",
	"script_path": "res://addons/api_builder/main/event_objects.gd",
	"class_name": "EventObjects",
	"version": "1.0.0",
	"description": "Type-safe event creation system providing structured events with autocomplete support for GoatBus integration",
	"required_dependencies": [],
	"optional_dependencies": ["goat_bus"],
	"features": [
		"type_safe_event_creation", "autocomplete_support", "validation_system",
		"dictionary_conversion", "factory_methods", "event_schemas",
		"complex_event_classes", "simple_event_factories", "metadata_injection"
	],
	"event_categories": [
		"system_events", "performance_events", "lifecycle_events", 
		"user_events", "error_events", "debug_events"
	],
	"api_version": "goatbus-events-v1.0.0",
	"last_updated": "2025-08-09"
}

# =============================================================================
# COMPLEX EVENT CLASSES (Full Objects with Validation)
# =============================================================================

class SystemHealthUpdate:
	var system_name: String
	var new_state: String
	var health_score: float
	var reason: String
	var timestamp: float
	var metadata: Dictionary
	
	func _init(p_system_name: String, p_new_state: String, p_health_score: float = 1.0, p_reason: String = ""):
		system_name = p_system_name
		new_state = p_new_state
		health_score = clamp(p_health_score, 0.0, 1.0)
		reason = p_reason
		timestamp = Time.get_unix_time_from_system()
		metadata = {
			"event_type": "SystemHealthUpdate",
			"version": "1.0.0",
			"schema_valid": true
		}
		
		# Validation
		if system_name.is_empty():
			push_warning("SystemHealthUpdate: system_name cannot be empty")
			metadata.schema_valid = false
		
		var valid_states = ["healthy", "degraded", "critical", "offline", "maintenance"]
		if new_state not in valid_states:
			push_warning("SystemHealthUpdate: new_state must be one of: " + str(valid_states))
			metadata.schema_valid = false
	
	func to_dict() -> Dictionary:
		return {
			"system_name": system_name,
			"new_state": new_state,
			"health_score": health_score,
			"reason": reason,
			"timestamp": timestamp,
			"metadata": metadata
		}
	
	func is_valid() -> bool:
		return metadata.get("schema_valid", false)
	
	func get_severity() -> String:
		if health_score >= 0.8:
			return "normal"
		elif health_score >= 0.5:
			return "warning"
		else:
			return "critical"

class PerformanceMetricsUpdate:
	var system_name: String
	var response_time_ms: float
	var error_rate: float
	var failure_probability: float
	var timestamp: float
	var metadata: Dictionary
	var metrics: Dictionary
	
	func _init(p_system_name: String, p_response_time_ms: float, p_error_rate: float = 0.0, p_failure_probability: float = 0.0):
		system_name = p_system_name
		response_time_ms = max(0.0, p_response_time_ms)
		error_rate = clamp(p_error_rate, 0.0, 1.0)
		failure_probability = clamp(p_failure_probability, 0.0, 1.0)
		timestamp = Time.get_unix_time_from_system()
		metadata = {
			"event_type": "PerformanceMetricsUpdate",
			"version": "1.0.0",
			"schema_valid": true
		}
		metrics = {
			"throughput": _calculate_throughput(),
			"availability": _calculate_availability(),
			"performance_score": _calculate_performance_score()
		}
		
		# Validation
		if system_name.is_empty():
			push_warning("PerformanceMetricsUpdate: system_name cannot be empty")
			metadata.schema_valid = false
	
	func to_dict() -> Dictionary:
		return {
			"system_name": system_name,
			"response_time_ms": response_time_ms,
			"error_rate": error_rate,
			"failure_probability": failure_probability,
			"timestamp": timestamp,
			"metadata": metadata,
			"metrics": metrics
		}
	
	func _calculate_throughput() -> float:
		if response_time_ms <= 0:
			return 0.0
		return 1000.0 / response_time_ms  # requests per second
	
	func _calculate_availability() -> float:
		return 1.0 - failure_probability
	
	func _calculate_performance_score() -> float:
		var response_score = max(0.0, 1.0 - (response_time_ms / 1000.0))  # 1000ms = 0 score
		var error_score = 1.0 - error_rate
		var availability_score = _calculate_availability()
		return (response_score + error_score + availability_score) / 3.0

class IntegrationBatchStarting:
	var batch_id: String
	var batch_size: int
	var estimated_duration_ms: float
	var priority: String
	var timestamp: float
	var metadata: Dictionary
	
	func _init(p_batch_id: String, p_batch_size: int, p_estimated_duration_ms: float = 0.0, p_priority: String = "normal"):
		batch_id = p_batch_id
		batch_size = max(0, p_batch_size)
		estimated_duration_ms = max(0.0, p_estimated_duration_ms)
		priority = p_priority
		timestamp = Time.get_unix_time_from_system()
		metadata = {
			"event_type": "IntegrationBatchStarting",
			"version": "1.0.0",
			"schema_valid": true
		}
		
		# Validation
		if batch_id.is_empty():
			push_warning("IntegrationBatchStarting: batch_id cannot be empty")
			metadata.schema_valid = false
		
		var valid_priorities = ["low", "normal", "high", "critical"]
		if priority not in valid_priorities:
			push_warning("IntegrationBatchStarting: priority must be one of: " + str(valid_priorities))
			priority = "normal"
	
	func to_dict() -> Dictionary:
		return {
			"batch_id": batch_id,
			"batch_size": batch_size,
			"estimated_duration_ms": estimated_duration_ms,
			"priority": priority,
			"timestamp": timestamp,
			"metadata": metadata
		}

class IntegrationBatchCompleted:
	var batch_id: String
	var actual_duration_ms: float
	var success_count: int
	var failure_count: int
	var success: bool
	var timestamp: float
	var metadata: Dictionary
	var summary: Dictionary
	
	func _init(p_batch_id: String, p_actual_duration_ms: float, p_success_count: int, p_failure_count: int = 0):
		batch_id = p_batch_id
		actual_duration_ms = max(0.0, p_actual_duration_ms)
		success_count = max(0, p_success_count)
		failure_count = max(0, p_failure_count)
		success = failure_count == 0
		timestamp = Time.get_unix_time_from_system()
		metadata = {
			"event_type": "IntegrationBatchCompleted",
			"version": "1.0.0",
			"schema_valid": true
		}
		summary = {
			"total_items": success_count + failure_count,
			"success_rate": _calculate_success_rate(),
			"throughput": _calculate_throughput()
		}
		
		# Validation
		if batch_id.is_empty():
			push_warning("IntegrationBatchCompleted: batch_id cannot be empty")
			metadata.schema_valid = false
	
	func to_dict() -> Dictionary:
		return {
			"batch_id": batch_id,
			"actual_duration_ms": actual_duration_ms,
			"success_count": success_count,
			"failure_count": failure_count,
			"success": success,
			"timestamp": timestamp,
			"metadata": metadata,
			"summary": summary
		}
	
	func _calculate_success_rate() -> float:
		var total = success_count + failure_count
		if total == 0:
			return 0.0
		return float(success_count) / float(total)
	
	func _calculate_throughput() -> float:
		if actual_duration_ms <= 0:
			return 0.0
		var total_items = success_count + failure_count
		return float(total_items) / (actual_duration_ms / 1000.0)  # items per second

class ConfigurationUpdated:
	var config_key: String
	var old_value: Variant
	var new_value: Variant
	var source: String
	var timestamp: float
	var metadata: Dictionary
	
	func _init(p_config_key: String, p_old_value: Variant, p_new_value: Variant, p_source: String = "unknown"):
		config_key = p_config_key
		old_value = p_old_value
		new_value = p_new_value
		source = p_source
		timestamp = Time.get_unix_time_from_system()
		metadata = {
			"event_type": "ConfigurationUpdated",
			"version": "1.0.0",
			"schema_valid": true,
			"value_type": type_string(typeof(new_value))
		}
		
		# Validation
		if config_key.is_empty():
			push_warning("ConfigurationUpdated: config_key cannot be empty")
			metadata.schema_valid = false
	
	func to_dict() -> Dictionary:
		return {
			"config_key": config_key,
			"old_value": old_value,
			"new_value": new_value,
			"source": source,
			"timestamp": timestamp,
			"metadata": metadata
		}

class SystemInitializationComplete:
	var system_name: String
	var initialization_time_ms: float
	var success: bool
	var loaded_components: Array
	var failed_components: Array
	var timestamp: float
	var metadata: Dictionary
	
	func _init(p_system_name: String, p_initialization_time_ms: float, p_success: bool, p_loaded_components: Array = [], p_failed_components: Array = []):
		system_name = p_system_name
		initialization_time_ms = max(0.0, p_initialization_time_ms)
		success = p_success
		loaded_components = p_loaded_components.duplicate()
		failed_components = p_failed_components.duplicate()
		timestamp = Time.get_unix_time_from_system()
		metadata = {
			"event_type": "SystemInitializationComplete",
			"version": "1.0.0",
			"schema_valid": true,
			"component_count": loaded_components.size(),
			"failure_count": failed_components.size()
		}
		
		# Validation
		if system_name.is_empty():
			push_warning("SystemInitializationComplete: system_name cannot be empty")
			metadata.schema_valid = false
	
	func to_dict() -> Dictionary:
		return {
			"system_name": system_name,
			"initialization_time_ms": initialization_time_ms,
			"success": success,
			"loaded_components": loaded_components,
			"failed_components": failed_components,
			"timestamp": timestamp,
			"metadata": metadata
		}

class QueueThresholdExceeded:
	var queue_name: String
	var current_size: int
	var threshold: int
	var severity: String
	var timestamp: float
	var metadata: Dictionary
	
	func _init(p_queue_name: String, p_current_size: int, p_threshold: int, p_severity: String = "warning"):
		queue_name = p_queue_name
		current_size = max(0, p_current_size)
		threshold = max(0, p_threshold)
		severity = p_severity
		timestamp = Time.get_unix_time_from_system()
		metadata = {
			"event_type": "QueueThresholdExceeded",
			"version": "1.0.0",
			"schema_valid": true,
			"overflow_amount": max(0, current_size - threshold)
		}
		
		# Validation
		if queue_name.is_empty():
			push_warning("QueueThresholdExceeded: queue_name cannot be empty")
			metadata.schema_valid = false
		
		var valid_severities = ["info", "warning", "error", "critical"]
		if severity not in valid_severities:
			push_warning("QueueThresholdExceeded: severity must be one of: " + str(valid_severities))
			severity = "warning"
	
	func to_dict() -> Dictionary:
		return {
			"queue_name": queue_name,
			"current_size": current_size,
			"threshold": threshold,
			"severity": severity,
			"timestamp": timestamp,
			"metadata": metadata
		}

class EventValidationFailed:
	var event_name: String
	var validation_errors: Array
	var attempted_data: Dictionary
	var validator_name: String
	var timestamp: float
	var metadata: Dictionary
	
	func _init(p_event_name: String, p_validation_errors: Array, p_attempted_data: Dictionary = {}, p_validator_name: String = "default"):
		event_name = p_event_name
		validation_errors = p_validation_errors.duplicate()
		attempted_data = p_attempted_data.duplicate()
		validator_name = p_validator_name
		timestamp = Time.get_unix_time_from_system()
		metadata = {
			"event_type": "EventValidationFailed",
			"version": "1.0.0",
			"schema_valid": true,
			"error_count": validation_errors.size()
		}
		
		# Validation
		if event_name.is_empty():
			push_warning("EventValidationFailed: event_name cannot be empty")
			metadata.schema_valid = false
	
	func to_dict() -> Dictionary:
		return {
			"event_name": event_name,
			"validation_errors": validation_errors,
			"attempted_data": attempted_data,
			"validator_name": validator_name,
			"timestamp": timestamp,
			"metadata": metadata
		}

# =============================================================================
# SIMPLE EVENT FACTORIES (Lightweight Dictionary Creation)
# =============================================================================

static func create_phase_started(phase_name: String, context: String = "system") -> Dictionary:
	return {
		"phase_name": phase_name,
		"context": context,
		"timestamp": Time.get_unix_time_from_system(),
		"metadata": {
			"event_type": "phase_started",
			"version": "1.0.0"
		}
	}

static func create_phase_completed(phase_name: String, duration_ms: float, success: bool, context: String = "system") -> Dictionary:
	return {
		"phase_name": phase_name,
		"duration_ms": max(0.0, duration_ms),
		"success": success,
		"context": context,
		"timestamp": Time.get_unix_time_from_system(),
		"metadata": {
			"event_type": "phase_completed",
			"version": "1.0.0"
		}
	}

static func create_maintenance_started(maintenance_type: String, estimated_duration_ms: float = 0.0, affected_systems: Array = []) -> Dictionary:
	return {
		"maintenance_type": maintenance_type,
		"estimated_duration_ms": max(0.0, estimated_duration_ms),
		"affected_systems": affected_systems.duplicate(),
		"timestamp": Time.get_unix_time_from_system(),
		"metadata": {
			"event_type": "maintenance_started",
			"version": "1.0.0"
		}
	}

static func create_performance_alert(alert_type: String, severity: String = "warning", metric_value: float = 0.0, threshold: float = 0.0, system_name: String = "unknown") -> Dictionary:
	var valid_severities = ["info", "warning", "error", "critical"]
	if severity not in valid_severities:
		severity = "warning"
	
	return {
		"alert_type": alert_type,
		"severity": severity,
		"metric_value": metric_value,
		"threshold": threshold,
		"system_name": system_name,
		"exceeded": metric_value > threshold if threshold > 0 else false,
		"timestamp": Time.get_unix_time_from_system(),
		"metadata": {
			"event_type": "performance_alert",
			"version": "1.0.0"
		}
	}

static func create_debug_info_requested(info_type: String, requester: String, additional_data: Dictionary = {}) -> Dictionary:
	var event_data = {
		"info_type": info_type,
		"requester": requester,
		"timestamp": Time.get_unix_time_from_system(),
		"metadata": {
			"event_type": "debug_info_requested",
			"version": "1.0.0"
		}
	}
	
	# Merge additional data
	for key in additional_data:
		event_data[key] = additional_data[key]
	
	return event_data

static func create_user_action(action_name: String, user_id: String = "unknown", action_data: Dictionary = {}) -> Dictionary:
	var event_data = {
		"action_name": action_name,
		"user_id": user_id,
		"timestamp": Time.get_unix_time_from_system(),
		"metadata": {
			"event_type": "user_action",
			"version": "1.0.0"
		}
	}
	
	# Merge action-specific data
	for key in action_data:
		event_data[key] = action_data[key]
	
	return event_data

static func create_error_occurred(error_type: String, error_message: String, source: String = "unknown", stack_trace: String = "") -> Dictionary:
	return {
		"error_type": error_type,
		"error_message": error_message,
		"source": source,
		"stack_trace": stack_trace,
		"timestamp": Time.get_unix_time_from_system(),
		"metadata": {
			"event_type": "error_occurred",
			"version": "1.0.0",
			"severity": _determine_error_severity(error_type)
		}
	}

static func create_resource_loaded(resource_path: String, resource_type: String, load_time_ms: float = 0.0, success: bool = true) -> Dictionary:
	return {
		"resource_path": resource_path,
		"resource_type": resource_type,
		"load_time_ms": max(0.0, load_time_ms),
		"success": success,
		"timestamp": Time.get_unix_time_from_system(),
		"metadata": {
			"event_type": "resource_loaded",
			"version": "1.0.0"
		}
	}

static func create_state_changed(entity_id: String, old_state: String, new_state: String, reason: String = "") -> Dictionary:
	return {
		"entity_id": entity_id,
		"old_state": old_state,
		"new_state": new_state,
		"reason": reason,
		"timestamp": Time.get_unix_time_from_system(),
		"metadata": {
			"event_type": "state_changed",
			"version": "1.0.0"
		}
	}

# =============================================================================
# UTILITY AND HELPER FUNCTIONS
# =============================================================================

static func _determine_error_severity(error_type: String) -> String:
	var error_type_lower = error_type.to_lower()
	
	if "critical" in error_type_lower or "fatal" in error_type_lower:
		return "critical"
	elif "error" in error_type_lower:
		return "error"
	elif "warning" in error_type_lower:
		return "warning"
	else:
		return "info"

static func validate_event_data(event_data: Dictionary, expected_schema: Dictionary) -> Array:
	"""Validate event data against expected schema, return array of errors"""
	var errors = []
	
	# Check required fields
	if expected_schema.has("required_fields"):
		for field in expected_schema.required_fields:
			if not event_data.has(field):
				errors.append("Missing required field: " + field)
			elif event_data[field] == null:
				errors.append("Required field cannot be null: " + field)
	
	# Check field types if specified
	if expected_schema.has("field_types"):
		for field in expected_schema.field_types:
			if event_data.has(field):
				var expected_type = expected_schema.field_types[field]
				var actual_type = typeof(event_data[field])
				if actual_type != expected_type:
					errors.append("Field '%s' expected type %s but got %s" % [field, type_string(expected_type), type_string(actual_type)])
	
	return errors

static func get_event_schema(event_type: String) -> Dictionary:
	"""Get the schema definition for a specific event type"""
	var schemas = {
		"SystemHealthUpdate": {
			"required_fields": ["system_name", "new_state", "health_score"],
			"field_types": {
				"system_name": TYPE_STRING,
				"new_state": TYPE_STRING,
				"health_score": TYPE_FLOAT
			}
		},
		"PerformanceMetricsUpdate": {
			"required_fields": ["system_name", "response_time_ms"],
			"field_types": {
				"system_name": TYPE_STRING,
				"response_time_ms": TYPE_FLOAT,
				"error_rate": TYPE_FLOAT,
				"failure_probability": TYPE_FLOAT
			}
		},
		"phase_started": {
			"required_fields": ["phase_name"],
			"field_types": {
				"phase_name": TYPE_STRING,
				"context": TYPE_STRING
			}
		},
		"performance_alert": {
			"required_fields": ["alert_type"],
			"field_types": {
				"alert_type": TYPE_STRING,
				"severity": TYPE_STRING,
				"metric_value": TYPE_FLOAT
			}
		}
	}
	
	return schemas.get(event_type, {})

static func get_all_event_types() -> Array:
	"""Get list of all available event types"""
	return [
		# Complex event classes
		"SystemHealthUpdate",
		"PerformanceMetricsUpdate", 
		"IntegrationBatchStarting",
		"IntegrationBatchCompleted",
		"ConfigurationUpdated",
		"SystemInitializationComplete",
		"QueueThresholdExceeded",
		"EventValidationFailed",
		
		# Simple event factories
		"phase_started",
		"phase_completed",
		"maintenance_started",
		"performance_alert",
		"debug_info_requested",
		"user_action",
		"error_occurred",
		"resource_loaded",
		"state_changed"
	]

static func create_event_by_name(event_type: String, params: Dictionary) -> Dictionary:
	"""Create an event by type name with parameters - useful for dynamic creation"""
	match event_type:
		"phase_started":
			return create_phase_started(
				params.get("phase_name", ""),
				params.get("context", "system")
			)
		"phase_completed":
			return create_phase_completed(
				params.get("phase_name", ""),
				params.get("duration_ms", 0.0),
				params.get("success", false),
				params.get("context", "system")
			)
		"performance_alert":
			return create_performance_alert(
				params.get("alert_type", ""),
				params.get("severity", "warning"),
				params.get("metric_value", 0.0),
				params.get("threshold", 0.0),
				params.get("system_name", "unknown")
			)
		"error_occurred":
			return create_error_occurred(
				params.get("error_type", ""),
				params.get("error_message", ""),
				params.get("source", "unknown"),
				params.get("stack_trace", "")
			)
		_:
			push_warning("Unknown event type: " + event_type)
			return {}

static func get_autocomplete_data() -> Dictionary:
	"""Get structured autocomplete data for IDE integration"""
	return {
		"complex_events": {
			"SystemHealthUpdate": {
				"constructor": "EventObjects.SystemHealthUpdate.new(system_name: String, new_state: String, health_score: float = 1.0, reason: String = \"\")",
				"usage": "var event = EventObjects.SystemHealthUpdate.new(\"player_system\", \"healthy\", 0.95)",
				"fields": ["system_name", "new_state", "health_score", "reason", "timestamp", "metadata"]
			},
			"PerformanceMetricsUpdate": {
				"constructor": "EventObjects.PerformanceMetricsUpdate.new(system_name: String, response_time_ms: float, error_rate: float = 0.0, failure_probability: float = 0.0)",
				"usage": "var event = EventObjects.PerformanceMetricsUpdate.new(\"ai_system\", 45.2, 0.02)",
				"fields": ["system_name", "response_time_ms", "error_rate", "failure_probability", "timestamp", "metadata", "metrics"]
			}
		},
		"simple_events": {
			"phase_started": {
				"factory": "EventObjects.create_phase_started(phase_name: String, context: String = \"system\")",
				"usage": "bus.publish(\"phase_started\", EventObjects.create_phase_started(\"initialization\"))",
				"fields": ["phase_name", "context", "timestamp", "metadata"]
			},
			"performance_alert": {
				"factory": "EventObjects.create_performance_alert(alert_type: String, severity: String = \"warning\", metric_value: float = 0.0, threshold: float = 0.0, system_name: String = \"unknown\")",
				"usage": "bus.publish(\"performance_alert\", EventObjects.create_performance_alert(\"high_latency\", \"critical\", 850.0, 500.0))",
				"fields": ["alert_type", "severity", "metric_value", "threshold", "system_name", "exceeded", "timestamp", "metadata"]
			}
		}
	}

# =============================================================================
# INTEGRATION HELPERS
# =============================================================================

static func register_with_goat_bus(goat_bus) -> void:
	"""Register all event factories with GoatBus for easy access"""
	if not goat_bus or not goat_bus.has_method("register_event_factory"):
		push_warning("GoatBus doesn't support event factory registration")
		return
	
	# Register the main EventObjects class
	goat_bus.register_event_factory("EventObjects", EventObjects)
	
	# Register individual factory methods
	var factory_methods = [
		"create_phase_started",
		"create_phase_completed", 
		"create_maintenance_started",
		"create_performance_alert",
		"create_debug_info_requested",
		"create_user_action",
		"create_error_occurred",
		"create_resource_loaded",
		"create_state_changed"
	]
	
	for method_name in factory_methods:
		goat_bus.register_event_factory(method_name, Callable(EventObjects, method_name))

static func get_manifest() -> Dictionary:
	"""Get the complete manifest for this EventObjects system"""
	return MANIFEST
