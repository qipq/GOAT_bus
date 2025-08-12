# =============================================================================
# GOATBUS ANALYSIS CONFIGURATION
# =============================================================================
# Configuration constants and event schema definitions for GoatBus analysis system
# Provides centralized configuration management and environment-specific settings
# =============================================================================

@tool
extends RefCounted
class_name GoatBusAnalysisConfig

# =============================================================================
# CONSTANTS & MANIFEST
# =============================================================================

const VERSION := "1.0.0"
const MANIFEST := {
	"script_name": "GoatBusAnalysisConfig",
	"script_path": "res://systems/analysis/goatbus_analysis_config.gd",
	"class_name": "GoatBusAnalysisConfig",
	"version": "1.0.0",
	"description": "Configuration constants and event schema definitions for GoatBus analysis system performance and behavior tuning",
	"required_dependencies": [],
	"optional_dependencies": [],
	"features": [
		"performance_configuration", "behavior_tuning", "event_schema_definitions",
		"cache_management_settings", "retry_configuration", "threshold_definitions",
		"environment_configs", "feature_flags", "logging_configuration"
	],
	"signals": {},
	"variables": [],
	"entry_points": [
		"get_default_config", "get_config_for_environment", 
		"apply_config_to_system", "get_event_schema"
	],
	"api_version": "goatbus-analysis-config-v1.0.0",
	"last_updated": "2025-08-09",
	"compliance": {
		"core_system_blueprint": "v1.2",
		"syntax_guide": "v1.2",
		"configuration_pattern": true
	}
}

# =============================================================================
# DEFAULT CONFIGURATION
# =============================================================================

static func get_default_config() -> Dictionary:
	"""Create default configuration for analysis system"""
	return {
		"analysis_system": {
			"auto_scan_project": true,
			"auto_inject": true,
			"cache_size_limit": 1000,
			"file_watch_interval": 1.0,
			"generate_usage_examples": false,
			"include_private_methods": true,
			"scan_on_startup": true,
			"retry_max_attempts": 30,
			"retry_base_delay_ms": 250,
			"retry_backoff_factor": 1.5
		},
		"file_watcher": {
			"enabled": true,
			"poll_interval": 1.0,
			"watch_extensions": [".gd"],
			"recursive": true,
			"ignore_hidden": true,
			"ignore_patterns": ["*.tmp", "*.temp", "*~", ".#*"]
		},
		"autocomplete": {
			"enabled": true,
			"cache_duration": 300,
			"include_examples": true,
			"include_patterns": true,
			"max_suggestions": 100
		},
		"performance": {
			"analysis_warning_ms": 1000,
			"analysis_error_ms": 5000,
			"autocomplete_warning_ms": 100,
			"injection_warning_ms": 50,
			"cache_access_warning_ms": 10
		},
		"logging": {
			"level": "debug",
			"prefix": "[AnalysisSystem]",
			"include_timestamps": false,
			"colored_output": false
		}
	}

# =============================================================================
# ENVIRONMENT-SPECIFIC CONFIGURATIONS
# =============================================================================

static func get_config_for_environment(environment: String) -> Dictionary:
	"""Get configuration optimized for specific environment"""
	var base_config = get_default_config()
	
	match environment:
		"development":
			base_config.logging.level = "debug"
			base_config.file_watcher.poll_interval = 0.5
			base_config.analysis_system.cache_size_limit = 500
			base_config.analysis_system.generate_usage_examples = true
			base_config.autocomplete.include_examples = true
			base_config.performance.analysis_warning_ms = 500
		
		"production":
			base_config.logging.level = "warn"
			base_config.file_watcher.poll_interval = 2.0
			base_config.analysis_system.cache_size_limit = 2000
			base_config.analysis_system.generate_usage_examples = false
			base_config.autocomplete.include_examples = false
			base_config.performance.analysis_warning_ms = 2000
		
		"testing":
			base_config.logging.level = "error"
			base_config.file_watcher.poll_interval = 0.1
			base_config.analysis_system.cache_size_limit = 100
			base_config.analysis_system.auto_scan_project = false
			base_config.analysis_system.retry_max_attempts = 5
			base_config.performance.analysis_warning_ms = 100
	
	return base_config

