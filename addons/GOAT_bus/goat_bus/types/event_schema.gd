# ===== goat_bus/types/event_schema.gd =====
extends RefCounted
class_name EventSchema

const VERSION := "4.2.0.69"
const MANIFEST := {
	"script_name": "EventSchema",
	"script_path": "res://goat_bus/types/event_schema.gd",
	"class_name": "EventSchema",
	"version": "1.0.0",
	"description": "Event schema validation for GoatBus event system",
	"required_dependencies": [],
	"optional_dependencies": [],
	"features": ["type_validation", "duck_typing", "custom_class_support"],
	"api_version": "goatbus-v1.0.0",
	"last_updated": "2025-08-10"
}

# =============================================================================
# EVENT SCHEMA VALIDATION
# =============================================================================

var event_name: String
var required_fields: Array = []
var optional_fields: Array = []
var field_types: Dictionary = {}

func _init(name: String):
	event_name = name

func add_required_field(field_name: String, field_type: String = ""):
	if field_name not in required_fields:
		required_fields.append(field_name)
	if not field_type.is_empty():
		field_types[field_name] = field_type

func add_optional_field(field_name: String, field_type: String = ""):
	if field_name not in optional_fields:
		optional_fields.append(field_name)
	if not field_type.is_empty():
		field_types[field_name] = field_type

func validate(data: Dictionary) -> Dictionary:
	var result = {"is_valid": true, "errors": []}
	
	for field in required_fields:
		if not data.has(field):
			result.errors.append("Missing required field: " + field)
			result.is_valid = false
	
	for field in data:
		if field_types.has(field):
			var expected_type = field_types[field]
			var actual_value = data[field]
			if not _is_type_match(actual_value, expected_type):
				result.errors.append("Field '%s' expected %s, got %s" % [field, expected_type, typeof(actual_value)])
				result.is_valid = false
	
	return result

func _is_type_match(value, expected_type: String) -> bool:
	match expected_type.to_lower():
		"string": return value is String
		"int", "integer": return value is int
		"float": return value is float
		"bool", "boolean": return value is bool
		"array": return value is Array
		"dictionary", "dict": return value is Dictionary
		"vector2": return value is Vector2
		"vector3": return value is Vector3
		"node": return value is Node
		"resource": return value is Resource
		_:
			# Handle custom class_name checks
			if expected_type.begins_with("class:"):
				var class_name_check = expected_type.substr(6)
				return _check_custom_class(value, class_name_check)
			
			# Handle duck-typing interface checks
			if expected_type.begins_with("interface:"):
				var methods = expected_type.substr(10).split(",")
				return _check_duck_type_interface(value, methods)
			
			# Handle Resource subclass checks
			if expected_type.begins_with("resource:"):
				var resource_type = expected_type.substr(9)
				return value is Resource and value.get_class() == resource_type
			
			return true  # Unknown type, allow it

func _check_custom_class(value, class_name_param: String) -> bool:
	# Check if value matches custom class_name
	if not is_instance_valid(value):
		return false
	
	var script = value.get_script()
	if script and script.has_method("get_global_name"):
		return script.get_global_name() == class_name_param
	elif script:
		return script.get_path().get_file().get_basename() == class_name_param
	
	return false

func _check_duck_type_interface(value, methods: Array) -> bool:
	# Check if value implements required methods (duck typing)
	if not is_instance_valid(value):
		return false
	
	for method_name in methods:
		method_name = method_name.strip_edges()
		if not value.has_method(method_name):
			return false
	
	return true
