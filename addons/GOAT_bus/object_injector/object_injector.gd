# =============================================================================
# GOATBUS ANALYSIS CORE
# =============================================================================
# Main RefCounted component for GoatBus script analysis and object injection
# Provides automatic project scanning, dependency discovery, and auto-injection
# =============================================================================

@tool
extends RefCounted
class_name ObjDictInjector

# =============================================================================
# CONSTANTS & MANIFEST
# =============================================================================

const VERSION := "1.0.0"
const MANIFEST := {
	"script_name": "ObjDictInjector",
	"script_path": "res://systems/analysis/goatbus_analysis_core.gd",
	"class_name": "ObjDictInjector",
	"version": "1.0.0",
	"description": "Main RefCounted component for GoatBus script analysis and object injection with automatic project scanning and resilient dependency discovery",
	"required_dependencies": ["event_bus", "system_registry", "script_analyzer", "event_objects"],
	"optional_dependencies": ["config_manager", "node_wrapper"],
	"features": [
		"script_analysis", "object_injection", "autocomplete_generation",
		"dependency_discovery", "hotload_safety", "5_stage_discovery_chain",
		"exponential_backoff_retry", "memory_safe_cleanup", "event_driven_communication",
		"automatic_project_scanning", "auto_injection_on_save", "file_system_monitoring",
		"selective_auto_injection"
	],
	"signals": {
		"system_ready": [],
		"dependency_failed": ["reason"],
		"analysis_complete": ["result"],
		"injection_ready": ["objects"]
	},
	"variables": [
		{"name": "_event_bus", "type": "Variant", "initial": "null"},
		{"name": "_system_registry", "type": "Variant", "initial": "null"},
		{"name": "_config_manager", "type": "Variant", "initial": "null"},
		{"name": "_node_wrapper", "type": "Variant", "initial": "null"},
		{"name": "_dependencies_ready", "type": "bool", "initial": "false"},
		{"name": "_analysis_cache", "type": "Dictionary", "initial": "{}"},
		{"name": "_injection_registry", "type": "Dictionary", "initial": "{}"},
		{"name": "_auto_scan_enabled", "type": "bool", "initial": "true"},
		{"name": "_auto_inject_enabled", "type": "bool", "initial": "true"},
		{"name": "_project_files_cache", "type": "Dictionary", "initial": "{}"}
	],
	"entry_points": ["_init", "start_discovery", "_initialize_system", "_scan_project_files"],
	"api_version": "goatbus-analysis-v1.0.0",
	"last_updated": "2025-08-09",
	"compliance": {
		"core_system_blueprint": "v1.2",
		"syntax_guide": "v1.2",
		"resilience_features": [
			"5_stage_dependency_discovery", "timer_based_retry", "weakref_memory_safety",
			"subscription_cleanup", "hotload_state_reset", "fallback_degraded_mode"
		]
	}
}

# =============================================================================
# SIGNALS
# =============================================================================

signal system_ready
signal dependency_failed(reason: String)
signal analysis_complete(result: Dictionary)
signal injection_ready(objects: Dictionary)

# =============================================================================
# DEPENDENCY VARIABLES
# =============================================================================

var _event_bus = null
var _system_registry = null
var _config_manager = null
var _node_wrapper = null
var _fallback_event_bus = null

# =============================================================================
# DISCOVERY RETRY CONFIG
# =============================================================================

var _retry_timer: Timer
var _retry_attempts := 0
var _max_attempts := 30
var _dependencies_ready := false

# =============================================================================
# CORE FUNCTIONALITY
# =============================================================================

var _script_analyzer: ScriptAnalyzer
var _event_objects: EventObjects
var _analysis_cache: Dictionary = {}
var _injection_registry: Dictionary = {}
var _autocomplete_data: Dictionary = {}

# =============================================================================
# AUTO-SCANNING AND INJECTION
# =============================================================================

