class_name ItemData
extends Resource


@export_category("Basic Information")
@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""


@export_category("Visual")
@export var icon: Texture2D


@export_category("Inventory")
@export var size: Vector2i = Vector2i(1, 1)
@export var max_stack: int = 1


@export_category("Economy")
@export var buy_price: int = 0
@export var sell_price: int = 0
