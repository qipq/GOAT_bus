# =============================================================================
# GOATBUS ANALYSIS INTEGRATION
# =============================================================================
# Integration utilities for quick setup and scene tree management
# Static helper methods for easy GoatBus analysis system integration
# =============================================================================

@tool
extends RefCounted
class_name GoatBusAnalysisIntegration

# =============================================================================
# CONSTANTS & MANIFEST
# =============================================================================

const VERSION := "1.0.0"
const MANIFEST := {
	"script_name": "GoatBusAnalysisIntegration",
	"script_path": "res://systems/analysis/goatbus_analysis_integration.gd",
	"class_name": "GoatBusAnalysisIntegration",
	"version": "1.0.0",
	"description": "Integration utilities for quick setup and scene tree management of GoatBus analysis system",
	"required_dependencies": [],
	"optional_dependencies": ["goat_bus", "system_registry"],
	"features": [
		"quick_setup_methods", "wrapper_node_creation", "scene_tree_integration",
		"autoload_configuration", "project_validation", "development_console"
	],
	"signals": {},
	"variables": [],
	"entry_points": [
		"setup_analysis_system", "create_analysis_wrapper_node", 
		"add_to_scene_tree", "validate_project_structure"
	],
	"api_version": "goatbus-analysis-integration-v1.0.0",
	"last_updated": "2025-08-09",
	"compliance": {
		"core_system_blueprint": "v1.2",
		"syntax_guide": "v1.2",
		"static_helper_pattern": true
	}
}

# =============================================================================
# QUICK SETUP METHODS
# =============================================================================

static func setup_analysis_system(goat_bus, system_registry = null) -> ObjDictInjector:
	"""Quick setup method for integrating analysis system with GoatBus"""
	log_debug("Setting up analysis system")
	
	var analysis_core = ObjDictInjector.new()
	analysis_core.set_event_bus(goat_bus)
	if system_registry:
		analysis_core.set_system_registry(system_registry)
	
	log_debug("Analysis system setup complete")
	return analysis_core

static func create_analysis_wrapper_node() -> GoatBusAnalysisWrapper:
	"""Create wrapper node for scene tree integration"""
	log_debug("Creating analysis wrapper node")
	
	var wrapper = GoatBusAnalysisWrapper.new()
	wrapper.name = "GoatBusAnalysisSystem"
	wrapper.add_to_group("analysis_system")
	wrapper.add_to_group("goatbus_integration")
	
	log_debug("Analysis wrapper node created")
	return wrapper

static func add_to_scene_tree(scene_tree: SceneTree, parent_path: String = "/root") -> GoatBusAnalysisWrapper:
	"""Add analysis system to scene tree at specified path"""
	log_debug("Adding analysis system to scene tree")
	
	var parent_node = scene_tree.get_node_or_null(parent_path)
	if not parent_node:
		log_error("Parent node not found: " + parent_path)
		return null
	
	var wrapper = create_analysis_wrapper_node()
	parent_node.add_child(wrapper)
	
	log_debug("Analysis system added to scene tree at: " + parent_path)
	return wrapper

static func setup_with_goat_bus_discovery(scene_tree: SceneTree) -> GoatBusAnalysisWrapper:
	"""Setup analysis system with automatic GoatBus discovery"""
	log_debug("Setting up with GoatBus discovery")
	
	var wrapper = add_to_scene_tree(scene_tree)
	if not wrapper:
		return null
	
	await wrapper.system_ready
	
	log_debug("Analysis system ready with GoatBus integration")
	return wrapper

# =============================================================================
# AUTOLOAD CONFIGURATION
# =============================================================================

static func setup_autoload_integration(autoload_name: String = "AnalysisSystem") -> Dictionary:
	"""Setup analysis system as an autoload with configuration"""
	return {
		"autoload_name": autoload_name,
		"script_path": "res://systems/analysis/goatbus_analysis_wrapper.gd",
		"singleton": true,
		"instructions": [
			"Add to Project Settings > AutoLoad:",
			"  Name: " + autoload_name,
			"  Path: res://systems/analysis/goatbus_analysis_wrapper.gd",
			"  Singleton: Enabled",
			"",
			"Access via: " + autoload_name + ".analyze_script(\"res://script.gd\")"
		]
	}