# =============================================================================
# CONFIGURATION APPLICATION
# =============================================================================

static func apply_config_to_system(analysis_system: GoatBusAnalysisWrapper, config: Dictionary) -> void:
	"""Apply configuration dictionary to analysis system"""
	log_debug("Applying configuration to analysis system")
	
	var analysis_config = config.get("analysis_system", {})
	var file_watcher_config = config.get("file_watcher", {})
	
	# Apply analysis system config
	if analysis_config.has("auto_scan_project"):
		if analysis_system.has_method("set_auto_scan_enabled"):
			analysis_system.set_auto_scan_enabled(analysis_config.auto_scan_project)
	
	if analysis_config.has("auto_inject"):
		if analysis_system.has_method("set_auto_inject_enabled"):
			analysis_system.set_auto_inject_enabled(analysis_config.auto_inject)
	
	# Apply file watcher config
	if file_watcher_config.has("poll_interval"):
		if analysis_system.has_method("set_file_watch_interval"):
			analysis_system.set_file_watch_interval(file_watcher_config.poll_interval)
	
	if file_watcher_config.has("watch_extensions"):
		for extension in file_watcher_config.watch_extensions:
			if analysis_system.has_method("add_watched_file_extension"):
				analysis_system.add_watched_file_extension(extension)
	
	log_debug("Configuration applied successfully")

static func merge_config(base_config: Dictionary, override_config: Dictionary) -> Dictionary:
	"""Merge configuration dictionaries with override precedence"""
	var merged_config = base_config.duplicate(true)
	
	for key in override_config:
		if merged_config.has(key) and merged_config[key] is Dictionary and override_config[key] is Dictionary:
			merged_config[key] = merge_config(merged_config[key], override_config[key])
		else:
			merged_config[key] = override_config[key]
	
	return merged_config

static func validate_config(config: Dictionary) -> Dictionary:
	"""Validate configuration dictionary against expected schema"""
	var validation = {
		"valid": true,
		"errors": [],
		"warnings": []
	}
	
	# Validate analysis config
	if config.has("analysis_system"):
		var analysis_validation = _validate_analysis_config(config.analysis_system)
		validation.errors.append_array(analysis_validation.errors)
		validation.warnings.append_array(analysis_validation.warnings)
		if not analysis_validation.valid:
			validation.valid = false
	
	# Validate file watcher config
	if config.has("file_watcher"):
		var watcher_validation = _validate_file_watcher_config(config.file_watcher)
		validation.errors.append_array(watcher_validation.errors)
		validation.warnings.append_array(watcher_validation.warnings)
		if not watcher_validation.valid:
			validation.valid = false
	
	return validation

static func _validate_analysis_config(config: Dictionary) -> Dictionary:
	var validation = {"valid": true, "errors": [], "warnings": []}
	
	if config.get("cache_size_limit", 0) < 100:
		validation.warnings.append("Analysis cache size is very small, may impact performance")
	if config.get("cache_size_limit", 0) > 10000:
		validation.warnings.append("Analysis cache size is very large, may impact memory usage")
	
	if config.get("retry_max_attempts", 0) < 5:
		validation.warnings.append("Low retry attempts may cause dependency discovery failures")
	if config.get("retry_base_delay_ms", 0) < 100:
		validation.warnings.append("Very short retry delay may cause excessive polling")
	
	return validation

static func _validate_file_watcher_config(config: Dictionary) -> Dictionary:
	var validation = {"valid": true, "errors": [], "warnings": []}
	
	if config.get("poll_interval", 0) < 0.1:
		validation.warnings.append("Very short polling interval may impact performance")
	if config.get("poll_interval", 0) > 5.0:
		validation.warnings.append("Long polling interval may delay change detection")
	
	return validation

# =============================================================================
# EVENT SCHEMA DEFINITIONS
# =============================================================================

