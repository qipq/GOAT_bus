# =============================================================================
# GOATBUS ANALYSIS WRAPPER
# =============================================================================
# Node wrapper for ObjDictInjector providing scene tree integration
# Handles timer-based dependency discovery, file monitoring, and API delegation
# =============================================================================

@tool
extends Node
class_name GoatBusAnalysisWrapper

# =============================================================================
# CONSTANTS & MANIFEST
# =============================================================================

const VERSION := "1.0.0"
const MANIFEST := {
	"script_name": "GoatBusAnalysisWrapper",
	"script_path": "res://systems/analysis/goatbus_analysis_wrapper.gd",
	"class_name": "GoatBusAnalysisWrapper",
	"version": "1.0.0",
	"description": "Node wrapper for ObjDictInjector providing scene tree integration, file monitoring, and timer-based dependency discovery",
	"required_dependencies": ["goatbus_analysis_core"],
	"optional_dependencies": ["event_bus", "system_registry"],
	"features": [
		"scene_tree_integration",
		"timer_based_discovery",
		"api_delegation",
		"signal_forwarding",
		"manual_injection_support",
		"file_system_monitoring",
		"automatic_initialization",
		"polling_file_watcher"
	],
	"signals": {
		"system_ready": [],
		"dependency_failed": ["reason"],
		"analysis_complete": ["result"],
		"injection_ready": ["objects"],
		"file_changed": ["file_path"]
	},
	"variables": [
		{"name": "_analysis_core", "type": "ObjDictInjector", "initial": "null"},
		{"name": "_file_watcher_timer", "type": "Timer", "initial": "null"},
		{"name": "_file_timestamps", "type": "Dictionary", "initial": "{}"},
		{"name": "_monitoring_enabled", "type": "bool", "initial": "true"}
	],
	"entry_points": ["_ready"],
	"api_version": "goatbus-analysis-wrapper-v1.0.0",
	"last_updated": "2025-08-09",
	"compliance": {
		"core_system_blueprint": "v1.2",
		"wrapper_node_pattern": true,
		"communication_architecture": "wrapper_to_core_only",
		"syntax_guide": "v1.2"
	}
}

# =============================================================================
# SIGNALS
# =============================================================================

signal system_ready
signal dependency_failed(reason: String)
signal analysis_complete(result: Dictionary)
signal injection_ready(objects: Dictionary)
signal file_changed(file_path: String)

# =============================================================================
# CORE INSTANCE AND FILE MONITORING
# =============================================================================

var _analysis_core: ObjDictInjector
var _file_watcher_timer: Timer
var _file_timestamps: Dictionary = {}
var _monitoring_enabled := true
var _poll_interval := 1.0
var _watched_extensions := [".gd"]

# =============================================================================
# INITIALIZATION
# =============================================================================

func _ready():
	_setup_analysis_core()
	_setup_file_watcher()
	_setup_groups()
	
	log_debug("GoatBusAnalysisWrapper ready")

func _setup_analysis_core():
	_analysis_core = ObjDictInjector.new()
	_analysis_core.set_node_wrapper(self)
	
	# Connect core signals
	_analysis_core.system_ready.connect(_on_core_system_ready)
	_analysis_core.dependency_failed.connect(_on_core_dependency_failed)
	_analysis_core.analysis_complete.connect(_on_core_analysis_complete)
	_analysis_core.injection_ready.connect(_on_core_injection_ready)
	
	# Start dependency discovery
	_analysis_core.start_discovery()
	
	log_debug("Analysis core setup complete")

func _setup_file_watcher():
	_file_watcher_timer = Timer.new()
	_file_watcher_timer.name = "FileWatcherTimer"
	_file_watcher_timer.timeout.connect(_poll_files)
	_file_watcher_timer.wait_time = _poll_interval
	_file_watcher_timer.autostart = false
	add_child(_file_watcher_timer)
	
	# Scan initial file timestamps
	_scan_initial_timestamps()
	
	# Start monitoring
	if _monitoring_enabled:
		_file_watcher_timer.start()
	
	log_debug("File watcher setup complete")

func _setup_groups():
	add_to_group("analysis_system")
	add_to_group("goatbus_analysis")
	
	log_debug("Added to analysis system groups")

# =============================================================================
# FILE SYSTEM MONITORING
# =============================================================================

func _scan_initial_timestamps():
	var file_count = _scan_directory_recursive("res://", true)
	log_debug("Initial file scan complete: %d files found" % file_count)

func _scan_directory_recursive(path: String, is_initial_scan: bool = false) -> int:
	var dir = DirAccess.open(path)
	if not dir:
		log_warn("Cannot access directory: " + path)
		return 0
	
	var file_count = 0
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		var full_path = path + "/" + file_name
		
		if dir.current_is_dir() and not file_name.begins_with("."):
			# Recursively scan subdirectories (skip hidden dirs)
			file_count += _scan_directory_recursive(full_path, is_initial_scan)
		elif _should_monitor_file(file_name):
			# Monitor files with watched extensions
			if is_initial_scan:
				_file_timestamps[full_path] = FileAccess.get_modified_time(full_path)
			file_count += 1
		
		file_name = dir.get_next()
	
	return file_count

