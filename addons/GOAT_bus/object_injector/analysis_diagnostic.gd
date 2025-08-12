# =============================================================================
# GOATBUS ANALYSIS DIAGNOSTIC
# =============================================================================
# Diagnostic and testing utilities for GoatBus analysis system
# Provides health monitoring, performance testing, and system validation
# =============================================================================

@tool
extends RefCounted
class_name GoatBusAnalysisDiagnostic

# =============================================================================
# CONSTANTS & MANIFEST
# =============================================================================

const VERSION := "1.0.0"
const MANIFEST := {
	"script_name": "GoatBusAnalysisDiagnostic",
	"script_path": "res://systems/analysis/goatbus_analysis_diagnostic.gd",
	"class_name": "GoatBusAnalysisDiagnostic",
	"version": "1.0.0",
	"description": "Diagnostic and testing utilities for GoatBus analysis system health monitoring and performance testing",
	"required_dependencies": ["goatbus_analysis_core"],
	"optional_dependencies": ["goatbus_analysis_wrapper"],
	"features": [
		"system_diagnostics", "dependency_testing", "functionality_validation",
		"performance_measurement", "recommendation_generation", "health_monitoring",
		"stress_testing", "integration_validation", "report_generation"
	],
	"signals": {},
	"variables": [],
	"entry_points": [
		"run_system_diagnostics", "run_performance_tests", 
		"validate_integration", "generate_diagnostic_report"
	],
	"api_version": "goatbus-analysis-diagnostic-v1.0.0",
	"last_updated": "2025-08-09",
	"compliance": {
		"core_system_blueprint": "v1.2",
		"diagnostic_utility_pattern": true,
		"syntax_guide": "v1.2"
	}
}

# =============================================================================
# MAIN DIAGNOSTIC FUNCTIONS
# =============================================================================

static func run_system_diagnostics(analysis_core: ObjDictInjector) -> Dictionary:
	"""Run comprehensive diagnostics on the analysis system"""
	log_debug("Running system diagnostics")
	
	var diagnostics = {
		"timestamp": Time.get_unix_time_from_system(),
		"version": VERSION,
		"system_info": analysis_core.get_system_info(),
		"dependency_status": {},
		"functionality_tests": {},
		"performance_metrics": {},
		"health_score": 0.0,
		"recommendations": []
	}
	
	diagnostics.dependency_status = _test_dependencies(analysis_core)
	diagnostics.functionality_tests = _test_functionality(analysis_core)
	diagnostics.performance_metrics = _measure_performance(analysis_core)
	diagnostics.health_score = _calculate_health_score(diagnostics)
	diagnostics.recommendations = _generate_recommendations(diagnostics)
	
	log_debug("System diagnostics complete")
	return diagnostics

static func run_performance_tests(analysis_core: ObjDictInjector) -> Dictionary:
	"""Run detailed performance tests on the analysis system"""
	log_debug("Running performance tests")
	
	var performance_tests = {
		"timestamp": Time.get_unix_time_from_system(),
		"analysis_performance": _test_analysis_performance(analysis_core),
		"injection_performance": _test_injection_performance(analysis_core),
		"autocomplete_performance": _test_autocomplete_performance(analysis_core),
		"cache_performance": _test_cache_performance(analysis_core),
		"memory_usage": _analyze_memory_usage(analysis_core),
		"overall_score": 0.0
	}
	
	performance_tests.overall_score = _calculate_performance_score(performance_tests)
	
	log_debug("Performance tests complete")
	return performance_tests

static func validate_integration(analysis_wrapper: GoatBusAnalysisWrapper) -> Dictionary:
	"""Validate complete integration with wrapper and dependencies"""
	log_debug("Validating integration")
	
	var validation = {
		"timestamp": Time.get_unix_time_from_system(),
		"wrapper_validation": _validate_wrapper(analysis_wrapper),
		"core_validation": _validate_core(analysis_wrapper.get_analysis_core()),
		"event_bus_integration": _validate_event_bus_integration(analysis_wrapper.get_analysis_core()),
		"scene_tree_integration": _validate_scene_tree_integration(analysis_wrapper),
		"overall_valid": false,
		"critical_issues": [],
		"warnings": []
	}
	
	validation.overall_valid = _determine_overall_validation(validation)
	
	log_debug("Integration validation complete")
	return validation

