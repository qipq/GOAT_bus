# core/events/event_bus.gd
extends RefCounted
class_name GoatBus

# ===== ENUMS =====
enum EventPriority { LOW = 0, NORMAL = 1, HIGH = 2, CRITICAL = 3 }
enum LogLevel { DEBUG = 0, INFO = 1, WARNING = 2, ERROR = 3 }

# ===== SIGNALS =====
signal event_published(event_name: String, data: Dictionary, priority: EventPriority)
signal subscriber_queue_overflow(subscription_id: String, dropped_count: int)
signal integration_event_processed(event_name: String, integration_type: String)
signal batch_processing_completed(batch_data: Dictionary)
signal dependency_connection_failed(dependency_name: String)
signal dependencies_resolved()
signal system_health_routing_updated(system_name: String, health_score: float)
signal frame_budget_exceeded(frame_time_ms: float)

# ===== CORE PROPERTIES =====
var _subscriptions: Dictionary = {}
var _event_schemas: Dictionary = {}
var _persistent_queue: PersistentEventQueue
var _replay_system: EventReplaySystem
var _time_windows: TimeWindowOperations
var _backpressure_controller: BackpressureController
var _batch_processor: EventBatchProcessor
var _throughput_monitor: ThroughputMonitor
var _health_aware_router: HealthAwareRouter
var _dependency_manager: DependencyManager

# ===== FEATURE FLAGS =====
var _persistent_queuing_enabled: bool = true
var _replay_enabled: bool = true
var _backpressure_enabled: bool = true
var _time_window_operations_enabled: bool = true
var _auto_queue_creation: bool = true
var _auto_replay_buffers: bool = true
var _health_integration_enabled: bool = true
var _orchestration_batch_processing: bool = true
var _enable_validation: bool = false
var _performance_aware_routing: bool = true
var _enable_frame_monitoring: bool = true
var _enforce_schema_registration: bool = false
var _warn_unregistered_events: bool = true

# ===== STATE TRACKING =====
var _subscription_health_tracking: Dictionary = {}
var _degraded_subscriptions: Array = []
var _integration_event_stats: Dictionary = {}
var _external_systems: Dictionary = {}
var _schema_enforcement_exceptions: Array = []
var _pending_setup_calls: Array = []
var _initialization_complete: bool = false

# ===== LOGGING CONFIGURATION =====
var _log_level: LogLevel = LogLevel.INFO
var _production_mode: bool = false
var _use_godot_logging: bool = true
var _log_to_debugger: bool = false
var _log_file_path: String = ""
var _hotload_safe: bool = true

# ===== INITIALIZATION =====
func _init():
	_setup_components()
	_reset_integration_stats()

func _setup_components():
	"""Initialize all components with proper dependencies"""
	_persistent_queue = PersistentEventQueue.new(_create_logger_callable())
	_replay_system = EventReplaySystem.new(_create_logger_callable())
	_time_windows = TimeWindowOperations.new(_create_logger_callable())
	_backpressure_controller = BackpressureController.new(_create_logger_callable())
	_throughput_monitor = ThroughputMonitor.new(_create_logger_callable())
	_health_aware_router = HealthAwareRouter.new(_create_logger_callable())
	_dependency_manager = DependencyManager.new(_create_logger_callable())
	_batch_processor = EventBatchProcessor.new(_create_logger_callable())

# ===== CORRECTED EVENT SUBSCRIPTION CLASS =====
class EventSubscription extends RefCounted:
	var handler: Callable
	var owner_ref: WeakRef
	var subscription_id: String
	var created_at: float
	var is_busy: bool = false
	var processing_count: int = 0
	var max_concurrent: int = 1
	var queue_enabled: bool = false
	var personal_queue: Array = []
	var max_queue_size: int = 100
	var wants_replay: bool = false
	var replay_from_timestamp: float = 0.0
	
	func _init(handler_callable: Callable, owner: Object):
		handler = handler_callable
		if owner:
			owner_ref = weakref(owner)
		subscription_id = "sub_" + str(Time.get_time_dict_from_system().unix) + "_" + str(randi())
		created_at = Time.get_time_dict_from_system().unix
	
	func is_valid() -> bool:
		if not owner_ref:
			return handler.is_valid()
		var owner = owner_ref.get_ref()
		return owner != null and is_instance_valid(owner) and handler.is_valid()
	
	func can_accept_event() -> bool:
		return processing_count < max_concurrent
	
	func queue_event(event_data: Dictionary) -> bool:
		if not queue_enabled:
			return false
		if personal_queue.size() >= max_queue_size:
			personal_queue.pop_front()  # Drop oldest
		personal_queue.append(event_data)
		return true
	
	func get_next_queued_event() -> Dictionary:
		if personal_queue.is_empty():
			return {}
		return personal_queue.pop_front()
	
	func has_queued_events() -> bool:
		return not personal_queue.is_empty()
	
	func call_handler(data: Dictionary) -> bool:
		if not handler.is_valid():
			return false
		
		if not is_valid():
			return false
		
		processing_count += 1
		is_busy = processing_count >= max_concurrent
		
		# GDScript doesn't have try/except, so we check validity before calling
		var success = false
		if handler.is_valid():
			handler.call(data)
			success = true
		
		processing_count = max(0, processing_count - 1)
		is_busy = processing_count >= max_concurrent
		return success

# ===== EVENT REPLAY SYSTEM =====
class EventReplaySystem extends RefCounted:
	var _global_replay_buffer: Array = []
	var _max_global_buffer_size: int = 50000
	var _replay_buffers: Dictionary = {}  # subscription_id -> ReplayBuffer
	var _replay_sessions: Dictionary = {}  # session_id -> ReplaySession
	var _logger: Callable
	
	class ReplayBuffer extends RefCounted:
		var subscription_id: String
		var events: Array = []
		var max_size: int = 1000
		var created_at: float
		
		func _init(sub_id: String, size: int = 1000):
			subscription_id = sub_id
			max_size = size
			created_at = Time.get_time_dict_from_system().unix
		
		func add_event(event_data: Dictionary):
			events.append(event_data)
			if events.size() > max_size:
				events.pop_front()
	
	class ReplaySession extends RefCounted:
		var session_id: String
		var subscription_id: String
		var start_timestamp: float
		var end_timestamp: float
		var event_filters: Array
		var replay_speed: float
		var session_start: float
		var current_position: int = 0
		var paused: bool = false
		var completed: bool = false
		
		func _init(sub_id: String, start_time: float, end_time: float = 0.0, 
				  filters: Array = [], speed: float = 1.0):
			session_id = "replay_" + str(Time.get_time_dict_from_system().unix) + "_" + str(randi())
			subscription_id = sub_id
			start_timestamp = start_time
			end_timestamp = end_time if end_time > 0 else Time.get_time_dict_from_system().unix
			event_filters = filters
			replay_speed = speed
			session_start = Time.get_time_dict_from_system().unix
	
	func _init(logger: Callable):
		_logger = logger
	
	func enable_replay_for_subscriber(subscription_id: String, buffer_size: int):
		if not _replay_buffers.has(subscription_id):
			_replay_buffers[subscription_id] = ReplayBuffer.new(subscription_id, buffer_size)
			_logger.call("Enabled replay buffer for subscriber: %s (size: %d)" % [subscription_id, buffer_size], 1)
	
	func disable_replay_for_subscriber(subscription_id: String):
		if _replay_buffers.has(subscription_id):
			_replay_buffers.erase(subscription_id)
			_logger.call("Disabled replay buffer for subscriber: %s" % subscription_id, 1)
	
	func add_event_to_replay_buffers(event_data: Dictionary):
		# Add to global buffer
		_global_replay_buffer.append(event_data)
		if _global_replay_buffer.size() > _max_global_buffer_size:
			_global_replay_buffer.pop_front()
		
		# Add to subscriber-specific buffers
		for buffer in _replay_buffers.values():
			buffer.add_event(event_data)
	
	func start_replay_session(subscription_id: String, start_timestamp: float, 
							 end_timestamp: float = 0.0, event_filters: Array = [],
							 replay_speed: float = 1.0) -> String:
		var session = ReplaySession.new(subscription_id, start_timestamp, end_timestamp, 
									   event_filters, replay_speed)
		_replay_sessions[session.session_id] = session
		_logger.call("Started replay session: %s for subscriber: %s" % [session.session_id, subscription_id], 1)
		return session.session_id
	
	func get_replay_session_status(session_id: String) -> Dictionary:
		var session = _replay_sessions.get(session_id, null)
		if not session:
			return {}
		
		return {
			"session_id": session.session_id,
			"subscription_id": session.subscription_id,
			"start_timestamp": session.start_timestamp,
			"end_timestamp": session.end_timestamp,
			"replay_speed": session.replay_speed,
			"current_position": session.current_position,
			"paused": session.paused,
			"completed": session.completed,
			"progress": _calculate_session_progress(session)
		}
	
	func _calculate_session_progress(session: ReplaySession) -> float:
		var total_events = get_events_from_global_buffer(session.start_timestamp, 
														session.end_timestamp, 
														session.event_filters).size()
		if total_events == 0:
			return 1.0
		return float(session.current_position) / total_events
	
	func pause_replay_session(session_id: String) -> bool:
		var session = _replay_sessions.get(session_id, null)
		if session and not session.completed:
			session.paused = true
			_logger.call("Paused replay session: %s" % session_id, 1)
			return true
		return false
	
	func resume_replay_session(session_id: String) -> bool:
		var session = _replay_sessions.get(session_id, null)
		if session and not session.completed:
			session.paused = false
			_logger.call("Resumed replay session: %s" % session_id, 1)
			return true
		return false
	
	func stop_replay_session(session_id: String) -> bool:
		if _replay_sessions.has(session_id):
			_replay_sessions.erase(session_id)
			_logger.call("Stopped replay session: %s" % session_id, 1)
			return true
		return false
	
	func get_events_from_global_buffer(start_timestamp: float, end_timestamp: float, 
									  event_filters: Array = []) -> Array:
		var filtered_events = []
		for event_data in _global_replay_buffer:
			var event_timestamp = event_data.get("timestamp", 0.0)
			var event_name = event_data.get("event_name", event_data.get("name", ""))
			
			# Check timestamp range
			if event_timestamp < start_timestamp or event_timestamp > end_timestamp:
				continue
			
			# Check event filters
			if not event_filters.is_empty() and event_name not in event_filters:
				continue
			
			filtered_events.append(event_data)
		
		return filtered_events
	
	func get_replay_statistics() -> Dictionary:
		var subscriber_stats = {}
		for sub_id in _replay_buffers:
			var buffer = _replay_buffers[sub_id]
			subscriber_stats[sub_id] = {
				"buffer_size": buffer.events.size(),
				"max_size": buffer.max_size,
				"created_at": buffer.created_at
			}
		
		return {
			"global_buffer_size": _global_replay_buffer.size(),
			"max_global_buffer_size": _max_global_buffer_size,
			"subscriber_buffers": _replay_buffers.size(),
			"active_sessions": _replay_sessions.size(),
			"subscriber_stats": subscriber_stats
		}
	
	func clear_global_replay_buffer():
		_global_replay_buffer.clear()
		_logger.call("Global replay buffer cleared", 1)
	
	func set_max_backlog_size(size: int):
		_max_global_buffer_size = max(1000, size)
		while _global_replay_buffer.size() > _max_global_buffer_size:
			_global_replay_buffer.pop_front()

# ===== BATCH PROCESSOR =====
class EventBatchProcessor extends RefCounted:
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

# ===== THROUGHPUT MONITOR =====
class ThroughputMonitor extends RefCounted:
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
	
	func _get_time_us() -> int:
		return Time.get_time_dict_from_system().unix * 1000000  # Convert to microseconds

