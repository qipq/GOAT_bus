# ===== goat_bus/core/replay_system.gd =====
extends RefCounted
class_name EventReplaySystem

const VERSION := "4.2.0.69"
const MANIFEST := {
	"script_name": "EventReplaySystem",
	"script_path": "res://goat_bus/core/replay_system.gd",
	"class_name": "EventReplaySystem",
	"version": "1.0.0",
	"description": "Event replay and time-travel debugging for GoatBus",
	"required_dependencies": [],
	"optional_dependencies": [],
	"features": ["replay_sessions", "subscriber_buffers", "playback_control"],
	"api_version": "goatbus-v1.0.0",
	"last_updated": "2025-08-10"
}

# =============================================================================
# EVENT REPLAY SYSTEM
# =============================================================================

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