func _should_monitor_file(file_name: String) -> bool:
	for extension in _watched_extensions:
		if file_name.ends_with(extension):
			return true
	return false

func _poll_files():
	if not _monitoring_enabled:
		return
	
	var changes_detected = 0
	var files_checked = 0
	
	for file_path in _file_timestamps:
		files_checked += 1
		
		# Check if file still exists
		if not FileAccess.file_exists(file_path):
			_handle_file_deleted(file_path)
			continue
		
		var current_time = FileAccess.get_modified_time(file_path)
		var cached_time = _file_timestamps[file_path]
		
		if current_time > cached_time:
			_file_timestamps[file_path] = current_time
			_handle_file_changed(file_path)
			changes_detected += 1
	
	# Check for new files
	_scan_for_new_files()
	
	if changes_detected > 0:
		log_debug("Poll complete: %d changes detected in %d files" % [changes_detected, files_checked])

func _scan_for_new_files():
	_scan_for_new_files_in_directory("res://")

func _scan_for_new_files_in_directory(path: String):
	var dir = DirAccess.open(path)
	if not dir:
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		var full_path = path + "/" + file_name
		
		if dir.current_is_dir() and not file_name.begins_with("."):
			_scan_for_new_files_in_directory(full_path)
		elif _should_monitor_file(file_name):
			# Check if this is a new file
			if not _file_timestamps.has(full_path):
				_file_timestamps[full_path] = FileAccess.get_modified_time(full_path)
				_handle_file_added(full_path)
		
		file_name = dir.get_next()

func _handle_file_changed(file_path: String):
	log_debug("File changed: " + file_path)
	file_changed.emit(file_path)
	
	# Forward to analysis core
	_analysis_core.handle_file_changed(file_path)

func _handle_file_added(file_path: String):
	log_debug("New file detected: " + file_path)
	file_changed.emit(file_path)
	
	# Forward to analysis core
	_analysis_core.handle_file_changed(file_path)

func _handle_file_deleted(file_path: String):
	log_debug("File deleted: " + file_path)
	_file_timestamps.erase(file_path)

# =============================================================================
# SIGNAL HANDLERS
# =============================================================================

func _on_core_system_ready():
	system_ready.emit()
	log_debug("Analysis system ready")

func _on_core_dependency_failed(reason: String):
	dependency_failed.emit(reason)
	log_warn("Analysis system dependency failed: " + reason)

func _on_core_analysis_complete(result: Dictionary):
	analysis_complete.emit(result)

func _on_core_injection_ready(objects: Dictionary):
	injection_ready.emit(objects)

# =============================================================================
# PUBLIC API DELEGATION
# =============================================================================

func analyze_script(script_path: String, options: Dictionary = {}) -> Dictionary:
	return _analysis_core.analyze_script(script_path, options)

func analyze_script_dependencies(script_path: String) -> Array:
	return _analysis_core._script_analyzer.analyze_script_dependencies(script_path)

func generate_script_summary(script_path: String) -> Dictionary:
	return _analysis_core._script_analyzer.generate_script_summary(script_path)

func validate_node_references(script_path: String) -> Dictionary:
	return _analysis_core._script_analyzer.validate_node_references(script_path)

func analyze_code_quality(script_path: String) -> Dictionary:
	return _analysis_core._script_analyzer.analyze_code_quality(script_path)

func get_injectable_object(object_name: String):
	return _analysis_core.get_injectable_object(object_name)

func register_injectable_object(name: String, object):
	_analysis_core.register_injectable_object(name, object)

func get_autocomplete_data() -> Dictionary:
	return _analysis_core.get_autocomplete_data()

func get_system_info() -> Dictionary:
	var core_info = _analysis_core.get_system_info()
	core_info["wrapper_version"] = VERSION
	core_info["wrapper_manifest"] = MANIFEST
	core_info["file_monitoring"] = {
		"enabled": _monitoring_enabled,
		"poll_interval": _poll_interval,
		"tracked_files": _file_timestamps.size(),
		"watched_extensions": _watched_extensions
	}
	return core_info

func get_project_scan_stats() -> Dictionary:
	return _analysis_core.get_project_scan_stats()

# =============================================================================
# CACHE MANAGEMENT
# =============================================================================

func clear_analysis_cache():
	_analysis_core.clear_analysis_cache()

func clear_project_cache():
	_analysis_core.clear_project_cache()

func refresh_autocomplete_data():
	_analysis_core.refresh_autocomplete_data()

func trigger_project_rescan():
	_analysis_core.trigger_project_rescan()

func force_file_rescan():
	_file_timestamps.clear()
	_scan_initial_timestamps()
	log_debug("Forced file rescan complete")

