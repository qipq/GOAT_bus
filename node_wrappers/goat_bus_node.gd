@tool
extends Node
class_name GoatBusNode

# D. Version Manifest Block
const MANIFEST = {
	"name": "GoatBusNode",
	"version": "1.0.0", 
	"author": "ONE OF HAM",
	"date": "2025-08-04",
	"description": "Universal event bus wrapper for 2.5D-engine ecosystem"
}

## GoatBusNode - Wrapper for EventBus communication with scene tree
## Provides a clean interface between the EventBus system and Godot nodes

# Configuration
@export var event_bus_path: NodePath = NodePath()
@export var auto_subscribe_events: Array[String] = []
@export var auto_unsubscribe: bool = true
@export var enable_debug_logging: bool = false
@export var retry_timeout_frames: int = 300  # 5 seconds at 60fps
@export var max_retry_interval: float = 8.0  # C. Exponential backoff cap
@export var retry_backoff_multiplier: float = 1.5  # C. Configurable backoff multiplier
@export var event_bus_group: String = "event_bus"  # E. Configurable group name

# Internal references
var _event_bus = null
var _subscription_ids: Array = []
# B. Hotload/Failsafe tracking
var _connection_lost_frame: int = -1
var _retry_attempts: int = 0
var _current_retry_interval: float = 1.0

# Signals for advanced event handling
signal event_received(event_name: String, data: Dictionary, priority: int)
signal event_bus_connected()
signal event_bus_disconnected()
signal subscription_failed(event_name: String, error: String)

func _ready():
	_discover_event_bus()
	if _event_bus:
		_auto_subscribe()
		_connect_event_bus_signals()
		event_bus_connected.emit()
	else:
		_connection_lost_frame = Engine.get_process_frames()

func _process(_delta):
	# B. Monitor for bus loss and retry with exponential backoff
	if not _event_bus and _connection_lost_frame > 0:
		var frames_elapsed = Engine.get_process_frames() - _connection_lost_frame
		if frames_elapsed >= retry_timeout_frames:
			_handle_dependency_timeout()
		elif frames_elapsed % int(_current_retry_interval * 60) == 0:  # Convert to frames
			_retry_bus_connection()

func _exit_tree():
	_cleanup_subscriptions()
	if _event_bus:
		event_bus_disconnected.emit()

# 1. Discovery with strict conformance and error handling
func _discover_event_bus():
	# 1. Explicit path
	if event_bus_path and not event_bus_path.is_empty():
		var candidate = get_node_or_null(event_bus_path)
		if candidate:
			_event_bus = candidate
			_log_debug("EventBus found at explicit path: %s" % event_bus_path)
			return

	# 2. Autoload or singleton by name/class
	if has_node("/root/EventBusEnhanced"):
		_event_bus = get_node("/root/EventBusEnhanced")
		_log_debug("EventBus found as EventBusEnhanced autoload")
	elif Engine.has_singleton("EventBusEnhanced"):
		_event_bus = Engine.get_singleton("EventBusEnhanced")
		_log_debug("EventBus found as EventBusEnhanced singleton")
	elif has_node("/root/EventBus"):
		_event_bus = get_node("/root/EventBus")
		_log_debug("EventBus found as EventBus autoload")
	elif Engine.has_singleton("EventBus"):
		_event_bus = Engine.get_singleton("EventBus")
		_log_debug("EventBus found as EventBus singleton")
	else:
		# E. Group discovery with multi-candidate handling
		if not _event_bus and not event_bus_group.is_empty():
			var candidates = get_tree().get_nodes_in_group(event_bus_group)
			if candidates.size() > 1:
				push_warning("Multiple EventBus candidates found in group '%s'. Using first one: %s" % [event_bus_group, candidates[0].name])
				# Future: could add selection criteria like priority property or specific class check
				for candidate in candidates:
					_log_debug("EventBus candidate: %s (class: %s)" % [candidate.name, candidate.get_class()])
			if candidates.size() > 0:
				_event_bus = candidates[0]
				_log_debug("EventBus found via group '%s': %s" % [event_bus_group, _event_bus.name])
		
		# 3. Search global script registry (class_name) - Editor only
		if not _event_bus and Engine.is_editor_hint():
			# Note: ScriptServer is editor-only, skip in runtime
			_log_debug("Script registry search skipped (runtime mode)")

	# 4. Fallback: attempt to create in editor/test only
	if not _event_bus and Engine.is_editor_hint():
		var eb_script = load("res://addons/2.5D_engine/core/backbone/event_bus.gd")
		if eb_script:
			_event_bus = eb_script.new()
			_log_debug("EventBus created from script (editor mode)")

	# 5. Success cleanup
	if _event_bus:
		_connection_lost_frame = -1
		_retry_attempts = 0
		_current_retry_interval = 1.0
	# 6. Fail if still missing
	elif not Engine.is_editor_hint():
		push_error("EventBus instance not found. GoatBusNode will not function!")