var _project_files_cache: Dictionary = {}
var _auto_scan_enabled := true
var _auto_inject_enabled := true
var _last_scan_timestamp := 0.0
var _subscribed_handlers: Array[Dictionary] = []

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init() -> void:
	_script_analyzer = ScriptAnalyzer.new()
	_event_objects = EventObjects.new()
	log_debug("ObjDictInjector initialized")

# =============================================================================
# DEPENDENCY DISCOVERY (5-STAGE CHAIN)
# =============================================================================

func _get_event_bus():
	# Stage 1: Engine singleton
	if Engine.has_singleton("EventBus"):
		return Engine.get_singleton("EventBus")
	
	# Stage 2: Scene tree path - get tree safely
	var tree = _get_scene_tree()
	if tree:
		var node = tree.get_node_or_null("/root/EventBus")
		if node: 
			return node
		
		# Stage 3: Group discovery
		var grp = tree.get_first_node_in_group("event_bus")
		if grp:
			if grp.has_method("get_event_bus_instance"):
				return grp.get_event_bus_instance()
			if grp.has_method("get_instance"):
				return grp.get_instance()
			return grp
	
	# Stage 4: Fallback
	if _should_use_fallback("event_bus"):
		if not _fallback_event_bus:
			_fallback_event_bus = _create_null_event_bus()
		return _fallback_event_bus
	
	return null

func _get_system_registry():
	# Stage 1: Engine singleton
	if Engine.has_singleton("SystemRegistry"):
		return Engine.get_singleton("SystemRegistry")
	
	# Stage 2: Scene tree path - get tree safely
	var tree = _get_scene_tree()
	if tree:
		var node = tree.get_node_or_null("/root/SystemRegistry")
		if node: 
			return node
		
		# Stage 3: Group discovery
		var grp = tree.get_first_node_in_group("system_registry")
		if grp:
			if grp.has_method("get_registry_instance"):
				return grp.get_registry_instance()
			return grp
	
	return null

func _get_config_manager():
	# Stage 1: Engine singleton
	if Engine.has_singleton("ConfigManager"):
		return Engine.get_singleton("ConfigManager")
	
	# Stage 2: Scene tree path - get tree safely
	var tree = _get_scene_tree()
	if tree:
		var node = tree.get_node_or_null("/root/ConfigManager")
		if node: 
			return node
		
		# Stage 3: Group discovery
		var grp = tree.get_first_node_in_group("config_manager")
		if grp: 
			return grp
	
	return null

# Helper function to safely get scene tree
func _get_scene_tree():
	if _node_wrapper and _node_wrapper.has_method("get_tree"):
		return _node_wrapper.get_tree()
	
	# Try to get tree from Engine if scene tree exists
	if Engine.get_main_loop() and Engine.get_main_loop() is SceneTree:
		return Engine.get_main_loop()
	
	return null

# =============================================================================
# DEPENDENCY RETRY LOOP
# =============================================================================

func start_discovery() -> void:
	if _node_wrapper:
		_setup_retry_timer()
	else:
		_retry_discovery()

func _setup_retry_timer() -> void:
	if not _node_wrapper: 
		return
	
	_retry_timer = Timer.new()
	_retry_timer.autostart = false
	_retry_timer.one_shot = true
	_retry_timer.timeout.connect(_retry_discovery)
	_node_wrapper.add_child(_retry_timer)
	_retry_discovery()

func _retry_discovery() -> void:
	_retry_attempts += 1
	
	_event_bus = _get_event_bus()
	_system_registry = _get_system_registry()
	_config_manager = _get_config_manager()
	
	var required_deps_ready = _event_bus and _system_registry
	
	if required_deps_ready:
		_dependencies_ready = true
		if _retry_timer:
			_retry_timer.stop()
		_initialize_system()
	else:
		if _retry_attempts < _max_attempts:
			var wait_time = 0.25 * pow(1.5, _retry_attempts)
			if _retry_timer:
				_retry_timer.wait_time = wait_time
				_retry_timer.start()
			else:
				var tree = _get_scene_tree()
				if tree:
					await tree.create_timer(wait_time).timeout
				_retry_discovery()
		else:
			_handle_dependency_timeout()