# =============================================================================
# PROJECT VALIDATION
# =============================================================================

static func validate_project_structure() -> Dictionary:
	"""Validate that project has proper structure for analysis system"""
	var validation = {
		"valid": true,
		"issues": [],
		"recommendations": []
	}
	
	# Check for required directories
	var required_dirs = ["res://systems/", "res://systems/analysis/"]
	for dir_path in required_dirs:
		if not DirAccess.dir_exists_absolute(dir_path):
			validation.valid = false
			validation.issues.append("Missing directory: " + dir_path)
			validation.recommendations.append("Create directory: " + dir_path)
	
	# Check for ScriptAnalyzer and EventObjects
	var required_scripts = [
		"res://addons/script_analyzer.gd",
		"res://addons/event_objects.gd"
	]
	
	for script_path in required_scripts:
		if not FileAccess.file_exists(script_path):
			validation.issues.append("Missing required script: " + script_path)
			validation.recommendations.append("Ensure " + script_path.get_file() + " is available")
	
	# Check for GoatBus
	var goat_bus_found = false
	var potential_goat_bus_paths = [
		"res://addons/goat_bus.gd",
		"res://systems/goat_bus.gd",
		"res://core/goat_bus.gd"
	]
	
	for path in potential_goat_bus_paths:
		if FileAccess.file_exists(path):
			goat_bus_found = true
			break
	
	if not goat_bus_found:
		validation.issues.append("GoatBus not found in expected locations")
		validation.recommendations.append("Ensure GoatBus is available in project")
	
	return validation

static func create_project_setup_guide() -> Dictionary:
	"""Create setup guide for new projects"""
	return {
		"title": "GoatBus Analysis System Setup Guide",
		"version": VERSION,
		"steps": [
			{
				"step": 1,
				"title": "Directory Structure",
				"actions": [
					"Create res://systems/ directory",
					"Create res://systems/analysis/ directory",
					"Copy analysis system scripts to res://systems/analysis/"
				]
			},
			{
				"step": 2,
				"title": "Dependencies",
				"actions": [
					"Ensure ScriptAnalyzer is available",
					"Ensure EventObjects is available", 
					"Ensure GoatBus is available and configured"
				]
			},
			{
				"step": 3,
				"title": "Integration Method (Choose One)",
				"actions": [
					"Option A: Autoload - Add GoatBusAnalysisWrapper as autoload",
					"Option B: Scene Tree - Add via GoatBusAnalysisIntegration.add_to_scene_tree()",
					"Option C: Manual - Create and configure manually in your scripts"
				]
			}
		],
		"examples": {
			"autoload_setup": "GoatBusAnalysisIntegration.setup_autoload_integration()",
			"scene_tree_setup": "GoatBusAnalysisIntegration.add_to_scene_tree(get_tree())",
			"manual_setup": "GoatBusAnalysisIntegration.setup_analysis_system(goat_bus)"
		}
	}

# =============================================================================
# DEVELOPMENT CONSOLE
# =============================================================================

static func create_development_console(parent_node: Node) -> DevelopmentConsole:
	"""Create a development console with analysis system integration"""
	log_debug("Creating development console")
	
	var console = DevelopmentConsole.new()
	console.name = "DevelopmentConsole"
	parent_node.add_child(console)
	
	log_debug("Development console created")
	return console