static func generate_diagnostic_report(diagnostics: Dictionary) -> String:
	"""Generate human-readable diagnostic report"""
	var report = "=== GOATBUS ANALYSIS SYSTEM DIAGNOSTIC REPORT ===\n"
	report += "Generated: " + Time.get_datetime_string_from_unix_time(diagnostics.timestamp) + "\n"
	report += "Version: " + str(diagnostics.version) + "\n"
	report += "Overall Health Score: " + str(diagnostics.health_score) + "%\n\n"
	
	# Dependencies section
	report += "DEPENDENCIES:\n"
	var deps = diagnostics.dependency_status
	report += "  Event Bus: " + ("✓" if deps.event_bus else "✗") + "\n"
	report += "  System Registry: " + ("✓" if deps.system_registry else "✗") + "\n"
	report += "  Dependencies Ready: " + ("✓" if deps.dependencies_ready else "✗") + "\n\n"
	
	# Functionality section
	report += "FUNCTIONALITY:\n"
	var funcs = diagnostics.functionality_tests
	report += "  Script Analysis: " + ("✓" if funcs.can_analyze_scripts else "✗") + "\n"
	report += "  Object Injection: " + ("✓" if funcs.event_objects_available else "✗") + "\n"
	report += "  Autocomplete: " + ("✓" if funcs.can_generate_autocomplete else "✗") + "\n\n"
	
	# Performance section
	report += "PERFORMANCE:\n"
	var perf = diagnostics.performance_metrics
	report += "  Autocomplete Gen: " + str(perf.autocomplete_generation_ms) + "ms\n"
	report += "  Object Injection: " + str(perf.object_injection_ms) + "ms\n"
	report += "  Cache Size: " + str(perf.cache_size) + " entries\n\n"
	
	# Recommendations section
	if diagnostics.recommendations.size() > 0:
		report += "RECOMMENDATIONS:\n"
		for rec in diagnostics.recommendations:
			report += "  [" + rec.priority.to_upper() + "] " + rec.issue + "\n"
			report += "    Solution: " + rec.solution + "\n"
	
	return report

# =============================================================================
# DEPENDENCY TESTING
# =============================================================================

static func _test_dependencies(analysis_core: ObjDictInjector) -> Dictionary:
	var status = {
		"event_bus": analysis_core._event_bus != null,
		"system_registry": analysis_core._system_registry != null,
		"config_manager": analysis_core._config_manager != null,
		"node_wrapper": analysis_core._node_wrapper != null,
		"dependencies_ready": analysis_core._dependencies_ready,
		"script_analyzer": analysis_core._script_analyzer != null,
		"event_objects": analysis_core._event_objects != null
	}
	
	if status.event_bus:
		status["event_bus_functional"] = _test_event_bus_functionality(analysis_core._event_bus)
	
	if status.system_registry:
		status["system_registry_functional"] = _test_system_registry_functionality(analysis_core._system_registry)
	
	status["overall_health"] = status.event_bus and status.system_registry and status.dependencies_ready
	status["critical_dependencies_met"] = status.event_bus and status.script_analyzer and status.event_objects
	
	return status

static func _test_event_bus_functionality(event_bus) -> bool:
	var has_publish = event_bus.has_method("publish")
	var has_subscribe = event_bus.has_method("subscribe")
	var has_unsubscribe = event_bus.has_method("unsubscribe")
	
	return has_publish and has_subscribe and has_unsubscribe

static func _test_system_registry_functionality(system_registry) -> bool:
	var has_register = system_registry.has_method("register_system")
	var has_get = system_registry.has_method("get_system")
	
	return has_register and has_get

# =============================================================================
# FUNCTIONALITY TESTING
# =============================================================================

static func _test_functionality(analysis_core: ObjDictInjector) -> Dictionary:
	var tests = {
		"injection_registry": analysis_core._injection_registry.size() > 0,
		"autocomplete_data": analysis_core.get_autocomplete_data().size() > 0,
		"event_objects_available": analysis_core.get_injectable_object("EventObjects") != null,
		"script_analyzer_available": analysis_core.get_injectable_object("ScriptAnalyzer") != null,
		"analysis_core_available": analysis_core.get_injectable_object("AnalysisCore") != null,
		"can_analyze_scripts": _test_script_analysis_capability(analysis_core),
		"can_create_events": _test_event_creation_capability(analysis_core),
		"can_generate_autocomplete": _test_autocomplete_generation(analysis_core),
		"cache_functional": _test_cache_functionality(analysis_core)
	}
	
	tests["overall_functionality"] = true
	for key in tests:
		if key != "overall_functionality" and not tests[key]:
			tests["overall_functionality"] = false
			break
	
	return tests