# =============================================================================
# MANUAL INJECTION METHODS
# =============================================================================

func set_event_bus(bus) -> void: 
	_event_bus = bus
	_check_ready_state()

func set_system_registry(reg) -> void: 
	_system_registry = reg
	_check_ready_state()

func set_config_manager(cfg) -> void: 
	_config_manager = cfg

func set_node_wrapper(wrapper) -> void: 
	_node_wrapper = wrapper

func _check_ready_state() -> void:
	if _event_bus and _system_registry and not _dependencies_ready:
		_dependencies_ready = true
		_initialize_system()

# =============================================================================
# SYSTEM INITIALIZATION
# =============================================================================

func _initialize_system() -> void:
	log_debug("Initializing analysis system with dependencies ready")
	
	# Load configuration
	_load_auto_scan_config()
	
	# Register with system registry
	if _system_registry and _system_registry.has_method("register_system"):
		_system_registry.register_system("analysis_core", self)
	
	# Subscribe to events
	_subscribe_events()
	
	# Initialize injection registry
	_setup_injection_registry()
	
	# Auto-scan project if enabled
	if _auto_scan_enabled:
		_scan_project_files()
	
	# Auto-inject to GoatBus if enabled
	if _auto_inject_enabled:
		_auto_inject_to_goat_bus()
	
	# Generate initial autocomplete data
	_generate_autocomplete_data()
	
	system_ready.emit()
	log_debug("ObjDictInjector system ready with auto-features enabled")

func _subscribe_events() -> void:
	if not _event_bus or not _event_bus.has_method("subscribe"): 
		return
	
	var callback_analyze = Callable(self, "_handle_analyze_request")
	var callback_inject = Callable(self, "_handle_injection_request")
	var callback_autocomplete = Callable(self, "_handle_autocomplete_request")
	
	if _event_bus.has_method("subscribe"):
		_event_bus.subscribe("script_analysis_requested", callback_analyze, self)
		_event_bus.subscribe("object_injection_requested", callback_inject, self)
		_event_bus.subscribe("autocomplete_data_requested", callback_autocomplete, self)
		
		# Track subscriptions for cleanup
		_subscribed_handlers.append({
			"name": "script_analysis_requested",
			"cb": callback_analyze,
			"ref": weakref(self)
		})
		_subscribed_handlers.append({
			"name": "object_injection_requested",
			"cb": callback_inject,
			"ref": weakref(self)
		})
		_subscribed_handlers.append({
			"name": "autocomplete_data_requested",
			"cb": callback_autocomplete,
			"ref": weakref(self)
		})

# =============================================================================
# AUTOMATIC PROJECT SCANNING (METHOD 1)
# =============================================================================

func _load_auto_scan_config() -> void:
	if _config_manager and _config_manager.has_method("get"):
		_auto_scan_enabled = _config_manager.get("analysis_system.auto_scan_project", true)
		_auto_inject_enabled = _config_manager.get("analysis_system.auto_inject", true)
	else:
		_auto_scan_enabled = true
		_auto_inject_enabled = true
	
	log_debug("Auto-scan enabled: %s, Auto-inject enabled: %s" % [_auto_scan_enabled, _auto_inject_enabled])