# B. Hotload/Failsafe methods
func _handle_dependency_timeout():
	push_error("EventBus connection timeout after %d frames" % retry_timeout_frames)
	_connection_lost_frame = -1

func _handle_bus_lost():
	_log_debug("EventBus connection lost, attempting recovery")
	_cleanup_subscriptions()
	_event_bus = null
	_connection_lost_frame = Engine.get_process_frames()
	event_bus_disconnected.emit()

func _retry_bus_connection():
	# C. Exponential backoff with configurable multiplier
	_retry_attempts += 1
	_current_retry_interval = min(_current_retry_interval * retry_backoff_multiplier, max_retry_interval)
	
	_log_debug("Retrying EventBus connection (attempt %d, interval %.1fs)" % [_retry_attempts, _current_retry_interval])
	_discover_event_bus()
	
	if _event_bus:
		_auto_subscribe()
		_connect_event_bus_signals()
		event_bus_connected.emit()
		_log_debug("EventBus reconnected after %d attempts" % _retry_attempts)

# 2. Auto-subscription with modern handler contract
func _auto_subscribe():
	if not _event_bus or not auto_subscribe_events:
		return
	
	for event_name in auto_subscribe_events:
		# A. Memory safety: Use WeakRef for handler ownership (EventBus handles this internally)
		# Note: EventBus already uses WeakRef for subscription owners, ensuring memory safety
		var handler = Callable(self, "_on_event_bus_event")
		var sub_id = _event_bus.subscribe(event_name, handler, self)
		_subscription_ids.append({"event_name": event_name, "subscription_id": sub_id})
		_log_debug("Auto-subscribed to event: %s (ID: %s)" % [event_name, sub_id])

# Supports both typed EventData and legacy event handling
func _on_event_bus_event(event_name, data = null, priority = 1):
	# If using EventData, handle accordingly
	if typeof(event_name) == TYPE_OBJECT and event_name is RefCounted and event_name.has_method("get"):
		var event_data = event_name
		_handle_typed_event(event_data)
	else:
		_handle_legacy_event(event_name, data, priority)
	
	# Emit signal for external handling
	if typeof(event_name) == TYPE_STRING:
		event_received.emit(event_name, data if data else {}, priority)

# Default handlers (override these in subclasses as needed)
@warning_ignore("unused_parameter")
func _handle_typed_event(event_data):
	"""Override this in subclasses if you need custom logic; default is log only."""
	_log_debug("Received typed event: %s" % event_data.name)
	# Override in subclasses for custom typed event handling

@warning_ignore("unused_parameter")
func _handle_legacy_event(event_name: String, data: Dictionary, priority: int):
	"""Override this in subclasses if you need custom logic; default is log only."""
	_log_debug("Received legacy event: %s (priority: %d)" % [event_name, priority])
	# Override in subclasses for custom legacy event handling

# 3. Clean unsubscription
func _cleanup_subscriptions():
	if auto_unsubscribe and _event_bus and _subscription_ids:
		for pair in _subscription_ids:
			var success = _event_bus.unsubscribe(pair["event_name"], pair["subscription_id"])
			if success:
				_log_debug("Unsubscribed from: %s" % pair["event_name"])
			else:
				push_warning("Failed to unsubscribe from: %s" % pair["event_name"])
		_subscription_ids.clear()