static func get_event_schema() -> Dictionary:
	"""Get event schema definitions for GoatBus integration"""
	return {
		"version": "1.0.0",
		"events": {
			"script_analysis_requested": {
				"required_fields": ["script_path"],
				"optional_fields": ["options", "requester_id"],
				"description": "Request analysis of a specific script file",
				"example": {
					"script_path": "res://player/player.gd",
					"options": {"generate_usage": true},
					"requester_id": "development_console"
				}
			},
			"script_analysis_response": {
				"fields": ["requester_id", "script_path", "analysis_result", "timestamp"],
				"description": "Response containing script analysis results",
				"example": {
					"requester_id": "development_console",
					"script_path": "res://player/player.gd",
					"analysis_result": {"methods": [], "properties": []},
					"timestamp": 1691596800.0
				}
			},
			"object_injection_requested": {
				"required_fields": ["object_name"],
				"optional_fields": ["requester_id"],
				"description": "Request an injectable object by name",
				"example": {
					"object_name": "EventObjects",
					"requester_id": "runtime_system"
				}
			},
			"object_injection_response": {
				"fields": ["requester_id", "object_name", "object_instance", "success", "timestamp"],
				"description": "Response containing requested object instance",
				"example": {
					"requester_id": "runtime_system",
					"object_name": "EventObjects",
					"object_instance": {},
					"success": true,
					"timestamp": 1691596800.0
				}
			},
			"autocomplete_data_requested": {
				"optional_fields": ["category", "requester_id"],
				"description": "Request autocomplete data for development tools",
				"example": {
					"category": "event_objects",
					"requester_id": "ide_plugin"
				}
			},
			"autocomplete_data_response": {
				"fields": ["requester_id", "category", "autocomplete_data", "timestamp"],
				"description": "Response containing autocomplete data",
				"example": {
					"requester_id": "ide_plugin",
					"category": "event_objects",
					"autocomplete_data": {"complex_events": {}, "simple_events": {}},
					"timestamp": 1691596800.0
				}
			},
			"project_scan_completed": {
				"fields": ["files_scanned", "files_analyzed", "duration_ms", "timestamp"],
				"description": "Published when automatic project scan completes",
				"example": {
					"files_scanned": 150,
					"files_analyzed": 145,
					"duration_ms": 2500.0,
					"timestamp": 1691596800.0
				}
			},
			"script_file_changed": {
				"fields": ["file_path", "auto_injected", "timestamp"],
				"description": "Published when a script file is modified",
				"example": {
					"file_path": "res://systems/player.gd",
					"auto_injected": true,
					"timestamp": 1691596800.0
				}
			},
			"auto_injection_completed": {
				"fields": ["injected_objects", "timestamp"],
				"description": "Published when auto-injection process completes",
				"example": {
					"injected_objects": ["EventObjects", "ScriptAnalyzer"],
					"timestamp": 1691596800.0
				}
			}
		}
	}

# =============================================================================
# FEATURE FLAGS
# =============================================================================

static func get_feature_flags() -> Dictionary:
	"""Get feature flags for experimental and optional functionality"""
	return {
		"experimental_features": {
			"advanced_caching": false,
			"predictive_analysis": false,
			"ml_code_quality": false,
			"async_batch_processing": false
		},
		"optional_features": {
			"development_console": true,
			"performance_overlay": false,
			"diagnostic_ui": false,
			"hot_reload_validation": true,
			"auto_code_formatting": false
		},
		"integration_features": {
			"editor_plugin_support": false,
			"external_tool_integration": false,
			"remote_analysis": false,
			"collaborative_features": false
		}
	}

static func apply_feature_flags(config: Dictionary, flags: Dictionary) -> Dictionary:
	"""Apply feature flags to configuration"""
	var updated_config = config.duplicate(true)
	
	# Apply experimental features
	if flags.has("experimental_features"):
		for feature in flags.experimental_features:
			if not flags.experimental_features[feature]:
				_disable_experimental_feature(updated_config, feature)
	
	# Apply optional features
	if flags.has("optional_features"):
		for feature in flags.optional_features:
			if not flags.optional_features[feature]:
				_disable_optional_feature(updated_config, feature)
	
	return updated_config