func _scan_project_files() -> void:
	log_debug("Starting automatic project file scan")
	var start_time = Time.get_ticks_msec()
	
	var script_files = _discover_all_gd_files()
	var analyzed_count = 0
	
	for script_path in script_files:
		if _should_skip_analysis(script_path):
			continue
		
		var analysis = analyze_script(script_path, {"generate_usage": false})
		if not analysis.has("error") or analysis.error.is_empty():
			analyzed_count += 1
			_project_files_cache[script_path] = {
				"last_modified": FileAccess.get_modified_time(script_path),
				"analysis_timestamp": Time.get_unix_time_from_system(),
				"has_event_objects": _contains_event_objects(analysis),
				"has_injectable_classes": _contains_injectable_classes(analysis)
			}
	
	_last_scan_timestamp = Time.get_unix_time_from_system()
	var scan_time = Time.get_ticks_msec() - start_time
	
	log_debug("Project scan complete: %d files analyzed in %d ms" % [analyzed_count, scan_time])
	
	# Publish scan complete event
	if _event_bus and _event_bus.has_method("publish"):
		var scan_event = _event_objects.create_phase_completed("project_scan", scan_time, true)
		scan_event["files_scanned"] = script_files.size()
		scan_event["files_analyzed"] = analyzed_count
		_event_bus.publish("project_scan_completed", scan_event)

func _discover_all_gd_files() -> Array:
	var script_files = []
	_scan_directory_recursive("res://", script_files)
	return script_files

func _scan_directory_recursive(path: String, files: Array) -> void:
	var dir = DirAccess.open(path)
	if not dir:
		log_warn("Cannot access directory: " + path)
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		var full_path = path + "/" + file_name
		
		if dir.current_is_dir() and not file_name.begins_with("."):
			_scan_directory_recursive(full_path, files)
		elif file_name.ends_with(".gd"):
			files.append(full_path)
		
		file_name = dir.get_next()

func _should_skip_analysis(script_path: String) -> bool:
	if not _project_files_cache.has(script_path):
		return false
	
	var cached_info = _project_files_cache[script_path]
	var current_modified = FileAccess.get_modified_time(script_path)
	
	return cached_info.last_modified >= current_modified

func _contains_event_objects(analysis: Dictionary) -> bool:
	for call in analysis.get("cross_script_calls", []):
		if "EventObjects" in call.get("target", ""):
			return true
	
	for method_call in analysis.get("object_method_calls", []):
		if "EventObjects" in method_call.get("object", ""):
			return true
	
	return false

func _contains_injectable_classes(analysis: Dictionary) -> bool:
	var injector_class_name = analysis.get("injector_class_name", "")
	if injector_class_name.is_empty():
		return false
	
	var injectable_patterns = ["Manager", "System", "Controller", "Service", "Factory", "Registry"]
	for pattern in injectable_patterns:
		if pattern in injector_class_name:
			return true
	
	return false

# =============================================================================
# FILE CHANGE HANDLING
# =============================================================================

func handle_file_changed(file_path: String) -> void:
	if not file_path.ends_with(".gd"):
		return
	
	log_debug("GDScript file changed: " + file_path)
	
	# Re-analyze the changed file
	var analysis = analyze_script(file_path, {"generate_usage": false})
	
	# Update cache
	_project_files_cache[file_path] = {
		"last_modified": FileAccess.get_modified_time(file_path),
		"analysis_timestamp": Time.get_unix_time_from_system(),
		"has_event_objects": _contains_event_objects(analysis),
		"has_injectable_classes": _contains_injectable_classes(analysis)
	}
	
	# Auto-inject if enabled and contains relevant objects
	if _auto_inject_enabled:
		_auto_inject_changed_file(file_path, analysis)
	
	# Refresh autocomplete data
	_generate_autocomplete_data()
	
	# Publish file change event
	if _event_bus and _event_bus.has_method("publish"):
		var change_event = _event_objects.create_debug_info_requested("file_changed", "file_watcher")
		change_event["file_path"] = file_path
		change_event["auto_injected"] = _auto_inject_enabled
		_event_bus.publish("script_file_changed", change_event)

func _auto_inject_changed_file(file_path: String, analysis: Dictionary) -> void:
	var injector_class_name = analysis.get("injector_class_name", "")
	if injector_class_name.is_empty():
		return
	
	var script = load(file_path)
	if script and script is GDScript:
		if _contains_injectable_classes(analysis):
			register_injectable_object(injector_class_name, script)
			log_debug("Auto-registered injectable class: " + injector_class_name)
		
		if _contains_event_objects(analysis):
			_update_goat_bus_integration(script, analysis)