# 4. Publishing API with schema validation
func publish_event(event_name: String, data: Dictionary = {}, priority: int = 1):
	if not _event_bus:
		push_warning("EventBus not available")
		_handle_bus_lost()  # B. Trigger recovery on bus loss
		return false

	# Schema enforcement: validate before publishing
	if _event_bus.has_method("validate"):
		var result = _event_bus.validate(data)
		if not result.get("is_valid", true):
			var error_msg = "Event data does not match schema for '%s': %s" % [event_name, result.errors]
			push_warning(error_msg)
			subscription_failed.emit(event_name, error_msg)
			return false
	
	# Publish event
	var success = _event_bus.publish(event_name, data, priority)
	_log_debug("Published event: %s (success: %s)" % [event_name, success])
	return success

# Manual subscription method
func subscribe_to_event(event_name: String, handler: Callable = Callable(), owner: Object = null):
	if not _event_bus:
		push_warning("EventBus not available")
		_handle_bus_lost()  # B. Trigger recovery
		return ""
	
	# Use provided handler or default to our internal handler
	var actual_handler = handler if handler.is_valid() else Callable(self, "_on_event_bus_event")
	var actual_owner = owner if owner else self
	
	var sub_id = _event_bus.subscribe(event_name, actual_handler, actual_owner)
	_subscription_ids.append({"event_name": event_name, "subscription_id": sub_id})
	_log_debug("Manually subscribed to event: %s (ID: %s)" % [event_name, sub_id])
	return sub_id

# Manual unsubscription
func unsubscribe_from_event(event_name: String, subscription_id: String = ""):
	if not _event_bus:
		push_warning("EventBus not available")
		return false
	
	# If no subscription_id provided, find and remove all subscriptions for this event
	if subscription_id.is_empty():
		var removed_count = 0
		for i in range(_subscription_ids.size() - 1, -1, -1):
			var pair = _subscription_ids[i]
			if pair["event_name"] == event_name:
				var success = _event_bus.unsubscribe(event_name, pair["subscription_id"])
				if success:
					_subscription_ids.remove_at(i)
					removed_count += 1
		_log_debug("Unsubscribed from all instances of: %s (%d removed)" % [event_name, removed_count])
		return removed_count > 0
	else:
		var success = _event_bus.unsubscribe(event_name, subscription_id)
		if success:
			# Remove from our tracking
			for i in range(_subscription_ids.size() - 1, -1, -1):
				var pair = _subscription_ids[i]
				if pair["event_name"] == event_name and pair["subscription_id"] == subscription_id:
					_subscription_ids.remove_at(i)
					break
		_log_debug("Unsubscribed from: %s (ID: %s, success: %s)" % [event_name, subscription_id, success])
		return success

# 5. Advanced API exposure
func get_event_schema(event_name: String):
	if _event_bus and _event_bus.has_method("get_event_schema"):
		return _event_bus.get_event_schema(event_name)
	return null

func validate_event(event_name: String, data: Dictionary):
	if _event_bus and _event_bus.has_method("validate"):
		return _event_bus.validate(data)
	return {"is_valid": true, "errors": []}

func register_event_schema(event_name: String, schema_def: Dictionary):
	if _event_bus and _event_bus.has_method("register_event_schema"):
		_event_bus.register_event_schema(event_name, schema_def)
		_log_debug("Registered schema for event: %s" % event_name)
	else:
		push_warning("EventBus does not support schema registration")

func create_typed_event_schema(event_name: String, field_definitions: Dictionary):
	if _event_bus and _event_bus.has_method("create_typed_event_schema"):
		return _event_bus.create_typed_event_schema(event_name, field_definitions)
	return null

func register_bulk_schemas(schema_definitions: Dictionary):
	if _event_bus and _event_bus.has_method("register_bulk_schemas"):
		_event_bus.register_bulk_schemas(schema_definitions)
		_log_debug("Registered %d bulk schemas" % schema_definitions.size())

func request_event_replay(target_object: Object = null):
	var replay_target = target_object if target_object else self
	if _event_bus and _event_bus.has_method("replay_operations"):
		var success = _event_bus.replay_operations(replay_target)
		_log_debug("Event replay requested (success: %s)" % success)
		return success
	else:
		push_warning("EventBus does not support replay/backlog.")
		return false

# 6. Persistent and batched event publishing
func publish_persistent_event(phase_name: String, event_data: Dictionary):
	if _event_bus and _event_bus.has_method("queue_phase_event"):
		_event_bus.queue_phase_event(phase_name, event_data)
		_log_debug("Published persistent event to phase: %s" % phase_name)
	else:
		push_warning("Persistent/batched event publishing is not supported by the EventBus.")

