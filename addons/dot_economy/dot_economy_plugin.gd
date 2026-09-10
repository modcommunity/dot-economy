@tool
extends EditorPlugin

## Editor entry point for dot-economy. Registers inspector types only.
##
## No autoloads. A server and a mirroring client are two of these in one process, which
## is the arrangement every suite in this family runs — and a server hosting two matches
## is two economies that must not share a loss-bonus ladder.

const _ICON := "res://addons/dot_economy/icon_placeholder.svg"

const _TYPES := [
	[
		"DotEconomyManager",
		"Node",
		"res://addons/dot_economy/runtime/dot_economy_manager.gd",
	],
]


func _enter_tree() -> void:
	var icon: Texture2D = null
	if ResourceLoader.exists(_ICON):
		icon = load(_ICON) as Texture2D

	for entry in _TYPES:
		add_custom_type(entry[0], entry[1], load(entry[2]), icon)


func _exit_tree() -> void:
	for i in range(_TYPES.size() - 1, -1, -1):
		remove_custom_type(_TYPES[i][0])