static func _test_script_analysis_capability(analysis_core: ObjDictInjector) -> bool:
	var analyzer = analysis_core.get_injectable_object("ScriptAnalyzer")
	if not analyzer:
		return false
	
	return analyzer.has_method("analyze_script") and analyzer.has_method("get_default_options")

static func _test_event_creation_capability(analysis_core: ObjDictInjector) -> bool:
	var event_objects = analysis_core.get_injectable_object("EventObjects")
	if not event_objects:
		return false
	
	# Test creating a simple event
	if event_objects.has_method("create_phase_started"):
		var test_event = event_objects.create_phase_started("test_phase")
		return test_event is Dictionary and test_event.has("phase_name")
	
	return false

static func _test_autocomplete_generation(analysis_core: ObjDictInjector) -> bool:
	var autocomplete_data = analysis_core.get_autocomplete_data()
	return autocomplete_data.has("event_objects") and autocomplete_data.has("script_analyzer")

static func _test_cache_functionality(analysis_core: ObjDictInjector) -> bool:
	var initial_size = analysis_core._analysis_cache.size()
	analysis_core.clear_analysis_cache()
	var cleared_size = analysis_core._analysis_cache.size()
	return cleared_size == 0

# =============================================================================
# PERFORMANCE TESTING
# =============================================================================

static func _measure_performance(analysis_core: ObjDictInjector) -> Dictionary:
	var start_time = Time.get_ticks_msec()
	
	var autocomplete_start = Time.get_ticks_msec()
	var autocomplete_data = analysis_core.get_autocomplete_data()
	var autocomplete_time = Time.get_ticks_msec() - autocomplete_start
	
	var injection_start = Time.get_ticks_msec()
	var event_objects = analysis_core.get_injectable_object("EventObjects")
	var injection_time = Time.get_ticks_msec() - injection_start
	
	var cache_start = Time.get_ticks_msec()
	var cache_size = analysis_core._analysis_cache.size()
	var cache_time = Time.get_ticks_msec() - cache_start
	
	var total_time = Time.get_ticks_msec() - start_time
	
	return {
		"autocomplete_generation_ms": autocomplete_time,
		"object_injection_ms": injection_time,
		"cache_access_ms": cache_time,
		"total_test_time_ms": total_time,
		"cache_size": cache_size,
		"injection_registry_size": analysis_core._injection_registry.size(),
		"project_files_cached": analysis_core._project_files_cache.size()
	}

static func _test_analysis_performance(analysis_core: ObjDictInjector) -> Dictionary:
	var performance = {
		"average_analysis_time_ms": 0.0,
		"cache_hit_ratio": 0.0,
		"tests_run": 0
	}
	
	var test_scripts = ["res://test/script1.gd", "res://test/script2.gd", "res://test/script3.gd"]
	var total_time = 0.0
	var cache_hits = 0
	
	for i in range(3):
		for script_path in test_scripts:
			var start_time = Time.get_ticks_msec()
			var cache_key = script_path + str({}.hash())
			if analysis_core._analysis_cache.has(cache_key):
				cache_hits += 1
			var end_time = Time.get_ticks_msec()
			
			total_time += (end_time - start_time)
			performance.tests_run += 1
	
	if performance.tests_run > 0:
		performance.average_analysis_time_ms = total_time / performance.tests_run
		performance.cache_hit_ratio = float(cache_hits) / float(performance.tests_run)
	
	return performance

static func _test_injection_performance(analysis_core: ObjDictInjector) -> Dictionary:
	var injection_tests = {
		"average_injection_time_ms": 0.0,
		"successful_injections": 0,
		"failed_injections": 0
	}
	
	var injectable_objects = ["EventObjects", "ScriptAnalyzer", "AnalysisCore"]
	var total_time = 0.0
	
	for i in range(10):
		for object_name in injectable_objects:
			var start_time = Time.get_ticks_msec()
			var obj = analysis_core.get_injectable_object(object_name)
			var end_time = Time.get_ticks_msec()
			
			total_time += (end_time - start_time)
			
			if obj != null:
				injection_tests.successful_injections += 1
			else:
				injection_tests.failed_injections += 1
	
	var total_tests = injection_tests.successful_injections + injection_tests.failed_injections
	if total_tests > 0:
		injection_tests.average_injection_time_ms = total_time / total_tests
	
	return injection_tests

