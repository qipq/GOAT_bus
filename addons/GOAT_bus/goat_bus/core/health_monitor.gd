# ===== goat_bus/core/health_router.gd =====
extends RefCounted
class_name HealthAwareRouter

const VERSION := "4.2.0.69"
const MANIFEST := {
	"script_name": "HealthAwareRouter",
	"script_path": "res://goat_bus/core/health_router.gd",
	"class_name": "HealthAwareRouter",
	"version": "1.0.0",
	"description": "Health-aware event routing for GoatBus system",
	"required_dependencies": [],
	"optional_dependencies": [],
	"features": ["system_health_monitoring", "routing_decisions", "priority_adjustments"],
	"api_version": "goatbus-v1.0.0",
	"last_updated": "2025-08-10"
}

# =============================================================================
# HEALTH AWARE ROUTER
# =============================================================================

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