func _update_goat_bus_integration(script: GDScript, analysis: Dictionary) -> void:
	if not _event_bus:
		return
	
	for method in analysis.get("methods", []):
		var method_name = method.name
		if method_name.begins_with("create_") and _event_bus.has_method("register_event_type"):
			if script.has_method(method_name):
				_event_bus.register_event_type(method_name, Callable(script, method_name))
				log_debug("Auto-registered new event type: " + method_name)

# =============================================================================
# SELECTIVE AUTO-INJECTION (METHOD 3)
# =============================================================================

func _auto_inject_to_goat_bus() -> void:
	if not _event_bus or not _event_bus.has_method("register_event_factory"):
		log_debug("Skipping auto-injection: GoatBus not available or doesn't support event factories")
		return
	
	log_debug("Starting selective auto-injection to GoatBus")
	
	# Auto-inject EventObjects factory
	var event_objects = get_injectable_object("EventObjects")
	if event_objects:
		_event_bus.register_event_factory("EventObjects", event_objects)
		log_debug("Auto-injected EventObjects factory to GoatBus")
	
	# Auto-inject all event creation methods
	var event_factories = _get_event_factory_registry()
	for factory_name in event_factories:
		if _event_bus.has_method("register_event_type"):
			_event_bus.register_event_type(factory_name, event_factories[factory_name])
			log_debug("Auto-injected event type: " + factory_name)
	
	# Auto-inject script analyzer if GoatBus supports it
	if _event_bus.has_method("register_analyzer"):
		var script_analyzer = get_injectable_object("ScriptAnalyzer")
		if script_analyzer:
			_event_bus.register_analyzer("ScriptAnalyzer", script_analyzer)
			log_debug("Auto-injected ScriptAnalyzer to GoatBus")
	
	# Auto-inject autocomplete data
	if _event_bus.has_method("register_autocomplete_provider"):
		_event_bus.register_autocomplete_provider("analysis_system", self)
		log_debug("Auto-injected autocomplete provider to GoatBus")
	
	# Publish auto-injection complete event
	if _event_bus.has_method("publish"):
		var injection_event = _event_objects.create_phase_completed("auto_injection", 0.0, true)
		injection_event["injected_objects"] = _injection_registry.keys()
		_event_bus.publish("auto_injection_completed", injection_event)

# =============================================================================
# SCRIPT ANALYSIS
# =============================================================================

func analyze_script(script_path: String, options: Dictionary = {}) -> Dictionary:
	var cache_key = script_path + str(options.hash())
	
	if _analysis_cache.has(cache_key):
		log_debug("Returning cached analysis for: " + script_path)
		return _analysis_cache[cache_key]
	
	log_debug("Analyzing script: " + script_path)
	var analysis_options = _script_analyzer.get_default_options()
	
	for key in options:
		analysis_options[key] = options[key]
	
	var result = _script_analyzer.analyze_script(script_path, analysis_options)
	_analysis_cache[cache_key] = result
	
	if _event_bus and _event_bus.has_method("publish"):
		var event_data = _event_objects.create_debug_info_requested("script_analysis", "analysis_core")
		event_data["analysis_result"] = result
		event_data["script_path"] = script_path
		_event_bus.publish("script_analysis_complete", event_data)
	
	analysis_complete.emit(result)
	return result

# =============================================================================
# OBJECT INJECTION SYSTEM
# =============================================================================

func _setup_injection_registry() -> void:
	_injection_registry["EventObjects"] = _event_objects
	_injection_registry["ScriptAnalyzer"] = _script_analyzer
	_injection_registry["AnalysisCore"] = self
	
	var event_factories = _get_event_factory_registry()
	for factory_name in event_factories:
		_injection_registry[factory_name] = event_factories[factory_name]
	
	log_debug("Injection registry setup complete with %d objects" % _injection_registry.size())
	injection_ready.emit(_injection_registry)

