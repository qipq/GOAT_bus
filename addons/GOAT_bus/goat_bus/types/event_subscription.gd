# ===== goat_bus/types/event_subscription.gd =====
extends RefCounted
class_name EventSubscription

const VERSION := "4.2.0.69"
const MANIFEST := {
	"script_name": "EventSubscription",
	"script_path": "res://goat_bus/types/event_subscription.gd",
	"class_name": "EventSubscription",
	"version": "1.0.0",
	"description": "Event subscription management for GoatBus event system",
	"required_dependencies": [],
	"optional_dependencies": [],
	"features": ["concurrent_processing", "personal_queues", "replay_support"],
	"api_version": "goatbus-v1.0.0",
	"last_updated": "2025-08-10"
}

# =============================================================================
# EVENT SUBSCRIPTION
# =============================================================================

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