func publish_integration_event(integration_type: String, event_data: Dictionary):
	if _event_bus and _event_bus.has_method("queue_integration_event"):
		_event_bus.queue_integration_event(integration_type, event_data)
		_log_debug("Published integration event: %s" % integration_type)
	else:
		push_warning("Integration event publishing is not supported by the EventBus.")

# Performance and diagnostics
func get_event_statistics():
	if _event_bus and _event_bus.has_method("get_event_statistics"):
		return _event_bus.get_event_statistics()
	return {}

func get_performance_stats():
	if _event_bus and _event_bus.has_method("get_performance_stats"):
		return _event_bus.get_performance_stats()
	return {}

func get_subscription_stats():
	if _event_bus and _event_bus.has_method("get_subscription_stats"):
		return _event_bus.get_subscription_stats()
	return {}

func force_process_batches():
	if _event_bus and _event_bus.has_method("force_process_all_batches"):
		_event_bus.force_process_all_batches()
		_log_debug("Forced processing of all event batches")

# Configuration methods
func enable_high_throughput_mode(enabled: bool, yield_threshold: int = 100):
	if _event_bus and _event_bus.has_method("enable_high_throughput_mode"):
		_event_bus.enable_high_throughput_mode(enabled, yield_threshold)
		_log_debug("High throughput mode: %s (threshold: %d)" % [enabled, yield_threshold])

func set_frame_budget(budget_ms: float):
	if _event_bus and _event_bus.has_method("set_frame_budget"):
		_event_bus.set_frame_budget(budget_ms)
		_log_debug("Frame budget set to: %f ms" % budget_ms)

func enable_schema_enforcement(enabled: bool, exceptions: Array = []):
	if _event_bus and _event_bus.has_method("enable_schema_enforcement"):
		_event_bus.enable_schema_enforcement(enabled, exceptions)
		_log_debug("Schema enforcement: %s (exceptions: %s)" % [enabled, exceptions])

# 7. Optional signal connections for advanced event handling
func _connect_event_bus_signals():
	if not _event_bus:
		return
	
	var signals = [
		"event_published", "subscriber_queue_overflow",
		"integration_event_processed", "batch_processing_completed",
		"dependency_connection_failed", "dependencies_resolved",
		"system_health_routing_updated", "frame_budget_exceeded"
	]
	
	for sig in signals:
		if _event_bus.has_signal(sig):
			_event_bus.connect(sig, Callable(self, "_on_event_bus_signal").bind(sig))
			_log_debug("Connected to EventBus signal: %s" % sig)

# Generic bus signal handler (override for custom handling)
@warning_ignore("unused_parameter")
func _on_event_bus_signal(signal_name: String):
	"""Override this in subclasses if you need custom logic; default is log only."""
	_log_debug("EventBus signal received: %s" % signal_name)
	# Override in subclasses for custom signal handling

# 8. Logging and debugging
func log_event_bus(message: String, level: int = 1):
	if _event_bus and _event_bus.has_method("_log"):
		_event_bus._log(message, level)
	else:
		match level:
			0: # DEBUG
				if enable_debug_logging:
					print("[GoatBusNode DEBUG] %s" % message)
			1: # INFO
				print("[GoatBusNode INFO] %s" % message)
			2: # WARNING
				push_warning("[GoatBusNode] %s" % message)
			3: # ERROR
				push_error("[GoatBusNode] %s" % message)

func _log_debug(message: String):
	if enable_debug_logging:
		log_event_bus(message, 0)

# Health and status checking
func is_event_bus_connected() -> bool:
	return _event_bus != null

func get_event_bus_status() -> Dictionary:
	if not _event_bus:
		return {"connected": false, "error": "EventBus not found"}
	
	var status = {"connected": true, "subscriptions": _subscription_ids.size()}
	
	# Get additional status if available
	if _event_bus.has_method("get_status"):
		var bus_status = _event_bus.get_status()
		status.merge(bus_status)
	
	return status

# Utility methods for external systems
func get_event_bus_reference():
	return _event_bus