func _get_event_factory_registry() -> Dictionary:
	return {
		"SystemHealthUpdate": EventObjects.SystemHealthUpdate,
		"PerformanceMetricsUpdate": EventObjects.PerformanceMetricsUpdate,
		"IntegrationBatchStarting": EventObjects.IntegrationBatchStarting,
		"IntegrationBatchCompleted": EventObjects.IntegrationBatchCompleted,
		"ConfigurationUpdated": EventObjects.ConfigurationUpdated,
		"SystemInitializationComplete": EventObjects.SystemInitializationComplete,
		"QueueThresholdExceeded": EventObjects.QueueThresholdExceeded,
		"EventValidationFailed": EventObjects.EventValidationFailed,
		"create_phase_started": EventObjects.create_phase_started,
		"create_phase_completed": EventObjects.create_phase_completed,
		"create_maintenance_started": EventObjects.create_maintenance_started,
		"create_performance_alert": EventObjects.create_performance_alert
	}

func get_injectable_object(object_name: String):
	if _injection_registry.has(object_name):
		return _injection_registry[object_name]
	
	log_warn("Injectable object not found: " + object_name)
	return null

func register_injectable_object(name: String, object) -> void:
	_injection_registry[name] = object
	log_debug("Registered injectable object: " + name)

# =============================================================================
# AUTOCOMPLETE DATA GENERATION
# =============================================================================

func _generate_autocomplete_data() -> void:
	_autocomplete_data = {
		"event_objects": _generate_event_objects_autocomplete(),
		"script_analyzer": _generate_script_analyzer_autocomplete(),
		"analysis_patterns": _generate_analysis_patterns(),
		"injection_objects": _generate_injection_autocomplete()
	}
	
	log_debug("Generated autocomplete data with %d categories" % _autocomplete_data.size())

func _generate_event_objects_autocomplete() -> Dictionary:
	return {
		"complex_events": {
			"SystemHealthUpdate": {
				"constructor": "EventObjects.SystemHealthUpdate.new(system_name: String, new_state: String, health_score: float = 1.0, reason: String = \"\")",
				"usage": "var event = EventObjects.SystemHealthUpdate.new(\"player_system\", \"healthy\", 0.95).to_dict()",
				"fields": ["system_name", "new_state", "health_score", "reason"]
			},
			"PerformanceMetricsUpdate": {
				"constructor": "EventObjects.PerformanceMetricsUpdate.new(system_name: String, response_time_ms: float, error_rate: float = 0.0, failure_probability: float = 0.0)",
				"usage": "var event = EventObjects.PerformanceMetricsUpdate.new(\"ai_system\", 45.2, 0.02).to_dict()",
				"fields": ["system_name", "response_time_ms", "error_rate", "failure_probability"]
			}
		},
		"simple_events": {
			"phase_started": {
				"factory": "EventObjects.create_phase_started(phase_name: String)",
				"usage": "bus.publish(\"phase_started\", EventObjects.create_phase_started(\"initialization\"))",
				"fields": ["phase_name"]
			},
			"performance_alert": {
				"factory": "EventObjects.create_performance_alert(alert_type: String, severity: String = \"warning\", metric_value: float = 0.0, threshold: float = 0.0)",
				"usage": "bus.publish(\"performance_alert\", EventObjects.create_performance_alert(\"high_latency\", \"critical\", 850.0, 500.0))",
				"fields": ["alert_type", "severity", "metric_value", "threshold"]
			}
		}
	}

func _generate_script_analyzer_autocomplete() -> Dictionary:
	return {
		"methods": {
			"analyze_script": {
				"signature": "analyze_script(script_path: String, options: Dictionary = {}) -> Dictionary",
				"description": "Comprehensive script analysis with configurable options",
				"returns": "Analysis result with methods, properties, signals, etc."
			},
			"generate_script_summary": {
				"signature": "generate_script_summary(script_path: String) -> Dictionary", 
				"description": "Generate overview summary of script structure",
				"returns": "Summary with complexity metrics and patterns"
			},
			"analyze_code_quality": {
				"signature": "analyze_code_quality(script_path: String) -> Dictionary",
				"description": "Analyze code quality metrics and suggestions",
				"returns": "Quality scores and improvement suggestions"
			}
		}
	}