# =============================================================================
# CONFIGURATION
# =============================================================================

func set_auto_scan_enabled(enabled: bool):
	_analysis_core.set_auto_scan_enabled(enabled)

func set_auto_inject_enabled(enabled: bool):
	_analysis_core.set_auto_inject_enabled(enabled)

func set_file_watch_interval(interval: float):
	_poll_interval = interval
	if _file_watcher_timer:
		_file_watcher_timer.wait_time = interval
	log_debug("File watch interval set to %s seconds" % interval)

func add_watched_file_extension(extension: String):
	if not extension.begins_with("."):
		extension = "." + extension
	
	if extension not in _watched_extensions:
		_watched_extensions.append(extension)
		log_debug("Added file extension: " + extension)

func remove_watched_file_extension(extension: String):
	if not extension.begins_with("."):
		extension = "." + extension
	
	_watched_extensions.erase(extension)
	log_debug("Removed file extension: " + extension)

# =============================================================================
# MANUAL INJECTION (For Testing/Setup)
# =============================================================================

func set_event_bus(bus):
	_analysis_core.set_event_bus(bus)
	log_debug("Event bus manually injected")

func set_system_registry(registry):
	_analysis_core.set_system_registry(registry)
	log_debug("System registry manually injected")

func set_config_manager(config):
	_analysis_core.set_config_manager(config)
	log_debug("Config manager manually injected")

# =============================================================================
# DIRECT CORE ACCESS (For Advanced Usage)
# =============================================================================

func get_analysis_core() -> ObjDictInjector:
	return _analysis_core

# =============================================================================
# MONITORING CONTROL
# =============================================================================

func start_file_monitoring():
	_monitoring_enabled = true
	if _file_watcher_timer:
		_file_watcher_timer.start()
	log_debug("File monitoring started")

func stop_file_monitoring():
	_monitoring_enabled = false
	if _file_watcher_timer:
		_file_watcher_timer.stop()
	log_debug("File monitoring stopped")

func pause_file_monitoring():
	if _file_watcher_timer:
		_file_watcher_timer.paused = true
	log_debug("File monitoring paused")

func resume_file_monitoring():
	if _file_watcher_timer:
		_file_watcher_timer.paused = false
	log_debug("File monitoring resumed")

func get_file_monitoring_status() -> Dictionary:
	return {
		"enabled": _monitoring_enabled,
		"poll_interval": _poll_interval,
		"tracked_files": _file_timestamps.size(),
		"timer_active": _file_watcher_timer and not _file_watcher_timer.is_stopped(),
		"watched_extensions": _watched_extensions
	}

# =============================================================================
# DIAGNOSTICS
# =============================================================================

func run_diagnostics() -> Dictionary:
	var diagnostics = {
		"wrapper_info": {
			"version": VERSION,
			"ready": _analysis_core != null,
			"file_monitoring_active": _monitoring_enabled
		},
		"core_info": {},
		"file_monitoring": get_file_monitoring_status(),
		"scene_tree_info": {
			"node_path": get_path(),
			"groups": get_groups(),
			"children_count": get_child_count()
		}
	}
	
	if _analysis_core:
		diagnostics.core_info = _analysis_core.get_system_info()
	
	return diagnostics

# =============================================================================
# EVENT REQUESTS (Convenience Methods)
# =============================================================================

func request_script_analysis(script_path: String, requester_id: String = "wrapper"):
	if _analysis_core._event_bus and _analysis_core._event_bus.has_method("publish"):
		var request_data = {
			"script_path": script_path,
			"options": {"generate_usage": true},
			"requester_id": requester_id
		}
		_analysis_core._event_bus.publish("script_analysis_requested", request_data)

func request_object_injection(object_name: String, requester_id: String = "wrapper"):
	if _analysis_core._event_bus and _analysis_core._event_bus.has_method("publish"):
		var request_data = {
			"object_name": object_name,
			"requester_id": requester_id
		}
		_analysis_core._event_bus.publish("object_injection_requested", request_data)

func request_autocomplete_data(category: String = "all", requester_id: String = "wrapper"):
	if _analysis_core._event_bus and _analysis_core._event_bus.has_method("publish"):
		var request_data = {
			"category": category,
			"requester_id": requester_id
		}
		_analysis_core._event_bus.publish("autocomplete_data_requested", request_data)

# =============================================================================
# LOGGING
# =============================================================================

func log_debug(msg: String):
	print("[GoatBusAnalysisWrapper DEBUG] " + msg)

func log_warn(msg: String):
	print("[GoatBusAnalysisWrapper WARN] " + msg)

func log_error(msg: String):
	print("[GoatBusAnalysisWrapper ERROR] " + msg)

# =============================================================================
# CLEANUP
# =============================================================================

func _exit_tree():
	if _analysis_core:
		_analysis_core._reset_state()
	
	if _file_watcher_timer:
		_file_watcher_timer.stop()
	
	log_debug("GoatBusAnalysisWrapper cleanup complete")