class DevelopmentConsole extends Control:
	const VERSION := "1.0.0"
	const MANIFEST := {
		"script_name": "DevelopmentConsole", 
		"class_name": "DevelopmentConsole",
		"version": "1.0.0",
		"description": "Development console with GoatBus analysis system integration",
		"features": ["script_analysis", "autocomplete_display", "system_diagnostics"]
	}
	
	# =============================================================================
	# SIGNALS
	# =============================================================================
	
	signal system_ready
	signal dependency_failed(reason: String)
	
	# =============================================================================
	# DEPENDENCY VARIABLES
	# =============================================================================
	
	var _event_bus = null
	var _system_registry = null
	var _config_manager = null
	var _node_wrapper = null
	
	# =============================================================================
	# DISCOVERY RETRY CONFIG
	# =============================================================================
	
	var _retry_timer: Timer
	var _retry_attempts := 0
	var _max_attempts := 30
	var _dependencies_ready := false
	
	# =============================================================================
	# CONSOLE VARIABLES
	# =============================================================================
	
	var analysis_system: GoatBusAnalysisWrapper
	var output_label: RichTextLabel
	var input_field: LineEdit
	
	# =============================================================================
	# INITIALIZATION
	# =============================================================================
	
	func _ready() -> void:
		_setup_ui()
		_setup_retry_timer()
	
	func _setup_ui() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		
		var vbox = VBoxContainer.new()
		add_child(vbox)
		
		# Output area
		output_label = RichTextLabel.new()
		output_label.custom_minimum_size = Vector2(400, 300)
		output_label.bbcode_enabled = true
		vbox.add_child(output_label)
		
		# Input field
		input_field = LineEdit.new()
		input_field.placeholder_text = "Enter script path to analyze..."
		input_field.text_submitted.connect(_on_input_submitted)
		vbox.add_child(input_field)
		
		# Buttons
		var button_container = HBoxContainer.new()
		vbox.add_child(button_container)
		
		var analyze_button = Button.new()
		analyze_button.text = "Analyze Script"
		analyze_button.pressed.connect(_analyze_script)
		button_container.add_child(analyze_button)
		
		var diagnostics_button = Button.new()
		diagnostics_button.text = "System Diagnostics"
		diagnostics_button.pressed.connect(_show_diagnostics)
		button_container.add_child(diagnostics_button)
		
		_log("Development Console Ready")
	
	# =============================================================================
	# DEPENDENCY DISCOVERY
	# =============================================================================
	
	func _setup_retry_timer() -> void:
		_retry_timer = Timer.new()
		_retry_timer.autostart = false
		_retry_timer.one_shot = true
		_retry_timer.timeout.connect(_retry_discovery)
		add_child(_retry_timer)
		_retry_discovery()
	
	func _retry_discovery() -> void:
		_retry_attempts += 1
		
		analysis_system = _get_analysis_system()
		
		if analysis_system:
			_dependencies_ready = true
			_retry_timer.stop()
			_initialize_system()
		else:
			if _retry_attempts < _max_attempts:
				var wait_time = 0.25 * pow(1.5, _retry_attempts)
				_retry_timer.wait_time = wait_time
				_retry_timer.start()
			else:
				_handle_dependency_timeout()
	
	func _get_analysis_system() -> GoatBusAnalysisWrapper:
		# Stage 1: Engine singleton
		if Engine.has_singleton("AnalysisSystem"):
			return Engine.get_singleton("AnalysisSystem")
		
		# Stage 2: Scene tree path
		var tree = get_tree()
		if tree:
			var node = tree.get_node_or_null("/root/AnalysisSystem")
			if node:
				return node
			
			# Stage 3: Group discovery
			var grp = tree.get_first_node_in_group("analysis_system")
			if grp:
				if grp.has_method("get_analysis_system_instance"):
					return grp.get_analysis_system_instance()
				if grp.has_method("get_instance"):
					return grp.get_instance()
				return grp
		
		return null
	
	func _initialize_system() -> void:
		_log("Analysis system found and connected")
		system_ready.emit()
	
	func _handle_dependency_timeout() -> void:
		_log("Warning: Analysis system not found after " + str(_retry_attempts) + " attempts")
		dependency_failed.emit("Analysis system not found")
	
	# =============================================================================
	# EVENT HANDLERS
	# =============================================================================
	
	func _on_input_submitted(text: String) -> void:
		if text.ends_with(".gd"):
			_analyze_script_path(text)
		else:
			_log("Please enter a valid .gd script path")
	
	func _analyze_script() -> void:
		var script_path = input_field.text
		if script_path.is_empty():
			_log("Please enter a script path")
			return
		_analyze_script_path(script_path)
	
	func _analyze_script_path(script_path: String) -> void:
		if not analysis_system:
			_log("Error: Analysis system not available")
			return
		
		_log("Analyzing: " + script_path)
		var analysis = analysis_system.analyze_script(script_path)
		
		if analysis.has("error") and not analysis.error.is_empty():
			_log("Error: " + analysis.error)
			return
		
		_log("=== Analysis Results ===")
		_log("Class: " + analysis.get("class_name", "unnamed"))
		_log("Methods: " + str(analysis.methods.size()))
		_log("Properties: " + str(analysis.properties.size()))
		_log("Signals: " + str(analysis.signals.size()))
		
		if analysis_system.has_method("analyze_code_quality"):
			var quality = analysis_system.analyze_code_quality(script_path)
			_log("Quality Score: " + str(quality.complexity_score))
			_log("Maintainability: " + str(quality.maintainability_score))
	
	func _show_diagnostics() -> void:
		if not analysis_system:
			_log("Error: Analysis system not available")
			return
		
		if not analysis_system.has_method("run_diagnostics"):
			_log("Error: Analysis system does not support diagnostics")
			return
		
		var diagnostics = analysis_system.run_diagnostics()
		_log("=== System Diagnostics ===")
		
		var core_info = diagnostics.get("core_info", {})
		_log("Dependencies Ready: " + str(core_info.get("dependencies_ready", false)))
		_log("Cached Files: " + str(core_info.get("analysis_cache_size", 0)))
		_log("Injectable Objects: " + str(core_info.get("injection_registry_size", 0)))
		
		var file_monitoring = diagnostics.get("file_monitoring", {})
		_log("File Monitoring: " + str(file_monitoring.get("enabled", false)))
		_log("Tracked Files: " + str(file_monitoring.get("tracked_files", 0)))
	
	func _log(message: String) -> void:
		if output_label:
			output_label.append_text(message + "\n")