func _generate_analysis_patterns() -> Dictionary:
	return {
		"common_patterns": [
			"var result = analysis_core.analyze_script(\"res://player.gd\")",
			"var quality = analysis_core.analyze_code_quality(script_path)",
			"var deps = analysis_core.analyze_script_dependencies(script_path)",
			"var summary = analysis_core.generate_script_summary(script_path)"
		],
		"event_publishing": [
			"bus.publish(\"system_health_updated\", EventObjects.SystemHealthUpdate.new(\"core\", \"healthy\").to_dict())",
			"bus.publish(\"phase_started\", EventObjects.create_phase_started(\"initialization\"))",
			"bus.publish(\"performance_alert\", EventObjects.create_performance_alert(\"memory\", \"warning\"))"
		]
	}

func _generate_injection_autocomplete() -> Dictionary:
	var autocomplete = {}
	for object_name in _injection_registry:
		autocomplete[object_name] = {
			"type": typeof(_injection_registry[object_name]),
			"methods": _get_object_methods(_injection_registry[object_name])
		}
	return autocomplete

func _get_object_methods(obj) -> Array:
	var methods = []
	if obj.has_method("get_method_list"):
		for method_info in obj.get_method_list():
			methods.append(method_info.name)
	return methods

func get_autocomplete_data() -> Dictionary:
	return _autocomplete_data

# =============================================================================
# EVENT HANDLERS
# =============================================================================

func _handle_analyze_request(event_data: Dictionary) -> void:
	var script_path = event_data.get("script_path", "")
	var options = event_data.get("options", {})
	var requester = event_data.get("requester_id", "unknown")
	
	if script_path.is_empty():
		log_warn("Analysis request missing script_path from: " + requester)
		return
	
	var result = analyze_script(script_path, options)
	
	if _event_bus and _event_bus.has_method("publish"):
		var response_data = {
			"requester_id": requester,
			"script_path": script_path,
			"analysis_result": result,
			"timestamp": Time.get_unix_time_from_system()
		}
		_event_bus.publish("script_analysis_response", response_data)

func _handle_injection_request(event_data: Dictionary) -> void:
	var object_name = event_data.get("object_name", "")
	var requester = event_data.get("requester_id", "unknown")
	
	var obj = get_injectable_object(object_name)
	
	if _event_bus and _event_bus.has_method("publish"):
		var response_data = {
			"requester_id": requester,
			"object_name": object_name,
			"object_instance": obj,
			"success": obj != null,
			"timestamp": Time.get_unix_time_from_system()
		}
		_event_bus.publish("object_injection_response", response_data)

func _handle_autocomplete_request(event_data: Dictionary) -> void:
	var category = event_data.get("category", "all")
	var requester = event_data.get("requester_id", "unknown")
	
	var response_data = _autocomplete_data
	if category != "all" and _autocomplete_data.has(category):
		response_data = {category: _autocomplete_data[category]}
	
	if _event_bus and _event_bus.has_method("publish"):
		var full_response = {
			"requester_id": requester,
			"category": category,
			"autocomplete_data": response_data,
			"timestamp": Time.get_unix_time_from_system()
		}
		_event_bus.publish("autocomplete_data_response", full_response)

# =============================================================================
# MEMORY SAFETY & CLEANUP
# =============================================================================