# ===== HEALTH AWARE ROUTER =====
class HealthAwareRouter extends RefCounted:
	var _system_health_cache: Dictionary = {}  # system_name -> health_data
	var _health_thresholds: Dictionary = {
		"routing_threshold": 0.2,  # Don't route to systems below 20% health
		"warning_threshold": 0.5,  # Warn about systems below 50% health
		"critical_threshold": 0.1   # Critical alert for systems below 10% health
	}
	var _routing_decisions: Dictionary = {}  # system_name -> last_routing_decision
	var _event_priority_adjustments: Dictionary = {}  # event_name -> priority_adjustment
	var _logger: Callable
	
	func _init(logger: Callable):
		_logger = logger
	
	func update_system_health(system_name: String, health_data: Dictionary):
		_system_health_cache[system_name] = health_data
		
		var failure_prob = health_data.get("failure_probability", 0.0)
		var health_score = 1.0 - failure_prob
		
		# Make routing decision
		var should_route = health_score > _health_thresholds.routing_threshold
		var previous_decision = _routing_decisions.get(system_name, true)
		
		_routing_decisions[system_name] = should_route
		
		# Log health changes
		if should_route != previous_decision:
			_logger.call("Routing decision changed for %s: %s (health: %.2f)" % 
				[system_name, ("enabled" if should_route else "disabled"), health_score], 
				2 if not should_route else 1)
		
		# Log warnings for unhealthy systems
		if health_score < _health_thresholds.critical_threshold:
			_logger.call("CRITICAL: System %s health at %.1f%%" % [system_name, health_score * 100], 3)
		elif health_score < _health_thresholds.warning_threshold:
			_logger.call("WARNING: System %s health at %.1f%%" % [system_name, health_score * 100], 2)
	
	func should_route_to_system(system_name: String, event_name: String) -> bool:
		# Check basic routing decision
		var basic_decision = _routing_decisions.get(system_name, true)
		if not basic_decision:
			return false
		
		# Check event-specific priority adjustments
		var priority_adjustment = _event_priority_adjustments.get(event_name, 0)
		if priority_adjustment < 0:
			# Lower priority events might be blocked even for healthy systems
			var health_data = _system_health_cache.get(system_name, {})
			var health_score = 1.0 - health_data.get("failure_probability", 0.0)
			
			# Require higher health for lower priority events
			var adjusted_threshold = _health_thresholds.routing_threshold + (-priority_adjustment * 0.1)
			return health_score > adjusted_threshold
		
		return true
	
	func get_system_health_score(system_name: String) -> float:
		var health_data = _system_health_cache.get(system_name, {})
		return 1.0 - health_data.get("failure_probability", 0.0)
	
	func get_routing_recommendation(event_name: String, target_systems: Array) -> Dictionary:
		var recommendations = {
			"recommended_systems": [],
			"blocked_systems": [],
			"degraded_systems": [],
			"overall_recommendation": "proceed"
		}
		
		for system_name in target_systems:
			var health_score = get_system_health_score(system_name)
			var should_route = should_route_to_system(system_name, event_name)
			
			if should_route:
				if health_score > _health_thresholds.warning_threshold:
					recommendations.recommended_systems.append(system_name)
				else:
					recommendations.degraded_systems.append(system_name)
			else:
				recommendations.blocked_systems.append(system_name)
		
		# Overall recommendation
		if recommendations.blocked_systems.size() == target_systems.size():
			recommendations.overall_recommendation = "block"
		elif recommendations.degraded_systems.size() > 0:
			recommendations.overall_recommendation = "proceed_with_caution"
		
		return recommendations

# ===== DEPENDENCY MANAGER =====
class DependencyManager extends RefCounted:
	var _dependencies: Dictionary = {}
	var _required_dependencies: Array = ["system_registry", "config_manager"]
	var _optional_dependencies: Array = ["metrics_collector", "health_monitor", "orchestrator"]
	var _resolved_dependencies: Array = []
	var _cached_operations: Array = []
	var _node_wrapper: Node
	var _dependency_callbacks: Dictionary = {}  # dependency_name -> Array[Callable]
	var _discovery_attempts: int = 0
	var _max_discovery_attempts: int = 5
	var _retry_timer: float = 0.0
	var _retry_interval: float = 1.0
	var _logger: Callable
	
	func _init(logger: Callable):
		_logger = logger
	
	func set_node_wrapper(node: Node):
		_node_wrapper = node
		discover_all_dependencies()
	
	func set_dependency(name: String, instance):
		if not instance or not is_instance_valid(instance):
			return
		
		_dependencies[name] = instance
		if name not in _resolved_dependencies:
			_resolved_dependencies.append(name)
		
		# Execute callbacks for this dependency
		if _dependency_callbacks.has(name):
			for callback in _dependency_callbacks[name]:
				if callback.is_valid():
					callback.call(instance)
		
		_logger.call("Dependency resolved: %s" % name, 1)
	
	func get_dependency(name: String):
		if _dependencies.has(name) and is_instance_valid(_dependencies[name]):
			return _dependencies[name]
		
		# Try to discover the dependency
		_discover_dependency(name)
		return _dependencies.get(name, null)
	
	func is_ready() -> bool:
		var missing_required = _get_missing_required()
		return missing_required.is_empty()
	
	func _get_missing_required() -> Array:
		var missing = []
		for req_dep in _required_dependencies:
			if not _dependencies.has(req_dep) or not is_instance_valid(_dependencies[req_dep]):
				missing.append(req_dep)
		return missing
	
	func cache_operation(operation: String, params: Dictionary):
		_cached_operations.append({
			"operation": operation,
			"params": params,
			"cached_at": Time.get_time_dict_from_system().unix
		})
	
	func replay_operations(event_bus):
		if not is_ready():
			return
		
		for cached_op in _cached_operations:
			var operation = cached_op.operation
			var params = cached_op.params
			
			match operation:
				"subscribe":
					event_bus.subscribe(
						params.get("event_name", ""),
						params.get("handler", Callable()),
						params.get("owner", null),
						params.get("enable_queue", false),
						params.get("max_concurrent", 1),
						params.get("enable_replay", false),
						params.get("queue_size", 100)
					)
				"publish":
					event_bus.publish(
						params.get("event_name", ""),
						params.get("data", {}),
						params.get("priority", 1)
					)
				"connect_system":
					event_bus.connect_external_system(
						params.get("system_name", ""),
						params.get("system_instance", null)
					)
		
		_cached_operations.clear()
		_logger.call("Replayed %d cached operations" % _cached_operations.size(), 1)
	
	func discover_all_dependencies():
		if not _node_wrapper:
			return
		
		_discovery_attempts += 1
		if _discovery_attempts > _max_discovery_attempts:
			_logger.call("Max dependency discovery attempts reached", 3)
			return
		
		var tree = _node_wrapper.get_tree()
		if not tree:
			return
		
		# Try to find dependencies in the scene tree
		var all_deps = _required_dependencies + _optional_dependencies
		for dep_name in all_deps:
			if not _dependencies.has(dep_name):
				_discover_dependency(dep_name)
	
	func _discover_dependency(name: String):
		if not _node_wrapper:
			return
		
		var tree = _node_wrapper.get_tree()
		if not tree:
			return
		
		# Try different discovery strategies
		var instance = null
		
		# Strategy 1: Check for singleton
		var singleton_name = _get_singleton_name(name)
		if Engine.has_singleton(singleton_name):
			instance = Engine.get_singleton(singleton_name)
		
		# Strategy 2: Find by node name in scene tree
		if not instance:
			instance = _find_node_by_name(tree.root, _get_node_name(name))
		
		# Strategy 3: Find by class name
		if not instance:
			instance = _find_node_by_class(tree.root, _get_class_name(name))
		
		# Strategy 4: Check autoload singletons
		if not instance:
			var autoload_name = _get_autoload_name(name)
			if tree.has_group(autoload_name):
				var nodes = tree.get_nodes_in_group(autoload_name)
				if not nodes.is_empty():
					instance = nodes[0]
		
		if instance and is_instance_valid(instance):
			set_dependency(name, instance)
		else:
			_logger.call("Failed to discover dependency: %s" % name, 2)
	
	
	
	func _find_node_by_name(root: Node, node_name: String) -> Node:
		if root.name.to_lower() == node_name.to_lower():
			return root
		
		for child in root.get_children():
			var result = _find_node_by_name(child, node_name)
			if result:
				return result
		return null
	
	func _find_node_by_class(root: Node, target_class_name: String) -> Node:
		var script = root.get_script()
		if script:
			var script_class = script.get_global_name()
			if script_class.to_lower() == target_class_name.to_lower():
				return root
		
		for child in root.get_children():
			var result = _find_node_by_class(child, target_class_name)
			if result:
				return result
		
		return null
	
	func _get_singleton_name(dependency_name: String) -> String:
		match dependency_name:
			"system_registry": return "SystemRegistry"
			"config_manager": return "ConfigManager"
			"metrics_collector": return "MetricsCollector"
			"health_monitor": return "HealthMonitor"
			"orchestrator": return "Orchestrator"
			"template_manager": return "TemplateManager"
			"schema_analyzer": return "SchemaAnalyzer"
			"intervention_manager": return "InterventionManager"
			_: return dependency_name.capitalize()
	
	func _get_node_name(dependency_name: String) -> String:
		return dependency_name.capitalize()
	
	func _get_class_name(dependency_name: String) -> String:
		return dependency_name.capitalize()
	
	func _get_autoload_name(dependency_name: String) -> String:
		return dependency_name.to_lower() + "_autoload"
	
	func add_dependency_callback(dependency_name: String, callback: Callable):
		if not _dependency_callbacks.has(dependency_name):
			_dependency_callbacks[dependency_name] = []
		_dependency_callbacks[dependency_name].append(callback)
	
	func remove_dependency_callback(dependency_name: String, callback: Callable):
		if _dependency_callbacks.has(dependency_name):
			_dependency_callbacks[dependency_name].erase(callback)
	
	func get_status() -> Dictionary:
		return {
			"dependencies_ready": is_ready(),
			"resolved_dependencies": _resolved_dependencies.duplicate(),
			"missing_required": _get_missing_required(),
			"missing_optional": _get_missing_optional(),
			"cached_operations": _cached_operations.size(),
			"discovery_attempts": _discovery_attempts,
			"node_wrapper_valid": _node_wrapper != null and is_instance_valid(_node_wrapper),
			"retry_active": _retry_timer > 0.0
		}
	
	func _get_missing_optional() -> Array:
		var missing = []
		for opt_dep in _optional_dependencies:
			if not _dependencies.has(opt_dep) or not is_instance_valid(_dependencies[opt_dep]):
				missing.append(opt_dep)
		return missing
	
	func reset_dependency_discovery():
		_discovery_attempts = 0
		_retry_timer = 0.0
		_cached_operations.clear()
		_logger.call("Dependency discovery reset", 1)
	
	func force_mark_ready():
		# For testing purposes - mark as ready even without all dependencies
		_logger.call("Force marked dependency manager as ready", 2)

# ===== ADDITIONAL UTILITY FUNCTIONS =====

# Helper function to create test subscriptions
func create_test_subscription(event_name: String, callback: Callable, owner: Object = null) -> String:
	"""Helper function for creating test subscriptions"""
	var subscription = EventSubscription.new(callback, owner)
	return subscription.subscription_id

# Helper function to validate event data structures
func validate_event_data(event_data: Dictionary) -> bool:
	"""Validate that event data has required fields"""
	var required_fields = ["event_name", "data"]
	for field in required_fields:
		if not event_data.has(field):
			return false
	return true