static func _disable_experimental_feature(config: Dictionary, feature: String) -> void:
	"""Disable specific experimental feature in configuration"""
	match feature:
		"advanced_caching":
			if config.has("analysis_system"):
				config.analysis_system["cache_size_limit"] = 100
		"predictive_analysis":
			if config.has("analysis_system"):
				config.analysis_system["predictive_enabled"] = false
		"async_batch_processing":
			if config.has("analysis_system"):
				config.analysis_system["batch_processing"] = false

static func _disable_optional_feature(config: Dictionary, feature: String) -> void:
	"""Disable specific optional feature in configuration"""
	match feature:
		"development_console":
			if config.has("development_tools"):
				config.development_tools["enable_console"] = false
		"performance_overlay":
			if config.has("development_tools"):
				config.development_tools["show_performance_overlay"] = false
		"hot_reload_validation":
			if config.has("file_watcher"):
				config.file_watcher["hot_reload_support"] = false

# =============================================================================
# PERFORMANCE THRESHOLDS
# =============================================================================

static func get_performance_thresholds() -> Dictionary:
	"""Get performance threshold definitions"""
	return {
		"analysis_times": {
			"warning_ms": 1000,
			"error_ms": 5000,
			"critical_ms": 10000
		},
		"injection_times": {
			"warning_ms": 50,
			"error_ms": 200,
			"critical_ms": 500
		},
		"autocomplete_times": {
			"warning_ms": 100,
			"error_ms": 500,
			"critical_ms": 1000
		},
		"cache_sizes": {
			"warning_count": 1000,
			"error_count": 2000,
			"critical_count": 5000
		},
		"memory_usage": {
			"warning_kb": 10000,
			"error_kb": 50000,
			"critical_kb": 100000
		}
	}

# =============================================================================
# CACHE MANAGEMENT SETTINGS
# =============================================================================

static func get_cache_settings() -> Dictionary:
	"""Get cache management configuration"""
	return {
		"analysis_cache": {
			"max_size": 1000,
			"cleanup_threshold": 1200,
			"entry_ttl_ms": 300000,  # 5 minutes
			"cleanup_interval_ms": 60000  # 1 minute
		},
		"project_files_cache": {
			"max_size": 2000,
			"cleanup_threshold": 2400,
			"entry_ttl_ms": 600000,  # 10 minutes
			"cleanup_interval_ms": 120000  # 2 minutes
		},
		"autocomplete_cache": {
			"max_size": 100,
			"cleanup_threshold": 120,
			"entry_ttl_ms": 300000,  # 5 minutes
			"cleanup_interval_ms": 300000  # 5 minutes
		},
		"injection_registry": {
			"max_size": 500,
			"allow_overwrites": true,
			"validate_on_register": true
		}
	}

# =============================================================================
# LOGGING CONFIGURATION
# =============================================================================

static func get_logging_config() -> Dictionary:
	"""Get logging configuration options"""
	return {
		"log_levels": {
			"debug": true,
			"info": true,
			"warn": true,
			"error": true
		},
		"component_logging": {
			"analysis_core": true,
			"file_watcher": true,
			"wrapper": true,
			"integration": true,
			"diagnostic": true
		},
		"output_settings": {
			"use_prefixes": true,
			"include_timestamps": false,
			"colored_output": false,
			"log_to_file": false,
			"max_log_file_size_mb": 10
		},
		"filters": {
			"exclude_patterns": [],
			"include_only_patterns": [],
			"min_log_level": "debug"
		}
	}

# =============================================================================
# RETRY CONFIGURATION
# =============================================================================

static func get_retry_config() -> Dictionary:
	"""Get dependency discovery retry configuration"""
	return {
		"dependency_discovery": {
			"max_attempts": 30,
			"base_delay_ms": 250,
			"backoff_factor": 1.5,
			"max_delay_ms": 10000,
			"timeout_ms": 30000
		},
		"file_operations": {
			"max_attempts": 3,
			"base_delay_ms": 100,
			"backoff_factor": 2.0,
			"max_delay_ms": 1000
		},
		"network_operations": {
			"max_attempts": 5,
			"base_delay_ms": 1000,
			"backoff_factor": 2.0,
			"max_delay_ms": 30000
		}
	}