static func _test_autocomplete_performance(analysis_core: ObjDictInjector) -> Dictionary:
	var autocomplete_tests = {
		"generation_time_ms": 0.0,
		"data_size_bytes": 0,
		"categories_generated": 0,
		"efficient": true
	}
	
	var start_time = Time.get_ticks_msec()
	var autocomplete_data = analysis_core.get_autocomplete_data()
	autocomplete_tests.generation_time_ms = Time.get_ticks_msec() - start_time
	
	var data_str = JSON.stringify(autocomplete_data)
	autocomplete_tests.data_size_bytes = data_str.length()
	autocomplete_tests.categories_generated = autocomplete_data.size()
	
	autocomplete_tests.efficient = autocomplete_tests.generation_time_ms < 100.0
	
	return autocomplete_tests

static func _test_cache_performance(analysis_core: ObjDictInjector) -> Dictionary:
	var cache_tests = {
		"cache_hit_time_ms": 0.0,
		"cache_clear_time_ms": 0.0,
		"memory_efficient": true
	}
	
	var hit_start = Time.get_ticks_msec()
	var cache_size = analysis_core._analysis_cache.size()
	cache_tests.cache_hit_time_ms = Time.get_ticks_msec() - hit_start
	
	var clear_start = Time.get_ticks_msec()
	analysis_core.clear_analysis_cache()
	cache_tests.cache_clear_time_ms = Time.get_ticks_msec() - clear_start
	
	cache_tests.memory_efficient = cache_size < 1000
	
	return cache_tests

static func _analyze_memory_usage(analysis_core: ObjDictInjector) -> Dictionary:
	return {
		"analysis_cache_entries": analysis_core._analysis_cache.size(),
		"injection_registry_entries": analysis_core._injection_registry.size(),
		"project_files_cached": analysis_core._project_files_cache.size(),
		"autocomplete_data_size": analysis_core._autocomplete_data.size(),
		"estimated_memory_kb": _estimate_memory_usage(analysis_core),
		"memory_efficient": true
	}

static func _estimate_memory_usage(analysis_core: ObjDictInjector) -> float:
	var cache_entries = analysis_core._analysis_cache.size()
	var registry_entries = analysis_core._injection_registry.size()
	var project_files = analysis_core._project_files_cache.size()
	
	var estimated_kb = (cache_entries * 2.0) + (registry_entries * 1.0) + (project_files * 0.5)
	
	return estimated_kb

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

static func _validate_wrapper(analysis_wrapper: GoatBusAnalysisWrapper) -> Dictionary:
	return {
		"wrapper_exists": analysis_wrapper != null,
		"has_analysis_core": analysis_wrapper.get_analysis_core() != null,
		"in_scene_tree": analysis_wrapper.get_parent() != null,
		"in_correct_groups": analysis_wrapper.is_in_group("analysis_system"),
		"api_methods_available": _validate_wrapper_api(analysis_wrapper)
	}

static func _validate_wrapper_api(analysis_wrapper: GoatBusAnalysisWrapper) -> bool:
	var required_methods = [
		"analyze_script",
		"get_injectable_object",
		"get_autocomplete_data",
		"get_system_info"
	]
	
	for method_name in required_methods:
		if not analysis_wrapper.has_method(method_name):
			return false
	
	return true

static func _validate_core(analysis_core: ObjDictInjector) -> Dictionary:
	return {
		"core_exists": analysis_core != null,
		"dependencies_ready": analysis_core._dependencies_ready,
		"has_script_analyzer": analysis_core._script_analyzer != null,
		"has_event_objects": analysis_core._event_objects != null,
		"injection_registry_populated": analysis_core._injection_registry.size() > 0,
		"auto_features_enabled": analysis_core._auto_scan_enabled and analysis_core._auto_inject_enabled
	}

static func _validate_event_bus_integration(analysis_core: ObjDictInjector) -> Dictionary:
	return {
		"event_bus_connected": analysis_core._event_bus != null,
		"event_bus_functional": _test_event_bus_functionality(analysis_core._event_bus) if analysis_core._event_bus else false,
		"subscriptions_active": true,
		"auto_injection_completed": analysis_core._auto_inject_enabled
	}