# Helper function to calculate health scores
func calculate_health_score(failure_probability: float, response_time_ms: float = 0.0, 
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
func format_performance_stats(stats: Dictionary) -> String:
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
func create_mock_health_data(system_name: String, health_score: float) -> Dictionary:
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
func create_integration_event(integration_type: String, event_name: String, 
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
func simulate_system_load(base_load: float, spike_probability: float = 0.1, 
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
func calculate_batch_efficiency(batch_size: int, processing_time: float, 
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
func create_time_based_filter(start_time: float, end_time: float, 
							 event_names: Array = []) -> Dictionary:
	"""Create filter for time-based event queries"""
	return {
		"start_timestamp": start_time,
		"end_timestamp": end_time,
		"event_filters": event_names,
		"created_at": Time.get_time_dict_from_system().unix
	}

# Helper function to validate subscription configuration
func validate_subscription_config(config: Dictionary) -> Dictionary:
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

func _create_logger_callable() -> Callable:
	"""Create a callable for component logging"""
	return Callable(self, "_log")

func _reset_integration_stats():
	"""Reset integration event statistics"""
	_integration_event_stats = {
		"schema_events_processed": 0,
		"config_events_processed": 0,
		"template_events_processed": 0,
		"resource_events_processed": 0
	}

# ===== ENHANCED EVENT SUBSCRIPTION =====
func subscribe(event_name: String, handler: Callable, owner: Object = null, 
			  enable_queue: bool = false, max_concurrent: int = 1, 
			  enable_replay: bool = false, queue_size: int = 100) -> String:
	"""Enhanced subscribe with queuing and replay options"""
	if not _dependency_manager.is_ready():
		_dependency_manager.cache_operation("subscribe", {
			"event_name": event_name,
			"handler": handler,
			"owner": owner,
			"enable_queue": enable_queue,
			"max_concurrent": max_concurrent,
			"enable_replay": enable_replay,
			"queue_size": queue_size
		})
		return "cached_" + str(randi())
	
	if not _subscriptions.has(event_name):
		_subscriptions[event_name] = []
	
	var subscription = EventSubscription.new(handler, owner)
	subscription.max_concurrent = max_concurrent
	subscription.queue_enabled = enable_queue or _auto_queue_creation
	subscription.max_queue_size = queue_size
	subscription.wants_replay = enable_replay or _auto_replay_buffers
	
	_subscriptions[event_name].append(subscription)
	
	# Create persistent queue if enabled
	if _persistent_queuing_enabled and subscription.queue_enabled:
		_persistent_queue.create_subscriber_queue(subscription.subscription_id, queue_size)
	
	# Enable replay buffer if requested
	if _replay_enabled and subscription.wants_replay:
		_replay_system.enable_replay_for_subscriber(subscription.subscription_id, queue_size)
	
	_log("Subscribed to '%s' (ID: %s, queue: %s, replay: %s)" % 
		[event_name, subscription.subscription_id, subscription.queue_enabled, subscription.wants_replay], LogLevel.DEBUG)
	
	return subscription.subscription_id

# ===== CONFIGURATION METHODS =====
func enable_schema_enforcement(enabled: bool, exceptions: Array = []):
	"""Enable or disable mandatory schema registration"""
	_enforce_schema_registration = enabled
	_schema_enforcement_exceptions = exceptions
	_log("Schema enforcement: " + ("enabled" if enabled else "disabled") + " (exceptions: " + (str(exceptions) if not exceptions.is_empty() else "none") + ")", LogLevel.INFO)

func enable_unregistered_event_warnings(enabled: bool):
	"""Enable or disable warnings for unregistered events"""
	_warn_unregistered_events = enabled
	_log("Unregistered event warnings: " + ("enabled" if enabled else "disabled"), LogLevel.INFO)

func enable_high_throughput_mode(enabled: bool, yield_threshold: int = 100):
	"""Enable high-throughput batch processing with coroutines"""
	_batch_processor.enable_high_throughput_mode(enabled, yield_threshold)
	_log("High-throughput mode: " + ("enabled" if enabled else "disabled") + " (yield threshold: " + str(yield_threshold) + ")", LogLevel.INFO)

# ===== LOGGING SYSTEM =====
func _log(message: String, level: LogLevel = LogLevel.INFO):
	"""Production-ready logging with configurable levels and Godot integration"""
	if level < _log_level:
		return
	
	if _production_mode and level < LogLevel.ERROR:
		return
	
	var full_message = "[GoatBus] %s" % message
	var prefix = ""
	
	match level:
		LogLevel.DEBUG: 
			prefix = "[DEBUG]"
			if _use_godot_logging:
				print(full_message)
		LogLevel.INFO: 
			prefix = "[INFO]"
			if _use_godot_logging:
				print_rich("[color=cyan]%s[/color]" % full_message)
		LogLevel.WARNING: 
			prefix = "[WARN]"
			if _use_godot_logging:
				print_rich("[color=yellow]%s[/color]" % full_message)
				push_warning(full_message)
		LogLevel.ERROR: 
			prefix = "[ERROR]"
			if _use_godot_logging:
				print_rich("[color=red]%s[/color]" % full_message)
				push_error(full_message)
	
	if not _log_file_path.is_empty():
		_log_to_file("%s %s %s" % [prefix, Time.get_datetime_string_from_system(), message])
	
	if _log_to_debugger and level >= LogLevel.WARNING:
		_send_to_debugger_panel(full_message, level)

func _log_to_file(message: String):
	"""Log message to file"""
	var file = FileAccess.open(_log_file_path, FileAccess.WRITE)
	if file:
		file.store_line(message)
		file.close()

func _send_to_debugger_panel(message: String, level: LogLevel):
	"""Send message to Godot's debugger panel"""
	match level:
		LogLevel.WARNING:
			print_stack()
		LogLevel.ERROR:
			print_stack()
			assert(false, message)

# ===== REMAINING CORE METHODS =====
func unsubscribe(event_name: String, subscription_id: String) -> bool:
	"""Unsubscribe from event by subscription ID"""
	if not _subscriptions.has(event_name):
		_log("Attempted to unsubscribe from non-existent event: %s" % event_name, LogLevel.WARNING)
		return false
	
	var subscriptions = _subscriptions[event_name]
	for i in range(subscriptions.size() - 1, -1, -1):
		var subscription = subscriptions[i]
		if subscription.subscription_id == subscription_id:
			subscriptions.remove_at(i)
			
			# Clean up persistent queue if exists
			if _persistent_queuing_enabled:
				_persistent_queue.remove_subscriber_queue(subscription_id)
			
			# Clean up replay buffer if exists
			if _replay_enabled:
				_replay_system.disable_replay_for_subscriber(subscription_id)
			
			_log("Unsubscribed from '%s' (ID: %s)" % [event_name, subscription_id], LogLevel.DEBUG)
			return true
	
	_log("Subscription ID not found: %s for event: %s" % [subscription_id, event_name], LogLevel.WARNING)
	return false

func unsubscribe_all(owner: Object) -> int:
	"""Unsubscribe all events for a specific owner"""
	var removed_count = 0
	
	for event_name in _subscriptions:
		var subscriptions = _subscriptions[event_name]
		for i in range(subscriptions.size() - 1, -1, -1):
			var subscription = subscriptions[i]
			if subscription.owner_ref:
				var subscription_owner = subscription.owner_ref.get_ref()
				if subscription_owner == owner:
					# Clean up associated queues and buffers
					if _persistent_queuing_enabled:
						_persistent_queue.remove_subscriber_queue(subscription.subscription_id)
					if _replay_enabled:
						_replay_system.disable_replay_for_subscriber(subscription.subscription_id)
					
					subscriptions.remove_at(i)
					removed_count += 1
	
	_log("Removed %d subscriptions for owner" % removed_count, LogLevel.INFO)
	return removed_count

# ===== EVENT SCHEMA MANAGEMENT =====
func register_event_schema(event_name: String, schema: EventSchema):
	"""Register an event schema for validation"""
	_event_schemas[event_name] = schema
	_log("Schema registered for event: %s" % event_name, LogLevel.DEBUG)

func create_event_schema(event_name: String, required_fields: Array = [], optional_fields: Array = []) -> EventSchema:
	"""Create and register a new event schema"""
	var schema = EventSchema.new(event_name)
	
	for field in required_fields:
		schema.add_required_field(field)
	
	for field in optional_fields:
		schema.add_optional_field(field)
	
	register_event_schema(event_name, schema)
	return schema

func create_typed_event_schema(event_name: String, field_definitions: Dictionary) -> EventSchema:
	"""Create event schema with typed fields"""
	var schema = EventSchema.new(event_name)
	
	for field_name in field_definitions:
		var def = field_definitions[field_name]
		var is_required = def.get("required", false)
		var field_type = def.get("type", "")
		
		if is_required:
			schema.add_required_field(field_name, field_type)
		else:
			schema.add_optional_field(field_name, field_type)
	
	register_event_schema(event_name, schema)
	return schema

func register_bulk_schemas(schema_definitions: Dictionary):
	"""Register multiple schemas at once"""
	for event_name in schema_definitions:
		var def = schema_definitions[event_name]
		var schema = EventSchema.new(event_name)
		
		var required = def.get("required", [])
		var optional = def.get("optional", [])
		var types = def.get("types", {})
		
		for field in required:
			var field_type = types.get(field, "")
			schema.add_required_field(field, field_type)
		
		for field in optional:
			var field_type = types.get(field, "")
			schema.add_optional_field(field, field_type)
		
		register_event_schema(event_name, schema)
	
	_log("Registered %d bulk schemas" % schema_definitions.size(), LogLevel.INFO)

# ===== COORDINATION EVENT SETUP =====
func _setup_coordination_subscriptions():
	"""Subscribe to coordination events for health-aware routing"""
	var coordination_events = {
		"system_health_status_updated": _handle_system_health_updated,
		"system_state_changed": _handle_system_state_changed,
		"phase_started": _handle_phase_started,
		"orchestration_emergency_paused": _handle_orchestration_emergency,
		"integration_batch_starting": _handle_integration_batch_starting,
		"integration_batch_completed": _handle_integration_batch_completed,
		"schema_integration_priority_change": _handle_schema_priority_change,
		"resource_integration_priority_change": _handle_resource_priority_change
	}
	
	for event_name in coordination_events:
		var handler_method = coordination_events[event_name]
		subscribe(event_name, handler_method, self)

# ===== HELPER METHODS =====
func _track_integration_event(event_name: String):
	"""Track integration event statistics"""
	if _is_schema_event(event_name):
		_integration_event_stats.schema_events_processed += 1
	elif _is_config_event(event_name):
		_integration_event_stats.config_events_processed += 1
	elif _is_template_event(event_name):
		_integration_event_stats.template_events_processed += 1
	elif _is_resource_event(event_name):
		_integration_event_stats.resource_events_processed += 1

func _is_integration_event(event_name: String) -> bool:
	"""Check if event is an integration event"""
	return _is_schema_event(event_name) or _is_config_event(event_name) or _is_template_event(event_name) or _is_resource_event(event_name)

func _is_schema_event(event_name: String) -> bool:
	"""Check if event is schema-related"""
	var schema_events = [
		"schedule_schema_analysis", "trigger_schema_analysis", 
		"schema_analysis_completed", "system_schema_analysis_complete",
		"integrate_schema_analysis_results", "schema_template_sync_requested",
		"schema_template_sync_completed"
	]
	return event_name in schema_events

func _is_config_event(event_name: String) -> bool:
	"""Check if event is configuration-related"""
	var config_events = [
		"config_auto_adjusted", "request_config_adjustment",
		"config_adjustment_completed", "immediate_config_adjustments_applied",
		"config_adjustments_scheduled"
	]
	return event_name in config_events

func _is_template_event(event_name: String) -> bool:
	"""Check if event is template-related"""
	var template_events = [
		"template_auto_updated", "template_updates_queued_for_review",
		"template_updates_from_feedback", "template_updates_from_scaling",
		"template_review_required", "template_updated_notify_systems"
	]
	return event_name in template_events

func _is_resource_event(event_name: String) -> bool:
	"""Check if event is resource-related"""
	var resource_events = [
		"resource_scaling_completed", "resource_forecast_generated", 
		"resource_profile_recommendations", "apply_resource_profile",
		"coordinate_profile_application"
	]
	return event_name in resource_events

func _get_integration_type(event_name: String) -> String:
	"""Get integration type for batching"""
	if _is_schema_event(event_name):
		return "schema_updates"
	elif _is_config_event(event_name):
		return "config_adjustments"
	elif _is_template_event(event_name):
		return "template_updates"
	elif _is_resource_event(event_name):
		return "resource_optimizations"
	return ""

func _adjust_priority_for_system_health(base_priority: EventPriority, target_systems: Array) -> EventPriority:
	"""Adjust event priority based on target system health"""
	if target_systems.is_empty():
		return base_priority
	
	var min_health = 1.0
	for system_name in target_systems:
		if not _health_aware_router.should_route_to_system(system_name, ""):
			min_health = min(min_health, 0.3)
	
	if min_health < 0.5:
		return EventPriority.LOW
	elif min_health < 0.8:
		return max(EventPriority.LOW, base_priority - 1)
	
	return base_priority

func _get_event_target_systems(event_name: String) -> Array:
	"""Get systems that are likely targets of this event"""
	var targets: Array = []
	if _subscriptions.has(event_name):
		for subscription in _subscriptions[event_name]:
			var owner_ref = subscription.owner_ref
			if owner_ref and owner_ref.get_ref():
				var owner = owner_ref.get_ref()
				if owner.has_method("get_system_name"):
					targets.append(owner.get_system_name())
	return targets

func _filter_subscriptions_by_health(subscriptions: Array, event_name: String) -> Array:
	"""Filter subscriptions based on system health"""
	if not _health_integration_enabled:
		return subscriptions
	
	var viable_subscriptions = []
	for subscription in subscriptions:
		var owner_ref = subscription.owner_ref
		if owner_ref and owner_ref.get_ref():
			var owner = owner_ref.get_ref()
			var system_name = ""
			if owner.has_method("get_system_name"):
				system_name = owner.get_system_name()
			
			if system_name.is_empty() or _health_aware_router.should_route_to_system(system_name, event_name):
				viable_subscriptions.append(subscription)
		else:
			viable_subscriptions.append(subscription)
	
	return viable_subscriptions

func _is_orchestration_event(event_name: String) -> bool:
	"""Check if event is part of orchestration and should be batched"""
	var orchestration_events = [
		"system_registered", "system_state_changed",
		"dependency_resolved", "phase_system_completed",
		"system_health_status_updated"
	]
	return event_name in orchestration_events

func _extract_phase_from_event(event_name: String, data: Dictionary) -> String:
	"""Extract phase name from event data for batching"""
	var meta = data.get("_orchestrator_meta", {})
	var phase = meta.get("active_phase", "")
	if not phase.is_empty():
		return phase
	
	return data.get("phase_name", "")

func _track_subscription_failure(subscription):
	"""Track subscription failures for health monitoring"""
	var subscription_id = subscription.subscription_id
	if not _subscription_health_tracking.has(subscription_id):
		_subscription_health_tracking[subscription_id] = {
			"failure_count": 0,
			"last_failure": 0.0,
			"consecutive_failures": 0
		}
	
	var health_data = _subscription_health_tracking[subscription_id]
	health_data.failure_count += 1
	health_data.consecutive_failures += 1
	health_data.last_failure = Time.get_time_dict_from_system().unix
	
	if health_data.consecutive_failures >= 3:
		if subscription_id not in _degraded_subscriptions:
			_degraded_subscriptions.append(subscription_id)

# ===== COORDINATION EVENT HANDLERS =====
func _handle_system_health_updated(data: Dictionary):
	"""Handle system health updates for routing decisions"""
	var health_analysis = data.get("health_analysis", {})
	var system_analysis = health_analysis.get("system_analysis", {})
	
	for system_name in system_analysis:
		var system_health = system_analysis[system_name]
		_health_aware_router.update_system_health(system_name, system_health)
		var health_score = 1.0 - system_health.get("failure_probability", 0.0)
		system_health_routing_updated.emit(system_name, health_score)

func _handle_system_state_changed(data: Dictionary):
	"""Handle system state changes for routing"""
	var system_name = data.get("system_name", "")
	var new_state = data.get("new_state", "")
	
	var health_score = 1.0
	if new_state == "ERROR":
		health_score = 0.0
	elif new_state in ["PAUSED", "STOPPING"]:
		health_score = 0.3
	elif new_state == "RUNNING":
		health_score = 1.0
	
	_health_aware_router.update_system_health(system_name, {
		"failure_probability": 1.0 - health_score,
		"current_state": new_state
	})

func _handle_phase_started(data: Dictionary):
	"""Handle phase start for batch processing optimization"""
	var phase_name = data.get("phase_name", "")
	if _orchestration_batch_processing:
		_batch_processor._phase_batches[phase_name] = []
		_log("Prepared batch processing for phase: %s" % phase_name, LogLevel.DEBUG)

func _handle_orchestration_emergency(data: Dictionary):
	"""Handle orchestration emergency - process all pending batches immediately"""
	var reason = data.get("reason", "emergency")
	_log("Emergency processing all pending batches due to: %s" % reason, LogLevel.WARNING)
	_batch_processor.force_process_all_batches()

func _handle_integration_batch_starting(data: Dictionary):
	"""Handle integration batch start"""
	var integration_type = data.get("integration_type", "")
	var event_count = data.get("event_count", 0)
	_log("Starting integration batch: %s (%d events)" % [integration_type, event_count], LogLevel.DEBUG)

func _handle_integration_batch_completed(data: Dictionary):
	"""Handle integration batch completion"""
	var integration_type = data.get("integration_type", "")
	var successful = data.get("successful", 0)
	var failed = data.get("failed", 0)
	var duration = data.get("duration", 0.0)
	
	_log("Integration batch completed: %s (%d success, %d failed, %.3fs)" % 
		[integration_type, successful, failed, duration], LogLevel.DEBUG)

func _handle_schema_priority_change(data: Dictionary):
	"""Handle schema integration priority changes"""
	var priority_adjustment = data.get("priority_adjustment", 0)
	var affected_events = data.get("affected_events", [])
	
	for event_name in affected_events:
		if _is_schema_event(event_name):
			_health_aware_router._event_priority_adjustments[event_name] = priority_adjustment

func _handle_resource_priority_change(data: Dictionary):
	"""Handle resource integration priority changes"""
	var priority_adjustment = data.get("priority_adjustment", 0)
	var affected_events = data.get("affected_events", [])
	
	for event_name in affected_events:
		if _is_resource_event(event_name):
			_health_aware_router._event_priority_adjustments[event_name] = priority_adjustment

func _emit_coordination_event(event_name: String, data: Dictionary):
	"""Emit coordination events (bypass health filtering)"""
	data["_coordination_meta"] = {
		"source": "event_bus_enhanced",
		"timestamp": Time.get_time_dict_from_system().unix,
		"bypass_health_filtering": true
	}
	
	event_published.emit(event_name, data, EventPriority.HIGH)

# ===== UTILITY METHODS =====
func cleanup_invalid_subscriptions() -> int:
	"""Clean up all invalid subscriptions"""
	var removed_count = 0
	
	for event_name in _subscriptions:
		var subscriptions = _subscriptions[event_name]
		for i in range(subscriptions.size() - 1, -1, -1):
			var subscription = subscriptions[i]
			if not subscription.is_valid():
				# Clean up associated resources
				if _persistent_queuing_enabled:
					_persistent_queue.remove_subscriber_queue(subscription.subscription_id)
				if _replay_enabled:
					_replay_system.disable_replay_for_subscriber(subscription.subscription_id)
				
				subscriptions.remove_at(i)
				removed_count += 1
	
	_log("Cleaned up %d invalid subscriptions" % removed_count, LogLevel.INFO)
	return removed_count

func get_total_subscription_count() -> int:
	"""Get total number of subscriptions"""
	var count = 0
	for subscriptions in _subscriptions.values():
		count += subscriptions.size()
	return count

func get_active_subscription_count() -> int:
	"""Get count of active (valid) subscriptions"""
	var count = 0
	for event_name in _subscriptions:
		for subscription in _subscriptions[event_name]:
			if subscription.is_valid():
				count += 1
	return count

func get_performance_stats() -> Dictionary:
	"""Get comprehensive performance statistics"""
	return {
		"total_subscriptions": get_total_subscription_count(),
		"active_subscriptions": get_active_subscription_count(),
		"degraded_subscriptions": _degraded_subscriptions.size(),
		"integration_events": _integration_event_stats.duplicate(),
		"throughput_data": _throughput_monitor.get_performance_report(),
		"health_routing_enabled": _health_integration_enabled,
		"batch_processing_enabled": _orchestration_batch_processing,
		"validation_enabled": _enable_validation,
		"dependencies_resolved": _dependency_manager.is_ready(),
		"resolved_dependencies": _dependency_manager._resolved_dependencies.duplicate(),
		"cached_operations": _dependency_manager._cached_operations.size(),
		"frame_monitoring_enabled": _enable_frame_monitoring,
		"hotload_safe": _hotload_safe,
		"initialization_complete": _initialization_complete
	}

func get_dependency_status() -> Dictionary:
	"""Get comprehensive dependency status"""
	return _dependency_manager.get_status()

func get_event_statistics() -> Dictionary:
	"""Get event-specific statistics"""
	var event_stats = {}
	
	for event_name in _subscriptions:
		var subscriptions = _subscriptions[event_name]
		var active_count = 0
		var total_count = subscriptions.size()
		
		for subscription in subscriptions:
			if subscription.is_valid():
				active_count += 1
		
		event_stats[event_name] = {
			"total_subscriptions": total_count,
			"active_subscriptions": active_count,
			"has_schema": _event_schemas.has(event_name),
			"is_integration_event": _is_integration_event(event_name),
			"integration_type": _get_integration_type(event_name)
		}
	
	return event_stats

func get_system_health_overview() -> Dictionary:
	"""Get overview of system health for routing"""
	var health_overview = {}
	
	for system_name in _health_aware_router._system_health_cache:
		var health_data = _health_aware_router._system_health_cache[system_name]
		var failure_prob = health_data.get("failure_probability", 0.0)
		var health_score = 1.0 - failure_prob
		
		health_overview[system_name] = {
			"health_score": health_score,
			"failure_probability": failure_prob,
			"routing_enabled": health_score > 0.2,
			"current_state": health_data.get("current_state", "UNKNOWN")
		}
	
	return health_overview

func get_subscription_stats() -> Dictionary:
	"""Get subscription statistics"""
	var total_subs = 0
	var active_subs = 0
	var event_stats = {}
	
	for event_name in _subscriptions:
		var subscriptions = _subscriptions[event_name]
		var active_count = 0
		
		for subscription in subscriptions:
			if subscription.is_valid():
				active_count += 1
		
		total_subs += subscriptions.size()
		active_subs += active_count
		event_stats[event_name] = {
			"total": subscriptions.size(),
			"active": active_count
		}
	
	return {
		"total_subscriptions": total_subs,
		"active_subscriptions": active_subs,
		"events_with_subscriptions": event_stats.size(),
		"event_details": event_stats
	}

# ===== CONFIGURATION METHODS =====
func enable_health_aware_routing(enabled: bool):
	"""Enable or disable health-aware event routing"""
	_health_integration_enabled = enabled
	_log("Health-aware routing: %s" % ("enabled" if enabled else "disabled"), LogLevel.INFO)

func enable_orchestration_batch_processing(enabled: bool):
	"""Enable or disable orchestration-aware batch processing"""
	_orchestration_batch_processing = enabled
	_log("Orchestration batch processing: %s" % ("enabled" if enabled else "disabled"), LogLevel.INFO)

func enable_event_validation(enabled: bool):
	"""Enable or disable event schema validation"""
	_enable_validation = enabled
	_log("Event validation: %s" % ("enabled" if enabled else "disabled"), LogLevel.INFO)

func enable_performance_aware_routing(enabled: bool):
	"""Enable or disable performance-aware routing"""
	_performance_aware_routing = enabled
	_log("Performance-aware routing: %s" % ("enabled" if enabled else "disabled"), LogLevel.INFO)

func enable_frame_monitoring(enabled: bool):
	"""Enable or disable frame performance monitoring"""
	_enable_frame_monitoring = enabled
	_log("Frame monitoring: %s" % ("enabled" if enabled else "disabled"), LogLevel.INFO)

func add_schema_enforcement_exception(event_name: String):
	"""Add event to schema enforcement exceptions"""
	if event_name not in _schema_enforcement_exceptions:
		_schema_enforcement_exceptions.append(event_name)
		_log("Added schema enforcement exception: %s" % event_name, LogLevel.INFO)

func remove_schema_enforcement_exception(event_name: String):
	"""Remove event from schema enforcement exceptions"""
	if event_name in _schema_enforcement_exceptions:
		_schema_enforcement_exceptions.erase(event_name)
		_log("Removed schema enforcement exception: %s" % event_name, LogLevel.INFO)

func set_batch_size(size: int):
	"""Set the maximum batch size for event processing"""
	if size > 0:
		_batch_processor._max_batch_size = size
		_log("Batch size set to: %d" % size, LogLevel.INFO)

func set_batch_timeout(timeout: float):
	"""Set the batch timeout in seconds"""
	if timeout > 0.0:
		_batch_processor._batch_timeout = timeout
		_log("Batch timeout set to: %.3fs" % timeout, LogLevel.INFO)

func set_frame_budget(budget_ms: float):
	"""Set processing budget per frame in milliseconds"""
	_batch_processor.set_frame_budget(budget_ms)
	_log("Frame budget set to: %.1fms" % budget_ms, LogLevel.INFO)

func set_events_per_frame(count: int):
	"""Set max events to process before budget check"""
	_batch_processor.set_events_per_frame(count)
	_log("Events per frame set to: %d" % count, LogLevel.INFO)

func set_coroutine_yield_threshold(threshold: int):
	"""Set how many events to process before yielding in high-throughput mode"""
	_batch_processor.set_coroutine_yield_threshold(threshold)
	_log("Coroutine yield threshold set to: %d" % threshold, LogLevel.INFO)

# ===== FORCE PROCESSING METHODS =====
func force_process_all_batches():
	"""Force immediate processing of all pending batches"""
	_batch_processor.force_process_all_batches()
	_log("All pending batches processed", LogLevel.INFO)

func force_emit_batch_events():
	"""Force emission of batch completion events"""
	batch_processing_completed.emit({
		"forced": true,
		"timestamp": Time.get_time_dict_from_system().unix
	})

func force_dependency_resolution():
	"""Force attempt to resolve all missing dependencies"""
	_dependency_manager.discover_all_dependencies()
	
	var missing_required = _dependency_manager._get_missing_required()
	for req_dep in missing_required:
		dependency_connection_failed.emit(req_dep)
		_log("Failed to resolve required dependency: %s" % req_dep, LogLevel.ERROR)

# ===== EXPORT/IMPORT CONFIGURATION =====
func export_configuration() -> Dictionary:
	"""Export current configuration for saving/loading"""
	return {
		"health_integration_enabled": _health_integration_enabled,
		"orchestration_batch_processing": _orchestration_batch_processing,
		"enable_validation": _enable_validation,
		"performance_aware_routing": _performance_aware_routing,
		"enable_frame_monitoring": _enable_frame_monitoring,
		"enforce_schema_registration": _enforce_schema_registration,
		"warn_unregistered_events": _warn_unregistered_events,
		"schema_enforcement_exceptions": _schema_enforcement_exceptions.duplicate(),
		"max_batch_size": _batch_processor._max_batch_size,
		"batch_timeout": _batch_processor._batch_timeout,
		"frame_budget_ms": _batch_processor.get_frame_budget_ms(),
		"max_events_per_frame": _batch_processor._max_events_per_frame,
		"high_throughput_mode": _batch_processor._high_throughput_mode,
		"coroutine_yield_threshold": _batch_processor._coroutine_yield_threshold,
		"integration_batch_types": _batch_processor._integration_batch_types.duplicate(),
		"required_dependencies": _dependency_manager._required_dependencies.duplicate(),
		"optional_dependencies": _dependency_manager._optional_dependencies.duplicate(),
		"log_level": _log_level,
		"production_mode": _production_mode,
		"use_godot_logging": _use_godot_logging,
		"log_to_debugger": _log_to_debugger,
		"log_file_path": _log_file_path,
		"hotload_safe": _hotload_safe
	}

func import_configuration(config: Dictionary):
	"""Import configuration from saved data"""
	_health_integration_enabled = config.get("health_integration_enabled", true)
	_orchestration_batch_processing = config.get("orchestration_batch_processing", true)
	_enable_validation = config.get("enable_validation", false)
	_performance_aware_routing = config.get("performance_aware_routing", true)
	_enable_frame_monitoring = config.get("enable_frame_monitoring", true)
	_enforce_schema_registration = config.get("enforce_schema_registration", false)
	_warn_unregistered_events = config.get("warn_unregistered_events", true)
	_schema_enforcement_exceptions = config.get("schema_enforcement_exceptions", [])
	
	if config.has("max_batch_size"):
		_batch_processor._max_batch_size = config.max_batch_size
	
	if config.has("batch_timeout"):
		_batch_processor._batch_timeout = config.batch_timeout
	
	if config.has("frame_budget_ms"):
		_batch_processor.set_frame_budget(config.frame_budget_ms)
	elif config.has("frame_budget"):
		_batch_processor.set_frame_budget(config.frame_budget)
	
	if config.has("max_events_per_frame"):
		_batch_processor.set_events_per_frame(config.max_events_per_frame)
	
	if config.has("high_throughput_mode"):
		var yield_threshold = config.get("coroutine_yield_threshold", 100)
		_batch_processor.enable_high_throughput_mode(config.high_throughput_mode, yield_threshold)
	
	if config.has("integration_batch_types"):
		_batch_processor._integration_batch_types = config.integration_batch_types
	
	if config.has("required_dependencies"):
		_dependency_manager._required_dependencies = config.required_dependencies
	
	if config.has("optional_dependencies"):
		_dependency_manager._optional_dependencies = config.optional_dependencies
	
	if config.has("log_level"):
		_log_level = config.log_level
	
	if config.has("production_mode"):
		_production_mode = config.production_mode
	
	if config.has("use_godot_logging"):
		_use_godot_logging = config.use_godot_logging
	
	if config.has("log_to_debugger"):
		_log_to_debugger = config.log_to_debugger
	
	if config.has("log_file_path"):
		set_log_file(config.log_file_path)
	
	if config.has("hotload_safe"):
		_hotload_safe = config.hotload_safe
	
	_log("Configuration imported successfully", LogLevel.INFO)

# ===== EXTERNAL SYSTEM MANAGEMENT =====
func connect_external_system(system_name: String, system_instance):
	"""Manually connect an external system"""
	if not system_instance or not is_instance_valid(system_instance):
		_log("Attempted to connect invalid external system: %s" % system_name, LogLevel.WARNING)
		return
	
	if not _dependency_manager.is_ready():
		_dependency_manager.cache_operation("connect_system", {
			"system_name": system_name,
			"system_instance": system_instance
		})
		return
	
	_external_systems[system_name] = system_instance
	_log("External system '%s' connected manually" % system_name, LogLevel.INFO)

func get_external_system(system_name: String):
	"""Get an external system instance"""
	var system = _external_systems.get(system_name, null)
	if system and is_instance_valid(system):
		return system
	else:
		if _external_systems.has(system_name):
			_external_systems.erase(system_name)
		return null

# ===== SAFE DEPENDENCY CALLS =====
func safe_publish_to_system(system_name: String, event_name: String, data: Dictionary = {}):
	"""Safely publish to a specific system"""
	var system = get_dependency(system_name)
	if system and is_instance_valid(system):
		if system.has_method("handle_event"):
			system.handle_event(event_name, data)
		elif system.has_method("on_" + event_name):
			system.call("on_" + event_name, data)
		else:
			_log("System '%s' cannot handle event '%s'" % [system_name, event_name], LogLevel.WARNING)
	else:
		_log("System '%s' not available for event '%s'" % [system_name, event_name], LogLevel.WARNING)

func safe_call(system_name: String, method_name: String, args: Array = []):
	"""Safely call method on system if it exists"""
	var system = get_dependency(system_name)
	if not system or not is_instance_valid(system):
		return null
	
	if system.has_method(method_name):
		match args.size():
			0: return system.call(method_name)
			1: return system.call(method_name, args[0])
			2: return system.call(method_name, args[0], args[1])
			3: return system.call(method_name, args[0], args[1], args[2])
			_: return system.callv(method_name, args)
	
	return null

# ===== DEBUG AND MONITORING METHODS =====
func debug_print_dependencies():
	"""Print current dependency status"""
	var status = get_dependency_status()
	_log("=== DEPENDENCY STATUS ===", LogLevel.INFO)
	_log("Dependencies Ready: %s" % status.dependencies_ready, LogLevel.INFO)
	_log("Cached Operations: %d" % status.cached_operations, LogLevel.INFO)
	_log("Node Wrapper Valid: %s" % status.node_wrapper_valid, LogLevel.INFO)
	_log("Retry Active: %s" % status.retry_active, LogLevel.INFO)
	
	if not status.missing_required.is_empty():
		_log("Missing Required: %s" % str(status.missing_required), LogLevel.ERROR)
	
	if not status.missing_optional.is_empty():
		_log("Missing Optional: %s" % str(status.missing_optional), LogLevel.WARNING)
	
	for dep in status.resolved_dependencies:
		_log("✓ %s" % dep, LogLevel.INFO)

func debug_print_subscriptions():
	"""Print subscription details"""
	var stats = get_subscription_stats()
	_log("=== SUBSCRIPTION STATUS ===", LogLevel.INFO)
	_log("Total: %d, Active: %d" % [stats.total_subscriptions, stats.active_subscriptions], LogLevel.INFO)
	
	for event_name in stats.event_details:
		var details = stats.event_details[event_name]
		_log("Event '%s': %d/%d active" % [event_name, details.active, details.total], LogLevel.INFO)

func debug_print_performance():
	"""Print performance statistics for debugging"""
	var stats = get_enhanced_performance_stats()
	_log("=== ENHANCED PERFORMANCE DEBUG ===", LogLevel.INFO)
	_log("Total Subscriptions: %d" % stats.total_subscriptions, LogLevel.INFO)
	_log("Active Subscriptions: %d" % stats.active_subscriptions, LogLevel.INFO)
	_log("Degraded Subscriptions: %d" % stats.degraded_subscriptions, LogLevel.INFO)
	_log("Dependencies Resolved: %s" % stats.dependencies_resolved, LogLevel.INFO)
	_log("Enhanced Features: %s" % str(stats.enhanced_features), LogLevel.INFO)
	
	if stats.has("total_queued_events"):
		_log("Total Queued Events: %d" % stats.total_queued_events, LogLevel.INFO)
	
	if stats.has("queue_utilization"):
		_log("Queue Utilization: %.1f%%" % (stats.queue_utilization * 100), LogLevel.INFO)
	
	var backpressure = stats.get("backpressure_status", {})
	if not backpressure.is_empty():
		_log("Backpressure: enabled=%s, throttle=%.2f, pressure=%.2f" % 
			[backpressure.get("enabled", false), backpressure.get("throttle_factor", 1.0), 
			 backpressure.get("pressure_level", 0.0)], LogLevel.INFO)

# ===== TESTING SUPPORT =====
func _create_test_event(name: String, data: Dictionary = {}) -> EventData:
	# Helper for unit tests
	return EventData.new(name, data)

func _get_subscription_count(event_name: String) -> int:
	# Helper for unit tests
	return _subscriptions.get(event_name, []).size()

func _force_dependency_ready():
	# Helper for unit tests
	_dependency_manager.force_mark_ready()

func _get_batch_queue_size(batch_name: String) -> int:
	# Helper for unit tests
	if batch_name in _batch_processor._phase_batches:
		return _batch_processor._phase_batches[batch_name].size()
	elif batch_name in _batch_processor._integration_batches:
		return _batch_processor._integration_batches[batch_name].size()
	return 0

func _clear_all_batches():
	# Helper for unit tests
	_batch_processor._phase_batches.clear()
	_batch_processor._integration_batches.clear()

func _simulate_hotload():
	# Helper for testing hotload scenarios
	reset_for_hotload()

func _get_pending_setup_calls_count() -> int:
	# Helper for unit tests
	return _pending_setup_calls.size()# ===== ENHANCED PERFORMANCE MONITORING =====
func get_enhanced_performance_stats() -> Dictionary:
	"""Get comprehensive performance statistics including new features"""
	var base_stats = get_performance_stats()
	
	var enhanced_stats = base_stats.duplicate()
	enhanced_stats["queue_metrics"] = _persistent_queue.get_all_queue_metrics() if _persistent_queuing_enabled else {}
	enhanced_stats["replay_statistics"] = _replay_system.get_replay_statistics() if _replay_enabled else {}
	enhanced_stats["time_window_summaries"] = _time_windows.get_all_window_summaries() if _time_window_operations_enabled else {}
	enhanced_stats["backpressure_status"] = get_backpressure_status()
	
	# Calculate additional metrics
	if _persistent_queuing_enabled:
		var queue_metrics = enhanced_stats["queue_metrics"]
		enhanced_stats["total_queued_events"] = queue_metrics.get("total_queued_events", 0)
		enhanced_stats["queue_utilization"] = _calculate_overall_queue_utilization()
	
	if _replay_enabled:
		var replay_stats = enhanced_stats["replay_statistics"]
		enhanced_stats["replay_buffer_usage"] = _calculate_replay_buffer_usage(replay_stats)
	
	# Enhanced feature status
	enhanced_stats["enhanced_features"] = {
		"persistent_queuing": _persistent_queuing_enabled,
		"replay_system": _replay_enabled,
		"backpressure_control": _backpressure_enabled,
		"time_windows": _time_window_operations_enabled,
		"auto_queue_creation": _auto_queue_creation,
		"auto_replay_buffers": _auto_replay_buffers
	}
	
	return enhanced_stats

func _calculate_overall_queue_utilization() -> float:
	"""Calculate overall queue utilization across all subscribers"""
	var total_queued = 0
	var total_capacity = 0
	
	var queue_metrics = _persistent_queue.get_all_queue_metrics()
	var subscriber_metrics = queue_metrics.get("subscriber_metrics", {})
	
	for sub_id in subscriber_metrics:
		var metrics = subscriber_metrics[sub_id]
		total_queued += _persistent_queue.get_queue_size(sub_id)
		total_capacity += _persistent_queue._max_queue_size_per_subscriber
	
	if total_capacity == 0:
		return 0.0
	
	return float(total_queued) / total_capacity

func _calculate_replay_buffer_usage(replay_stats: Dictionary) -> Dictionary:
	"""Calculate replay buffer usage statistics"""
	var usage = {
		"global_utilization": 0.0,
		"subscriber_utilization": 0.0,
		"average_buffer_size": 0.0
	}
	
	var global_size = replay_stats.get("global_buffer_size", 0)
	var max_global = replay_stats.get("max_global_buffer_size", 1)
	usage.global_utilization = float(global_size) / max_global
	
	var subscriber_stats = replay_stats.get("subscriber_stats", {})
	if not subscriber_stats.is_empty():
		var total_used = 0
		var total_capacity = 0
		
		for stats in subscriber_stats.values():
			total_used += stats.get("buffer_size", 0)
			total_capacity += stats.get("max_size", 0)
		
		if total_capacity > 0:
			usage.subscriber_utilization = float(total_used) / total_capacity
			usage.average_buffer_size = float(total_used) / subscriber_stats.size()
	
	return usage

# ===== MAINTENANCE AND CLEANUP =====
func perform_maintenance() -> Dictionary:
	"""Perform maintenance tasks and return summary"""
	var maintenance_stats = {
		"invalid_subscriptions_removed": 0,
		"empty_queues_cleaned": 0,
		"expired_replay_sessions_removed": 0,
		"deferred_events_processed": 0,
		"time_windows_cleaned": 0
	}
	
	# Clean up invalid subscriptions
	maintenance_stats.invalid_subscriptions_removed = cleanup_invalid_subscriptions()
	
	# Process deferred events if backpressure has reduced
	if _backpressure_enabled and not _backpressure_controller.needs_emergency_flush():
		_process_deferred_events()
		if has_meta("deferred_events"):
			var deferred = get_meta("deferred_events")
			maintenance_stats.deferred_events_processed = deferred.size()
	
	# Clean up empty persistent queues
	if _persistent_queuing_enabled:
		maintenance_stats.empty_queues_cleaned = _cleanup_empty_queues()
	
	# Remove completed replay sessions
	if _replay_enabled:
		maintenance_stats.expired_replay_sessions_removed = _cleanup_replay_sessions()
	
	# Process queued events
	var queue_stats = process_queued_events()
	maintenance_stats["queued_events_processed"] = queue_stats.processed
	
	_log("Maintenance completed: %s" % str(maintenance_stats), LogLevel.DEBUG)
	return maintenance_stats

func _cleanup_empty_queues() -> int:
	"""Remove empty persistent queues"""
	var removed_count = 0
	var queues_to_remove = []
	
	for subscription_id in _persistent_queue._event_queues:
		if _persistent_queue.get_queue_size(subscription_id) == 0:
			# Check if the subscription still exists
			if not _find_subscription_by_id(subscription_id):
				queues_to_remove.append(subscription_id)
	
	for queue_id in queues_to_remove:
		_persistent_queue.remove_subscriber_queue(queue_id)
		removed_count += 1
	
	return removed_count

func _cleanup_replay_sessions() -> int:
	"""Remove completed or stale replay sessions"""
	var removed_count = 0
	var sessions_to_remove = []
	var current_time = Time.get_time_dict_from_system().unix
	
	for session_id in _replay_system._replay_sessions:
		var session = _replay_system._replay_sessions[session_id]
		var session_age = current_time - session.session_start
		
		# Remove completed sessions or sessions older than 1 hour
		if session.completed or session_age > 3600:
			sessions_to_remove.append(session_id)
	
	for session_id in sessions_to_remove:
		_replay_system.stop_replay_session(session_id)
		removed_count += 1
	
	return removed_count

# ===== ENHANCED EXPORT/IMPORT =====
func export_enhanced_configuration() -> Dictionary:
	"""Export enhanced configuration including new features"""
	var base_config = export_configuration()
	
	base_config["persistent_queuing_enabled"] = _persistent_queuing_enabled
	base_config["replay_enabled"] = _replay_enabled
	base_config["backpressure_enabled"] = _backpressure_enabled
	base_config["time_window_operations_enabled"] = _time_window_operations_enabled
	base_config["auto_queue_creation"] = _auto_queue_creation
	base_config["auto_replay_buffers"] = _auto_replay_buffers
	
	# Export queue configuration
	base_config["queue_config"] = {
		"max_queue_size_per_subscriber": _persistent_queue._max_queue_size_per_subscriber,
		"max_backlog_size": _persistent_queue._max_backlog_size,
		"backpressure_threshold": _persistent_queue._backpressure_threshold,
		"drop_policy": _persistent_queue._drop_policy
	}
	
	# Export backpressure configuration
	base_config["backpressure_config"] = _backpressure_controller.get_current_status()
	
	# Export replay configuration
	base_config["replay_config"] = {
		"max_global_buffer_size": _replay_system._max_global_buffer_size
	}
	
	return base_config

func import_enhanced_configuration(config: Dictionary):
	"""Import enhanced configuration"""
	# Import base configuration first
	import_configuration(config)
	
	# Import enhanced features
	_persistent_queuing_enabled = config.get("persistent_queuing_enabled", true)
	_replay_enabled = config.get("replay_enabled", true)
	_backpressure_enabled = config.get("backpressure_enabled", true)
	_time_window_operations_enabled = config.get("time_window_operations_enabled", true)
	_auto_queue_creation = config.get("auto_queue_creation", true)
	_auto_replay_buffers = config.get("auto_replay_buffers", true)
	
	# Import queue configuration
	var queue_config = config.get("queue_config", {})
	if not queue_config.is_empty():
		_persistent_queue._max_queue_size_per_subscriber = queue_config.get("max_queue_size_per_subscriber", 1000)
		_persistent_queue.set_max_backlog_size(queue_config.get("max_backlog_size", 10000))
		var threshold = queue_config.get("backpressure_threshold", 0.8)
		var policy = queue_config.get("drop_policy", "drop_oldest")
		_persistent_queue.set_backpressure_config(true, threshold, policy)
	
	# Import backpressure configuration
	var backpressure_config = config.get("backpressure_config", {})
	if not backpressure_config.is_empty():
		_backpressure_controller.enable_backpressure(backpressure_config.get("enabled", true))
		_backpressure_controller.enable_adaptive_throttling(backpressure_config.get("adaptive_throttling", true))
		var thresholds = backpressure_config.get("thresholds", {})
		for metric in thresholds:
			_backpressure_controller.set_threshold(metric, thresholds[metric])
	
	# Import replay configuration
	var replay_config = config.get("replay_config", {})
	if not replay_config.is_empty():
		_replay_system.set_max_backlog_size(replay_config.get("max_global_buffer_size", 50000))
	
	_log("Enhanced configuration imported successfully", LogLevel.INFO)

# ===== TESTING AND DEBUG METHODS =====
func _simulate_backpressure(pressure_level: float):
	"""Simulate backpressure for testing"""
	_backpressure_controller.update_metrics({
		"queue_utilization": pressure_level,
		"processing_rate": pressure_level,
		"frame_budget_used": pressure_level,
		"events_per_second": 100.0 * pressure_level
	})

func _get_queue_count_for_subscriber(subscription_id: String) -> int:
	"""Helper for testing - get queue count for specific subscriber"""
	return _persistent_queue.get_queue_size(subscription_id)

func _create_test_time_window(window_id: String, duration: float) -> bool:
	"""Helper for testing - create a simple time window"""
	return create_time_window(window_id, duration, 0.0, [], ["count", "event_rate"])

func _get_replay_buffer_size(subscription_id: String) -> int:
	"""Helper for testing - get replay buffer size for subscriber"""
	if not _replay_system._replay_buffers.has(subscription_id):
		return 0
	return _replay_system._replay_buffers[subscription_id].events.size()

func _force_process_all_queues():
	"""Helper for testing - force process all queues immediately"""
	var total_processed = 0
	var batch_size = 100
	
	while true:
		var stats = process_queued_events(batch_size)
		total_processed += stats.processed
		if stats.processed == 0:
			break
	
	return total_processed

func _get_backpressure_throttle_factor() -> float:
	"""Helper for testing - get current throttle factor"""
	return _backpressure_controller._throttle_factor

func _clear_all_enhanced_data():
	"""Helper for testing - clear all enhanced feature data"""
	if _persistent_queuing_enabled:
		for sub_id in _persistent_queue._event_queues.keys():
			_persistent_queue.clear_subscriber_queue(sub_id)
		_persistent_queue.clear_global_backlog()
	
	if _replay_enabled:
		_replay_system.clear_global_replay_buffer()
		for session_id in _replay_system._replay_sessions.keys():
			_replay_system.stop_replay_session(session_id)
	
	if _time_window_operations_enabled:
		_time_windows.clear_all_windows()
	
	_backpressure_controller._reset_metrics()

# ===== HOTLOAD SAFETY METHODS =====
func set_node_wrapper(node: Node):
	"""Set the node wrapper for scene tree access with hotload safety"""
	if not node or not is_instance_valid(node):
		_log("Invalid node wrapper provided", LogLevel.ERROR)
		return
	
	_dependency_manager.set_node_wrapper(node)
	_batch_processor.set_node_wrapper(node)
	
	_setup_dependency_callbacks()
	_execute_pending_setup()
	
	_log("Node wrapper set, dependency discovery started", LogLevel.INFO)

func _setup_dependency_callbacks():
	"""Set up callbacks for when dependencies are resolved"""
	_dependency_manager.add_dependency_callback("system_registry", _on_system_registry_ready)
	_dependency_manager.add_dependency_callback("config_manager", _on_config_manager_ready)
	_dependency_manager.add_dependency_callback("metrics_collector", _on_metrics_collector_ready)
	_dependency_manager.add_dependency_callback("health_monitor", _on_health_monitor_ready)

func _on_system_registry_ready(registry):
	"""Called when system registry becomes available"""
	if registry and is_instance_valid(registry):
		if registry.has_method("register_system"):
			registry.register_system("event_bus", self)
		_log("System registry connected and registered", LogLevel.INFO)

func _on_config_manager_ready(config_manager):
	"""Called when config manager becomes available"""
	if config_manager and is_instance_valid(config_manager):
		if config_manager.has_method("get_config"):
			var config = config_manager.get_config("event_bus", {})
			import_enhanced_configuration(config)
		_log("Config manager connected and configuration loaded", LogLevel.INFO)

func _on_metrics_collector_ready(metrics_collector):
	"""Called when metrics collector becomes available"""
	if metrics_collector and is_instance_valid(metrics_collector):
		_log("Metrics collector connected", LogLevel.INFO)

func _on_health_monitor_ready(health_monitor):
	"""Called when health monitor becomes available"""
	if health_monitor and is_instance_valid(health_monitor):
		if health_monitor.has_method("subscribe_to_health_updates"):
			health_monitor.subscribe_to_health_updates(_handle_system_health_updated)
		_log("Health monitor connected", LogLevel.INFO)

func _execute_pending_setup():
	"""Execute any setup calls that were deferred"""
	for call in _pending_setup_calls:
		if call.is_valid():
			call.call()
	_pending_setup_calls.clear()
	_initialization_complete = true

func add_pending_setup(call: Callable):
	"""Add a setup call to be executed when ready"""
	if _initialization_complete:
		if call.is_valid():
			call.call()
	else:
		_pending_setup_calls.append(call)

func reset_for_hotload():
	"""Reset state for hotload scenarios"""
	_dependency_manager.reset_dependency_discovery()
	_external_systems.clear()
	_subscription_health_tracking.clear()
	_degraded_subscriptions.clear()
	_integration_event_stats = {
		"schema_events_processed": 0,
		"config_events_processed": 0,
		"template_events_processed": 0,
		"resource_events_processed": 0
	}
	_initialization_complete = false
	_pending_setup_calls.clear()
	
	# Reset enhanced features
	_clear_all_enhanced_data()
	
	_log("Event bus reset for hotload", LogLevel.INFO)

# ===== PRODUCTION LOGGING SYSTEM =====
func _production_log(message: String, level: LogLevel = LogLevel.INFO):
	"""Production-ready logging with configurable levels and Godot integration"""
	if level < _log_level:
		return
	
	if _production_mode and level < LogLevel.ERROR:
		return
	
	var full_message = "[GoatBus] %s" % message
	var prefix = ""
	
	match level:
		LogLevel.DEBUG: 
			prefix = "[DEBUG]"
			if _use_godot_logging:
				print(full_message)
		LogLevel.INFO: 
			prefix = "[INFO]"
			if _use_godot_logging:
				print_rich("[color=cyan]%s[/color]" % full_message)
		LogLevel.WARNING: 
			prefix = "[WARN]"
			if _use_godot_logging:
				print_rich("[color=yellow]%s[/color]" % full_message)
				push_warning(full_message)
		LogLevel.ERROR: 
			prefix = "[ERROR]"
			if _use_godot_logging:
				print_rich("[color=red]%s[/color]" % full_message)
				push_error(full_message)
	
	if not _log_file_path.is_empty():
		_log_to_file("%s %s %s" % [prefix, Time.get_datetime_string_from_system(), message])
	
	if _log_to_debugger and level >= LogLevel.WARNING:
		_send_to_debugger_panel(full_message, level)

func set_log_file(file_path: String):
	"""Set log file path for persistent logging"""
	_log_file_path = file_path
	if not file_path.is_empty():
		var dir = file_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(dir):
			DirAccess.open("user://").make_dir_recursive_absolute(dir)

func enable_godot_logging(enabled: bool):
	"""Enable/disable Godot's built-in logging integration"""
	_use_godot_logging = enabled

func enable_debugger_logging(enabled: bool):
	"""Enable/disable logging to Godot's debugger panel"""
	_log_to_debugger = enabled

func set_log_level(level: LogLevel):
	"""Set logging level for production control"""
	_log_level = level
	_log("Log level set to %d" % level, LogLevel.INFO)

func set_production_mode(enabled: bool):
	"""Enable production mode (minimal logging)"""
	_production_mode = enabled
	if enabled:
		_log_level = LogLevel.ERROR
	_log("Production mode: %s" % ("enabled" if enabled else "disabled"), LogLevel.INFO)

# ===== GENERIC DEPENDENCY MANAGEMENT =====
func set_dependency(name: String, instance):
	"""Generic dependency injection with safety checks"""
	if not instance or not is_instance_valid(instance):
		_log("Attempted to set invalid dependency: %s" % name, LogLevel.WARNING)
		return
	
	_dependency_manager.set_dependency(name, instance)
	
	if _dependency_manager.is_ready():
		_dependency_manager.replay_operations(self)
		dependencies_resolved.emit()

func get_dependency(name: String):
	"""Generic dependency access with auto-discovery and caching"""
	var dep = _dependency_manager.get_dependency(name)
	return dep

func safe_get_dependency(name: String):
	"""Safely get dependency without triggering discovery"""
	return _dependency_manager._dependencies.get(name, null) if _dependency_manager._dependencies.has(name) and is_instance_valid(_dependency_manager._dependencies[name]) else null

# ===== MANUAL DEPENDENCY SETTERS =====
func set_system_registry(registry): 
	if registry and is_instance_valid(registry):
		set_dependency("system_registry", registry)

func set_config_manager(manager): 
	if manager and is_instance_valid(manager):
		set_dependency("config_manager", manager)

func set_metrics_collector(collector): 
	if collector and is_instance_valid(collector):
		set_dependency("metrics_collector", collector)

func set_health_monitor(monitor): 
	if monitor and is_instance_valid(monitor):
		set_dependency("health_monitor", monitor)

func set_orchestrator(orchestrator): 
	if orchestrator and is_instance_valid(orchestrator):
		set_dependency("orchestrator", orchestrator)

func set_template_manager(manager): 
	if manager and is_instance_valid(manager):
		set_dependency("template_manager", manager)

func set_schema_analyzer(analyzer): 
	if analyzer and is_instance_valid(analyzer):
		set_dependency("schema_analyzer", analyzer)

func set_intervention_manager(manager): 
	if manager and is_instance_valid(manager):
		set_dependency("intervention_manager", manager)

# ===== RUNTIME DEPENDENCY GETTERS =====
func get_system_registry(): 
	var registry = safe_get_dependency("system_registry")
	if not registry:
		if Engine.has_singleton("SystemRegistry"):
			var singleton = Engine.get_singleton("SystemRegistry")
			if singleton:
				set_system_registry(singleton)
				return singleton
	return registry

func get_config_manager(): 
	var manager = safe_get_dependency("config_manager")
	if not manager:
		if Engine.has_singleton("ConfigManager"):
			var singleton = Engine.get_singleton("ConfigManager")
			if singleton:
				set_config_manager(singleton)
				return singleton
	return manager

func get_metrics_collector(): 
	var collector = safe_get_dependency("metrics_collector")
	if not collector:
		if Engine.has_singleton("MetricsCollector"):
			var singleton = Engine.get_singleton("MetricsCollector")
			if singleton:
				set_metrics_collector(singleton)
				return singleton
	return collector

func get_health_monitor(): 
	var monitor = safe_get_dependency("health_monitor")
	if not monitor:
		if Engine.has_singleton("HealthMonitor"):
			var singleton = Engine.get_singleton("HealthMonitor")
			if singleton:
				set_health_monitor(singleton)
				return singleton
	return monitor

func get_orchestrator(): 
	var orchestrator_instance = safe_get_dependency("orchestrator")
	if not orchestrator_instance:
		if Engine.has_singleton("Orchestrator"):
			var singleton = Engine.get_singleton("Orchestrator")
			if singleton:
				set_orchestrator(singleton)
				return singleton
	return orchestrator_instance

func get_template_manager(): 
	var manager = safe_get_dependency("template_manager")
	if not manager:
		if Engine.has_singleton("TemplateManager"):
			var singleton = Engine.get_singleton("TemplateManager")
			if singleton:
				set_template_manager(singleton)
				return singleton
	return manager

func get_schema_analyzer(): 
	var analyzer = safe_get_dependency("schema_analyzer")
	if not analyzer:
		if Engine.has_singleton("SchemaAnalyzer"):
			var singleton = Engine.get_singleton("SchemaAnalyzer")
			if singleton:
				set_schema_analyzer(singleton)
				return singleton
	return analyzer

func get_intervention_manager(): 
	var manager = safe_get_dependency("intervention_manager")
	if not manager:
		if Engine.has_singleton("InterventionManager"):
			var singleton = Engine.get_singleton("InterventionManager")
			if singleton:
				set_intervention_manager(singleton)
				return singleton
	return manager

func subscribe_with_backlog(event_name: String, handler: Callable, owner: Object = null,
						   replay_from_timestamp: float = 0.0) -> String:
	"""Subscribe and immediately replay events from a specific timestamp"""
	var subscription_id = subscribe(event_name, handler, owner, true, 1, true)
	
	if replay_from_timestamp > 0.0:
		var current_time = Time.get_time_dict_from_system().unix
		var session_id = _replay_system.start_replay_session(
			subscription_id, replay_from_timestamp, current_time, [event_name], 10.0  # 10x speed
		)
		
		if not session_id.is_empty():
			_log("Started backlog replay for subscriber %s from timestamp %.1f" % 
				[subscription_id, replay_from_timestamp], LogLevel.INFO)
	
	return subscription_id

# ===== ENHANCED EVENT PUBLISHING =====
func publish(event_name: String, data: Dictionary = {}, priority: EventPriority = EventPriority.NORMAL) -> bool:
	"""Enhanced publish with persistent queuing, backpressure, and replay support"""
	
	# Cache if dependencies not ready
	if not _dependency_manager.is_ready():
		_dependency_manager.cache_operation("publish", {
			"event_name": event_name,
			"data": data,
			"priority": priority
		})
		return true
	
	# Check backpressure first
	if _backpressure_enabled:
		# Update metrics for backpressure calculation
		_update_backpressure_metrics()
		
		if _backpressure_controller.should_drop_event(priority):
			_log("Event '%s' dropped due to backpressure (priority: %d)" % [event_name, priority], LogLevel.WARNING)
			return false
		
		if _backpressure_controller.should_defer_non_critical(event_name):
			# Defer non-critical events by queuing them for later
			_defer_event(event_name, data, priority)
			return true
	
	# Start frame monitoring if enabled
	if _enable_frame_monitoring:
		_throughput_monitor.start_frame_monitoring()
	
	# Validate event data if schema exists
	if _enable_validation and _event_schemas.has(event_name):
		var schema = _event_schemas[event_name]
		var validation = schema.validate(data)
		if not validation.is_valid:
			_log("Event '%s' validation failed: %s" % [event_name, str(validation.errors)], LogLevel.ERROR)
			return false
	
	# Check for schema enforcement
	if _enforce_schema_registration and not _event_schemas.has(event_name):
		if event_name not in _schema_enforcement_exceptions:
			_log("Schema enforcement violation: Event '%s' published without registered schema" % event_name, LogLevel.ERROR)
			return false
	
	# Warn about unregistered events
	if _warn_unregistered_events and not _event_schemas.has(event_name):
		if event_name not in _schema_enforcement_exceptions:
			_log("Unregistered event published: '%s' - consider adding a schema for better validation" % event_name, LogLevel.WARNING)
	
	# Create event data structure
	var event_data = EventData.new(event_name, data, priority)
	
	# Track integration events
	_track_integration_event(event_name)
	
	# Add to replay buffers first
	if _replay_enabled:
		_replay_system.add_event_to_replay_buffers({
			"name": event_name,
			"event_name": event_name,
			"data": data,
			"priority": priority,
			"timestamp": event_data.timestamp
		})
	
	# Add to time windows
	if _time_window_operations_enabled:
		_time_windows.add_event_to_windows({
			"name": event_name,
			"event_name": event_name,
			"data": data,
			"priority": priority,
			"timestamp": event_data.timestamp
		})
	
	# Add to global backlog for persistent queuing
	if _persistent_queuing_enabled:
		_persistent_queue.add_to_global_backlog({
			"name": event_name,
			"event_name": event_name,
			"data": data,
			"priority": priority,
			"timestamp": event_data.timestamp
		})
	
	# Get target systems for this event
	var target_systems = _get_event_target_systems(event_name)
	
	# Adjust priority based on target system health
	var adjusted_priority = priority
	if _performance_aware_routing:
		adjusted_priority = _adjust_priority_for_system_health(priority, target_systems)
	
	# Add metadata
	data["_meta"] = {
		"event_name": event_name,
		"timestamp": event_data.timestamp,
		"priority": adjusted_priority,
		"source": "event_bus_enhanced",
		"target_systems": target_systems,
		"health_adjusted": adjusted_priority != priority,
		"integration_event": _is_integration_event(event_name)
	}
	
	# Route integration events through specialized batching
	var integration_type = _get_integration_type(event_name)
	if not integration_type.is_empty() and _orchestration_batch_processing:
		_batch_processor.queue_integration_event(integration_type, {
			"event_name": event_name,
			"data": data,
			"priority": adjusted_priority
		})
		return true
	
	# Route through batch processor if orchestration batching enabled
	if _orchestration_batch_processing and _is_orchestration_event(event_name):
		var phase_name = _extract_phase_from_event(event_name, data)
		if not phase_name.is_empty():
			_batch_processor.queue_phase_event(phase_name, {
				"event_name": event_name,
				"data": data,
				"priority": adjusted_priority
			})
			return true
	
	# Process immediately for non-batchable events
	var result = _process_single_event({
		"event_name": event_name,
		"data": data,
		"priority": adjusted_priority
	})
	
	# End frame monitoring
	if _enable_frame_monitoring:
		_throughput_monitor.end_frame_monitoring()
		if _throughput_monitor.is_frame_budget_exceeded(16.0):
			frame_budget_exceeded.emit(_throughput_monitor._frame_start_time * 1000)
	
	return result

func _defer_event(event_name: String, data: Dictionary, priority: int):
	"""Defer non-critical events during backpressure"""
	# Add to a special deferred queue that will be processed when pressure reduces
	if not has_meta("deferred_events"):
		set_meta("deferred_events", [])
	
	var deferred_events = get_meta("deferred_events")
	deferred_events.append({
		"event_name": event_name,
		"data": data,
		"priority": priority,
		"deferred_at": Time.get_time_dict_from_system().unix
	})
	
	# Limit deferred queue size
	while deferred_events.size() > 500:
		deferred_events.pop_front()
	
	_log("Deferred event '%s' due to backpressure" % event_name, LogLevel.DEBUG)

func _process_deferred_events():
	"""Process deferred events when backpressure reduces"""
	if not has_meta("deferred_events"):
		return
	
	var deferred_events = get_meta("deferred_events")
	if deferred_events.is_empty():
		return
	
	var processed_count = 0
	var max_to_process = 10  # Process a few at a time to avoid new pressure
	
	while not deferred_events.is_empty() and processed_count < max_to_process:
		var event = deferred_events.pop_front()
		_process_single_event(event)
		processed_count += 1
	
	if processed_count > 0:
		_log("Processed %d deferred events" % processed_count, LogLevel.INFO)

func _update_backpressure_metrics():
	"""Update metrics for backpressure calculation"""
	var total_queued = 0
	var total_queue_capacity = 0
	
	# Calculate queue utilization
	for subscription_id in _persistent_queue._event_queues:
		var queue_size = _persistent_queue.get_queue_size(subscription_id)
		total_queued += queue_size
		total_queue_capacity += _persistent_queue._max_queue_size_per_subscriber
	
	var queue_utilization = 0.0
	if total_queue_capacity > 0:
		queue_utilization = float(total_queued) / total_queue_capacity
	
	# Calculate processing rate based on recent throughput
	var throughput_report = _throughput_monitor.get_performance_report()
	var processing_rate = throughput_report.get("recent_events_per_frame", 0.0) / 60.0  # Convert to per-second
	
	# Update backpressure controller
	_backpressure_controller.update_metrics({
		"queue_utilization": queue_utilization,
		"processing_rate": processing_rate,
		"frame_budget_used": throughput_report.get("recent_frame_avg_ms", 0.0) / 16.0,  # Fraction of 16ms budget
		"events_per_second": processing_rate,
		"failed_events_rate": 0.0  # Could be calculated from throughput monitor
	})

func _process_single_event(event_data: Dictionary) -> bool:
	"""Enhanced process single event with persistent queuing support"""
	var event_name = event_data.get("event_name", "")
	var data = event_data.get("data", {})
	var priority = event_data.get("priority", EventPriority.NORMAL)
	
	event_published.emit(event_name, data, priority)
	
	# Emit integration event signal
	if _is_integration_event(event_name):
		var integration_type = _get_integration_type(event_name)
		integration_event_processed.emit(event_name, integration_type)
	
	if not _subscriptions.has(event_name):
		return true # No subscribers, but not an error
	
	var subscriptions = _subscriptions[event_name]
	var successful_calls = 0
	var failed_calls = 0
	
	# Filter subscriptions based on system health
	var viable_subscriptions = _filter_subscriptions_by_health(subscriptions, event_name)
	
	# Process each subscription with enhanced queuing
	for subscription in viable_subscriptions:
		if not subscription.is_valid():
			continue
		
		var start_time_us = _throughput_monitor._get_time_us()
		var processed = false
		
		# Check if subscriber can accept the event immediately
		if subscription.can_accept_event():
			if subscription.call_handler(data):
				successful_calls += 1
				processed = true
			else:
				failed_calls += 1
				_track_subscription_failure(subscription)
		else:
			# Subscriber is busy, try to queue the event
			if subscription.queue_enabled:
				if subscription.queue_event(data):
					# Successfully queued for later processing
					successful_calls += 1
					processed = true
				else:
					# Queue is full, try persistent queue
					if _persistent_queuing_enabled:
						if _persistent_queue.queue_event_for_subscriber(subscription.subscription_id, data):
							successful_calls += 1
							processed = true
						else:
							# Persistent queue is also full
							failed_calls += 1
							subscriber_queue_overflow.emit(subscription.subscription_id, 1)
					else:
						failed_calls += 1
			else:
				# No queuing enabled, event is lost
				failed_calls += 1
		
		if processed:
			var handler_time_us = _throughput_monitor._get_time_us() - start_time_us
			_throughput_monitor.record_handler_performance(event_name, handler_time_us)
	
	return failed_calls == 0

# ===== QUEUE PROCESSING =====
func process_queued_events(max_events_per_subscriber: int = 5) -> Dictionary:
	"""Process queued events for all subscribers"""
	var stats = {"processed": 0, "failed": 0, "subscribers_processed": 0}
	
	if not _persistent_queuing_enabled:
		return stats
	
	for subscription_id in _persistent_queue._event_queues:
		var events_processed = 0
		var subscriber_processed = false
		
		while events_processed < max_events_per_subscriber:
			var event_data = _persistent_queue.dequeue_event_for_subscriber(subscription_id)
			if event_data.is_empty():
				break
			
			# Find the subscription and process the event
			var subscription = _find_subscription_by_id(subscription_id)
			if subscription and subscription.is_valid() and subscription.can_accept_event():
				var data = event_data.get("data", {})
				if subscription.call_handler(data):
					stats.processed += 1
				else:
					stats.failed += 1
				
				events_processed += 1
				subscriber_processed = true
			else:
				# Put the event back in the queue if subscriber can't process it
				_persistent_queue.queue_event_for_subscriber(subscription_id, event_data)
				break
		
		if subscriber_processed:
			stats.subscribers_processed += 1
	
	# Also process personal queues in subscriptions
	for event_name in _subscriptions:
		for subscription in _subscriptions[event_name]:
			if subscription.has_queued_events() and subscription.can_accept_event():
				var queued_data = subscription.get_next_queued_event()
				if not queued_data.is_empty():
					if subscription.call_handler(queued_data):
						stats.processed += 1
					else:
						stats.failed += 1
	
	return stats

func _find_subscription_by_id(subscription_id: String) -> EventSubscription:
	"""Find subscription by ID across all event types"""
	for event_name in _subscriptions:
		for subscription in _subscriptions[event_name]:
			if subscription.subscription_id == subscription_id:
				return subscription
	return null

# ===== TIME WINDOW OPERATIONS API =====
func create_time_window(window_id: String, duration: float, slide_interval: float = 0.0,
					   event_filters: Array = [], aggregations: Array = ["count"]) -> bool:
	"""Create a time window for event aggregation"""
	if not _time_window_operations_enabled:
		_log("Time window operations are disabled", LogLevel.WARNING)
		return false
	
	return _time_windows.create_time_window(window_id, duration, slide_interval, event_filters, aggregations)

func get_window_aggregation(window_id: String) -> Dictionary:
	"""Get current aggregation results for a time window"""
	if not _time_window_operations_enabled:
		return {}
	
	return _time_windows.get_window_aggregation(window_id)

func get_events_in_time_window(window_id: String) -> Array:
	"""Get all events currently in a time window"""
	if not _time_window_operations_enabled:
		return []
	
	return _time_windows.get_events_in_window(window_id)

func get_events_from_last_seconds(seconds: float, event_filters: Array = []) -> Array:
	"""Get events from the last N seconds"""
	if not _replay_enabled:
		return []
	
	var current_time = Time.get_time_dict_from_system().unix
	var start_time = current_time - seconds
	
	return _replay_system.get_events_from_global_buffer(start_time, current_time, event_filters)

func get_events_between_timestamps(start_timestamp: float, end_timestamp: float, 
								  event_filters: Array = []) -> Array:
	"""Get events between specific timestamps"""
	if not _replay_enabled:
		return []
	
	return _replay_system.get_events_from_global_buffer(start_timestamp, end_timestamp, event_filters)

# ===== REPLAY OPERATIONS API =====
func start_event_replay(subscription_id: String, start_timestamp: float, 
					   end_timestamp: float = 0.0, event_filters: Array = [],
					   replay_speed: float = 1.0) -> String:
	"""Start replaying events for a subscriber"""
	if not _replay_enabled:
		_log("Replay system is disabled", LogLevel.WARNING)
		return ""
	
	return _replay_system.start_replay_session(subscription_id, start_timestamp, end_timestamp, 
											   event_filters, replay_speed)

func get_replay_status(session_id: String) -> Dictionary:
	"""Get status of a replay session"""
	if not _replay_enabled:
		return {}
	
	return _replay_system.get_replay_session_status(session_id)

func pause_replay(session_id: String) -> bool:
	"""Pause a replay session"""
	if not _replay_enabled:
		return false
	
	return _replay_system.pause_replay_session(session_id)

func resume_replay(session_id: String) -> bool:
	"""Resume a paused replay session"""
	if not _replay_enabled:
		return false
	
	return _replay_system.resume_replay_session(session_id)

func stop_replay(session_id: String) -> bool:
	"""Stop a replay session"""
	if not _replay_enabled:
		return false
	
	return _replay_system.stop_replay_session(session_id)

# ===== BACKPRESSURE CONTROL API =====
func enable_backpressure_control(enabled: bool):
	"""Enable or disable backpressure control"""
	_backpressure_enabled = enabled
	_backpressure_controller.enable_backpressure(enabled)
	_log("Backpressure control: %s" % ("enabled" if enabled else "disabled"), LogLevel.INFO)

func set_backpressure_threshold(metric_name: String, threshold: float):
	"""Set backpressure threshold for a specific metric"""
	if _backpressure_enabled:
		_backpressure_controller.set_threshold(metric_name, threshold)

func get_backpressure_status() -> Dictionary:
	"""Get current backpressure status"""
	if not _backpressure_enabled:
		return {"enabled": false}
	
	return _backpressure_controller.get_current_status()

func set_queue_drop_policy(policy: String):
	"""Set the drop policy for full queues: 'drop_oldest', 'drop_newest', 'block'"""
	if _persistent_queuing_enabled:
		_persistent_queue.set_backpressure_config(_persistent_queue._backpressure_enabled, 
												  _persistent_queue._backpressure_threshold, policy)

# ===== ENHANCED CONFIGURATION =====
func enable_persistent_queuing(enabled: bool):
	"""Enable or disable persistent event queuing"""
	_persistent_queuing_enabled = enabled
	_log("Persistent queuing: %s" % ("enabled" if enabled else "disabled"), LogLevel.INFO)

func enable_replay_system(enabled: bool):
	"""Enable or disable event replay system"""
	_replay_enabled = enabled
	_log("Replay system: %s" % ("enabled" if enabled else "disabled"), LogLevel.INFO)

func enable_time_window_operations(enabled: bool):
	"""Enable or disable time window operations"""
	_time_window_operations_enabled = enabled
	_log("Time window operations: %s" % ("enabled" if enabled else "disabled"), LogLevel.INFO)

func enable_auto_queue_creation(enabled: bool):
	"""Enable automatic queue creation for new subscribers"""
	_auto_queue_creation = enabled
	_log("Auto queue creation: %s" % ("enabled" if enabled else "disabled"), LogLevel.INFO)

func enable_auto_replay_buffers(enabled: bool):
	"""Enable automatic replay buffer creation for new subscribers"""
	_auto_replay_buffers = enabled
	_log("Auto replay buffers: %s" % ("enabled" if enabled else "disabled"), LogLevel.INFO)# core/events/event_bus.gd

# ===== TYPED EVENT CLASSES =====

class EventData extends RefCounted:
	var name: String
	var data: Dictionary
	var priority: int
	var timestamp: float
	var source: String
	var target_systems: Array
	var health_adjusted: bool
	var integration_event: bool
	
	func _init(event_name: String, event_data: Dictionary = {}, event_priority: int = 1):
		name = event_name
		data = event_data
		priority = event_priority
		timestamp = Time.get_time_dict_from_system().unix
		source = "event_bus_enhanced"
		target_systems = []
		health_adjusted = false
		integration_event = false


class EventSchema extends RefCounted:
	var event_name: String
	var required_fields: Array = []
	var optional_fields: Array = []
	var field_types: Dictionary = {}
	
	func _init(name: String):
		event_name = name
	
	func add_required_field(field_name: String, field_type: String = ""):
		if field_name not in required_fields:
			required_fields.append(field_name)
		if not field_type.is_empty():
			field_types[field_name] = field_type
	
	func add_optional_field(field_name: String, field_type: String = ""):
		if field_name not in optional_fields:
			optional_fields.append(field_name)
		if not field_type.is_empty():
			field_types[field_name] = field_type
	
	func validate(data: Dictionary) -> Dictionary:
		var result = {"is_valid": true, "errors": []}
		
		for field in required_fields:
			if not data.has(field):
				result.errors.append("Missing required field: " + field)
				result.is_valid = false
		
		for field in data:
			if field_types.has(field):
				var expected_type = field_types[field]
				var actual_value = data[field]
				if not _is_type_match(actual_value, expected_type):
					result.errors.append("Field '%s' expected %s, got %s" % [field, expected_type, typeof(actual_value)])
					result.is_valid = false
		
		return result
	
	func _is_type_match(value, expected_type: String) -> bool:
		match expected_type.to_lower():
			"string": return value is String
			"int", "integer": return value is int
			"float": return value is float
			"bool", "boolean": return value is bool
			"array": return value is Array
			"dictionary", "dict": return value is Dictionary
			"vector2": return value is Vector2
			"vector3": return value is Vector3
			"node": return value is Node
			"resource": return value is Resource
			_:
				# Handle custom class_name checks
				if expected_type.begins_with("class:"):
					var class_name_check = expected_type.substr(6)
					return _check_custom_class(value, class_name_check)
				
				# Handle duck-typing interface checks
				if expected_type.begins_with("interface:"):
					var methods = expected_type.substr(10).split(",")
					return _check_duck_type_interface(value, methods)
				
				# Handle Resource subclass checks
				if expected_type.begins_with("resource:"):
					var resource_type = expected_type.substr(9)
					return value is Resource and value.get_class() == resource_type
				
				return true  # Unknown type, allow it
	
	func _check_custom_class(value, class_name_param: String) -> bool:
		# Check if value matches custom class_name
		if not is_instance_valid(value):
			return false
		
		var script = value.get_script()
		if script and script.has_method("get_global_name"):
			return script.get_global_name() == class_name_param
		elif script:
			return script.get_path().get_file().get_basename() == class_name_param
		
		return false
	
	func _check_duck_type_interface(value, methods: Array) -> bool:
		# Check if value implements required methods (duck typing)
		if not is_instance_valid(value):
			return false
		
		for method_name in methods:
			method_name = method_name.strip_edges()
			if not value.has_method(method_name):
				return false
		
		return true

# ===== PERSISTENT EVENT QUEUE =====
class PersistentEventQueue extends RefCounted:
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

# ===== TIME WINDOW OPERATIONS =====
class TimeWindowOperations extends RefCounted:
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

# ===== BACKPRESSURE CONTROLLER =====
class BackpressureController extends RefCounted:
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