# =============================================================================
# USAGE EXAMPLES
# =============================================================================

static func get_usage_examples() -> Dictionary:
	"""Get comprehensive usage examples for different scenarios"""
	return {
		"basic_integration": {
			"description": "Basic integration with existing GoatBus",
			"code": """
# In your main script or autoload
var goat_bus = GoatBus.new()
var analysis_system = GoatBusAnalysisIntegration.setup_analysis_system(goat_bus)

# Analyze a script
var analysis = analysis_system.analyze_script("res://player/player.gd")
print("Player script has %d methods" % analysis.methods.size())

# Get EventObjects for creating events
var event_objects = analysis_system.get_injectable_object("EventObjects")
if event_objects and event_objects.has_method("SystemHealthUpdate"):
	var health_event = event_objects.SystemHealthUpdate.new("player", "healthy", 0.95)
	goat_bus.publish("system_health_updated", health_event.to_dict())
"""
		},
		"scene_tree_integration": {
			"description": "Integration via scene tree with automatic discovery",
			"code": """
# In your _ready() method
func _ready() -> void:
	var analysis_wrapper = GoatBusAnalysisIntegration.create_analysis_wrapper_node()
	add_child(analysis_wrapper)
	
	# Wait for system ready
	await analysis_wrapper.system_ready
	
	# System is now ready for use
	var autocomplete = analysis_wrapper.get_autocomplete_data()
	print("Autocomplete categories: ", autocomplete.keys())
"""
		},
		"development_console": {
			"description": "Development console with analysis features",
			"code": """
# Create development console
extends Control

var analysis_system: GoatBusAnalysisWrapper

func _ready() -> void:
	analysis_system = get_tree().get_first_node_in_group("analysis_system")
	if analysis_system:
		_setup_analysis_features()

func _setup_analysis_features() -> void:
	var analyze_button = Button.new()
	analyze_button.text = "Analyze Current Script"
	analyze_button.pressed.connect(_analyze_current_script)
	add_child(analyze_button)

func _analyze_current_script() -> void:
	var script_path = get_current_editor_script_path()
	var analysis = analysis_system.analyze_script(script_path)
	display_analysis_results(analysis)
"""
		}
	}

# =============================================================================
# LOGGING
# =============================================================================

static func log_debug(msg: String) -> void:
	print("[GoatBusAnalysisIntegration DEBUG] " + msg)

static func log_warn(msg: String) -> void:
	print("[GoatBusAnalysisIntegration WARN] " + msg)

static func log_error(msg: String) -> void:
	print("[GoatBusAnalysisIntegration ERROR] " + msg)