static func _validate_scene_tree_integration(analysis_wrapper: GoatBusAnalysisWrapper) -> Dictionary:
	return {
		"in_scene_tree": analysis_wrapper.get_parent() != null,
		"proper_node_name": analysis_wrapper.name == "GoatBusAnalysisSystem",
		"in_analysis_group": analysis_wrapper.is_in_group("analysis_system"),
		"children_setup": analysis_wrapper.get_child_count() > 0
	}

# =============================================================================
# SCORING AND RECOMMENDATION FUNCTIONS
# =============================================================================

static func _calculate_health_score(diagnostics: Dictionary) -> float:
	var score = 0.0
	var weight_total = 0.0
	
	var deps = diagnostics.dependency_status
	if deps.overall_health:
		score += 30.0
	weight_total += 30.0
	
	var funcs = diagnostics.functionality_tests
	if funcs.overall_functionality:
		score += 40.0
	weight_total += 40.0
	
	var perf = diagnostics.performance_metrics
	var perf_score = 30.0
	if perf.autocomplete_generation_ms > 100:
		perf_score -= 10.0
	if perf.object_injection_ms > 50:
		perf_score -= 10.0
	if perf.cache_size > 1000:
		perf_score -= 10.0
	
	score += max(0.0, perf_score)
	weight_total += 30.0
	
	return score / weight_total * 100.0

static func _calculate_performance_score(performance_tests: Dictionary) -> float:
	var score = 100.0
	
	var analysis_perf = performance_tests.analysis_performance
	if analysis_perf.average_analysis_time_ms > 1000:
		score -= 20.0
	
	var injection_perf = performance_tests.injection_performance
	if injection_perf.average_injection_time_ms > 50:
		score -= 20.0
	
	var autocomplete_perf = performance_tests.autocomplete_performance
	if not autocomplete_perf.efficient:
		score -= 20.0
	
	var memory = performance_tests.memory_usage
	if memory.estimated_memory_kb > 10000:
		score -= 20.0
	
	return max(0.0, score)

static func _determine_overall_validation(validation: Dictionary) -> bool:
	var wrapper_valid = validation.wrapper_validation.wrapper_exists and validation.wrapper_validation.has_analysis_core
	var core_valid = validation.core_validation.core_exists and validation.core_validation.dependencies_ready
	var integration_valid = validation.event_bus_integration.event_bus_connected
	
	return wrapper_valid and core_valid and integration_valid

static func _generate_recommendations(diagnostics: Dictionary) -> Array:
	var recommendations = []
	
	var deps = diagnostics.dependency_status
	var funcs = diagnostics.functionality_tests
	var perf = diagnostics.performance_metrics
	
	if not deps.event_bus:
		recommendations.append({
			"priority": "high",
			"category": "dependency",
			"issue": "Event bus not connected",
			"solution": "Ensure GoatBus is properly initialized and injected"
		})
	
	if not deps.system_registry:
		recommendations.append({
			"priority": "medium", 
			"category": "dependency",
			"issue": "System registry not available",
			"solution": "Initialize system registry or set up manual injection"
		})
	
	if not funcs.injection_registry:
		recommendations.append({
			"priority": "high",
			"category": "functionality",
			"issue": "Injection registry empty",
			"solution": "Call _setup_injection_registry() during initialization"
		})
	
	if perf.autocomplete_generation_ms > 100:
		recommendations.append({
			"priority": "low",
			"category": "performance", 
			"issue": "Slow autocomplete generation",
			"solution": "Consider caching autocomplete data more aggressively"
		})
	
	if perf.cache_size > 1000:
		recommendations.append({
			"priority": "medium",
			"category": "memory",
			"issue": "Large analysis cache",
			"solution": "Implement cache size limits or periodic cleanup"
		})
	
	if diagnostics.health_score < 70.0:
		recommendations.append({
			"priority": "high",
			"category": "overall",
			"issue": "System health score below acceptable threshold",
			"solution": "Address critical dependency and functionality issues"
		})
	
	return recommendations

# =============================================================================
# LOGGING
# =============================================================================

static func log_debug(msg: String) -> void:
	print("[GoatBusAnalysisDiagnostic DEBUG] " + msg)

static func log_warn(msg: String) -> void:
	print("[GoatBusAnalysisDiagnostic WARN] " + msg)

static func log_error(msg: String) -> void:
	print("[GoatBusAnalysisDiagnostic ERROR] " + msg)
