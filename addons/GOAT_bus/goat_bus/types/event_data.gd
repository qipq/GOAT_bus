# ===== goat_bus/types/event_data.gd =====
extends RefCounted
class_name EventData

const VERSION := "4.2.0.69"
const MANIFEST := {
	"script_name": "EventData",
	"script_path": "res://goat_bus/types/event_data.gd",
	"class_name": "EventData",
	"version": "1.0.0",
	"description": "Core event data structure for GoatBus event system",
	"required_dependencies": [],
	"optional_dependencies": [],
	"features": ["event_metadata", "timestamp_tracking", "priority_support"],
	"api_version": "goatbus-v1.0.0",
	"last_updated": "2025-08-10"
}

# =============================================================================
# EVENT DATA TYPE
# =============================================================================

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