func force_reconnect():
	_cleanup_subscriptions()
	_discover_event_bus()
	if _event_bus:
		_auto_subscribe()
		_connect_event_bus_signals()
		event_bus_connected.emit()
		_log_debug("EventBus reconnected successfully")
	else:
		push_error("Failed to reconnect to EventBus")

# Configuration export/import
func export_configuration() -> Dictionary:
	var config = {
		"event_bus_path": str(event_bus_path),
		"auto_subscribe_events": auto_subscribe_events.duplicate(),
		"auto_unsubscribe": auto_unsubscribe,
		"enable_debug_logging": enable_debug_logging,
		"subscription_count": _subscription_ids.size(),
		"connected": is_event_bus_connected()
	}
	
	# Include EventBus configuration if available
	if _event_bus and _event_bus.has_method("export_configuration"):
		config["event_bus_config"] = _event_bus.export_configuration()
	
	return config

func import_configuration(config: Dictionary):
	if config.has("event_bus_path"):
		event_bus_path = NodePath(config.event_bus_path)
	if config.has("auto_subscribe_events"):
		auto_subscribe_events = config.auto_subscribe_events
	if config.has("auto_unsubscribe"):
		auto_unsubscribe = config.auto_unsubscribe
	if config.has("enable_debug_logging"):
		enable_debug_logging = config.enable_debug_logging
	
	_log_debug("Configuration imported successfully")

# Debug and introspection
func debug_print_status():
	print("=== GoatBusNode Status ===")
	print("Connected: %s" % is_event_bus_connected())
	print("Subscriptions: %d" % _subscription_ids.size())
	print("Auto-subscribe events: %s" % auto_subscribe_events)
	print("Event bus path: %s" % event_bus_path)
	
	if _event_bus and _event_bus.has_method("debug_print_dependencies"):
		print("\n=== EventBus Dependencies ===")
		_event_bus.debug_print_dependencies()
	
	if _event_bus and _event_bus.has_method("debug_print_performance"):
		print("\n=== EventBus Performance ===")
		_event_bus.debug_print_performance()

# Convenience methods for common operations
func quick_subscribe(event_name: String, method_name: String = "_on_event_bus_event") -> String:
	"""Quick subscription using a method name on this node"""
	if not has_method(method_name):
		push_error("Method '%s' not found on %s" % [method_name, name])
		return ""
	
	var handler = Callable(self, method_name)
	return subscribe_to_event(event_name, handler)

func quick_publish(event_name: String, data: Dictionary = {}):
	"""Quick publish with normal priority"""
	return publish_event(event_name, data, 1)

func emergency_publish(event_name: String, data: Dictionary = {}):
	"""Publish with high priority for emergency events"""
	return publish_event(event_name, data, 3)

# Batch operations
func subscribe_to_multiple_events(event_names: Array[String]) -> Array:
	"""Subscribe to multiple events and return subscription IDs"""
	var subscription_ids = []
	for event_name in event_names:
		var sub_id = subscribe_to_event(event_name)
		subscription_ids.append(sub_id)
	return subscription_ids

func publish_multiple_events(events: Array[Dictionary]):
	"""Publish multiple events from an array of event dictionaries"""
	for event_dict in events:
		var event_name = event_dict.get("name", "")
		var data = event_dict.get("data", {})
		var priority = event_dict.get("priority", 1)
		
		if not event_name.is_empty():
			publish_event(event_name, data, priority)

# Manual subscription method (enhanced version from instructions)
func subscribe_to_event_enhanced(event_name: String, handler: Callable = Callable(), owner: Object = null) -> String:
	if not _event_bus:
		push_warning("EventBus not available")
		subscription_failed.emit(event_name, "EventBus not available")
		return ""
	
	# Use provided handler or default to our internal handler
	var actual_handler = handler if handler.is_valid() else Callable(self, "_on_event_bus_event")
	var actual_owner = owner if owner else self
	
	var sub_id = _event_bus.subscribe(event_name, actual_handler, actual_owner)
	if sub_id and not sub_id.is_empty():
		_subscription_ids.append({"event_name": event_name, "subscription_id": sub_id})
		_log_debug("Subscribed to event: %s (ID: %s)" % [event_name, sub_id])
	else:
		var error_msg = "Failed to subscribe to event: %s" % event_name
		push_warning(error_msg)
		subscription_failed.emit(event_name, error_msg)
	
	return sub_id
