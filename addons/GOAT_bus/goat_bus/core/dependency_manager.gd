# ===== goat_bus/core/dependency_manager.gd =====
extends RefCounted
class_name DependencyManager

const VERSION := "4.2.0.69"
const MANIFEST := {
	"script_name": "DependencyManager",
	"script_path": "res://goat_bus/core/dependency_manager.gd",
	"class_name": "DependencyManager",
	"version": "1.0.0",
	"description": "Dependency management and discovery for GoatBus",
	"required_dependencies": [],
	"optional_dependencies": [],
	"features": ["dependency_discovery", "cached_operations", "callback_system"],
	"api_version": "goatbus-v1.0.0",
	"last_updated": "2025-08-10"
}

# =============================================================================
# DEPENDENCY MANAGER
# =============================================================================

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
