@tool
extends EditorPlugin

const PLUGIN_NAME = "GOAT_bus"
const GOAT_BUS_SCENE = "res://addons/GOAT_bus/GoatBusSystem.tscn"

func _enter_tree():
	print("🐐 GOAT_bus plugin loading...")
	
	# Add the main GoatBus scene as an autoload
	add_autoload_singleton("GoatBusSystem", GOAT_BUS_SCENE)
	
	print("✅ GOAT_bus plugin loaded successfully")
	print("   - GoatBusSystem autoload added")
	print("   - RefCounted classes available via ObjectInjectorNode")

func _exit_tree():
	print("🐐 GOAT_bus plugin unloading...")
	
	# Remove autoload
	remove_autoload_singleton("GoatBusSystem")
	
	print("✅ GOAT_bus plugin unloaded")

func get_plugin_name():
	return PLUGIN_NAME

func has_main_screen():
	return false

func get_plugin_icon():
	# You can add a custom icon here
	return EditorInterface.get_editor_theme().get_icon("Node", "EditorIcons")