# =============================================================================
# INTEGRATION SETTINGS
# =============================================================================

static func get_integration_settings() -> Dictionary:
	"""Get GoatBus integration configuration"""
	return {
		"event_bus": {
			"auto_discovery_enabled": true,
			"fallback_mode_enabled": true,
			"subscription_timeout_ms": 5000,
			"publish_timeout_ms": 1000
		},
		"scene_tree": {
			"auto_add_to_tree": false,
			"default_parent_path": "/root",
			"node_name": "GoatBusAnalysisSystem",
			"groups": ["analysis_system", "goatbus_integration"]
		},
		"autoload": {
			"singleton_name": "AnalysisSystem",
			"enable_singleton": false,
			"priority": 100
		},
		"manual_setup": {
			"require_explicit_injection": false,
			"validate_dependencies": true,
			"warn_on_missing_deps": true
		}
	}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

static func get_all_config() -> Dictionary:
	"""Get complete configuration as single dictionary"""
	return {
		"default": get_default_config(),
		"event_schema": get_event_schema(),
		"feature_flags": get_feature_flags(),
		"performance_thresholds": get_performance_thresholds(),
		"cache_settings": get_cache_settings(),
		"logging_config": get_logging_config(),
		"retry_config": get_retry_config(),
		"integration_settings": get_integration_settings()
	}

static func get_config_summary() -> Dictionary:
	"""Get summary of all configuration options"""
	return {
		"version": VERSION,
		"total_configs": 8,
		"config_categories": [
			"default", "event_schema", "feature_flags", "performance_thresholds",
			"cache_settings", "logging_config", "retry_config", "integration_settings"
		],
		"environment_presets": ["development", "production", "testing"],
		"feature_count": get_feature_flags().experimental_features.size() + get_feature_flags().optional_features.size(),
		"event_types": get_event_schema().events.size()
	}

static func print_config_documentation() -> void:
	"""Print complete configuration documentation to console"""
	print("=== GOATBUS ANALYSIS SYSTEM CONFIGURATION ===")
	print("Version: " + VERSION)
	print("")
	
	print("DEFAULT CONFIG:")
	print("  - Analysis system settings and auto-scan configuration")
	print("  - File watcher polling and monitoring settings")
	print("  - Autocomplete generation and caching options")
	print("")
	
	print("ENVIRONMENT CONFIGS:")
	print("  - Development: Debug logging, fast polling, usage examples")
	print("  - Production: Warn logging, slow polling, optimized caching")
	print("  - Testing: Error logging, minimal cache, disabled auto-scan")
	print("")
	
	print("EVENT SCHEMA:")
	print("  - " + str(get_event_schema().events.size()) + " event type definitions")
	print("  - Request/response patterns with examples")
	print("  - Field specifications and validation rules")
	print("")
	
	print("FEATURE FLAGS:")
	print("  - Experimental features for advanced functionality")
	print("  - Optional features for development tools")
	print("  - Integration features for external tool support")
	print("")
	
	print("Use get_config_for_environment() for environment-specific settings")
	print("Use apply_config_to_system() to apply configuration to running system")

# =============================================================================
# LOGGING
# =============================================================================

static func log_debug(msg: String) -> void:
	var logging_config = get_logging_config()
	if logging_config.log_levels.debug:
		print("[GoatBusAnalysisConfig DEBUG] " + msg)

static func log_warn(msg: String) -> void:
	var logging_config = get_logging_config()
	if logging_config.log_levels.warn:
		print("[GoatBusAnalysisConfig WARN] " + msg)

static func log_error(msg: String) -> void:
	var logging_config = get_logging_config()
	if logging_config.log_levels.error:
		print("[GoatBusAnalysisConfig ERROR] " + msg)