func _reset_state() -> void:
	log_debug("Resetting analysis core state")
	
	for sub in _subscribed_handlers:
		if sub.has("ref") and sub.ref.get_ref():
			if _event_bus and _event_bus.has_method("unsubscribe"):
				_event_bus.unsubscribe(sub.name, sub.cb)
	_subscribed_handlers.clear()
	
	_analysis_cache.clear()
	_autocomplete_data.clear()
	_project_files_cache.clear()
	
	_dependencies_ready = false
	_retry_attempts = 0
	_last_scan_timestamp = 0.0
	
	log_debug("Analysis core state reset complete")

# =============================================================================
# ERROR HANDLING & FALLBACKS
# =============================================================================

func _handle_dependency_timeout() -> void:
	log_warn("Dependencies not found after %d retries. Running in degraded mode." % _retry_attempts)
	dependency_failed.emit("Missing dependencies: event_bus, system_registry")
	
	if _should_use_fallback("event_bus"):
		_event_bus = _create_null_event_bus()
		_initialize_system()

func _should_use_fallback(dep_name: String) -> bool:
	match dep_name:
		"event_bus":
			return true
		_:
			return false

func _create_null_event_bus():
	return NullEventBus.new()

class NullEventBus extends RefCounted:
	func publish(event: String, data: Dictionary) -> void: 
		pass
	func subscribe(event: String, cb: Callable, ctx) -> void: 
		pass
	func unsubscribe(event: String, cb: Callable) -> void: 
		pass
	# Fixed: Override has_method with correct signature
	func has_method(method_name: StringName) -> bool: 
		return method_name in ["publish", "subscribe", "unsubscribe"]

# =============================================================================
# PUBLIC API
# =============================================================================

func get_system_info() -> Dictionary:
	return {
		"version": VERSION,
		"manifest": MANIFEST,
		"dependencies_ready": _dependencies_ready,
		"injection_registry_size": _injection_registry.size(),
		"analysis_cache_size": _analysis_cache.size(),
		"autocomplete_categories": _autocomplete_data.keys(),
		"auto_scan_enabled": _auto_scan_enabled,
		"auto_inject_enabled": _auto_inject_enabled,
		"last_scan_timestamp": _last_scan_timestamp,
		"project_files_cached": _project_files_cache.size()
	}

func clear_analysis_cache() -> void:
	_analysis_cache.clear()
	log_debug("Analysis cache cleared")

func clear_project_cache() -> void:
	_project_files_cache.clear()
	log_debug("Project files cache cleared")

func refresh_autocomplete_data() -> void:
	_generate_autocomplete_data()
	log_debug("Autocomplete data refreshed")

func trigger_project_rescan() -> void:
	if _auto_scan_enabled:
		_scan_project_files()
		log_debug("Manual project rescan triggered")
	else:
		log_warn("Project rescan requested but auto-scan is disabled")

func set_auto_scan_enabled(enabled: bool) -> void:
	_auto_scan_enabled = enabled
	log_debug("Auto-scan %s" % ("enabled" if enabled else "disabled"))

func set_auto_inject_enabled(enabled: bool) -> void:
	_auto_inject_enabled = enabled
	log_debug("Auto-inject %s" % ("enabled" if enabled else "disabled"))

func get_project_scan_stats() -> Dictionary:
	return {
		"files_cached": _project_files_cache.size(),
		"last_scan": _last_scan_timestamp,
		"auto_scan_enabled": _auto_scan_enabled,
		"auto_inject_enabled": _auto_inject_enabled,
		"files_with_event_objects": _count_files_with_feature("has_event_objects"),
		"files_with_injectable_classes": _count_files_with_feature("has_injectable_classes")
	}

func _count_files_with_feature(feature: String) -> int:
	var count = 0
	for file_info in _project_files_cache.values():
		if file_info.get(feature, false):
			count += 1
	return count

# =============================================================================
# LOGGING
# =============================================================================

func log_debug(msg: String) -> void:
	print("[ObjDictInjector DEBUG] " + msg)

func log_warn(msg: String) -> void:
	print("[ObjDictInjector WARN] " + msg)

func log_error(msg: String) -> void:
	print("[ObjDictInjector ERROR] " + msg)
