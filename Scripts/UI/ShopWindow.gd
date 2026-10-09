extends Panel


const SHOP_ITEM_ROW_SCENE = preload(
	"res://Scenes/Shop/ShopItemRow.tscn"
)


@onready var gold_label: Label = $MarginContainer/VBoxContainer/Header/GoldLabel

@onready var buy_list: VBoxContainer = $MarginContainer/VBoxContainer/Content/BuyPanel/VBoxContainer/BuyScroll/BuyList

@onready var sell_list: VBoxContainer = $MarginContainer/VBoxContainer/Content/SellPanel/VBoxContainer/SellScroll/SellList

@onready var close_button: Button = $MarginContainer/VBoxContainer/CloseCenter/CloseButton


var shop_items: Array[ItemData] = [
	preload("res://Data/Items/health_potion.tres"),
	preload("res://Data/Items/iron_sword.tres")
]


func _ready() -> void:
	if not GameState.state_changed.is_connected(refresh):
		GameState.state_changed.connect(refresh)

	refresh()


func refresh() -> void:
	refresh_gold()
	refresh_buy_list()
	refresh_sell_list()


func refresh_gold() -> void:
	gold_label.text = "Gold: " + str(GameState.gold)


func refresh_buy_list() -> void:
	for child in buy_list.get_children():
		child.queue_free()


	for item_data in shop_items:
		var row = SHOP_ITEM_ROW_SCENE.instantiate()

		row.custom_minimum_size = Vector2(0, 90)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		buy_list.add_child(row)

		row.setup_buy(
			item_data,
			_on_buy_requested
		)


func refresh_sell_list() -> void:
	for child in sell_list.get_children():
		child.queue_free()


	for inventory_item in GameState.backpack.items:
		var row = SHOP_ITEM_ROW_SCENE.instantiate()

		row.custom_minimum_size = Vector2(0, 90)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		sell_list.add_child(row)

		row.setup_sell(
			inventory_item,
			_on_sell_requested
		)

func _on_buy_requested(row) -> void:
	if GameState.buy_item(row.item_data):
		print("Purchased: ", row.item_data.display_name)
	else:
		print("Purchase failed: ", row.item_data.display_name)


func _on_sell_requested(row) -> void:
	if row.inventory_item == null:
		return

	var item_name = row.inventory_item.item_data.display_name

	if GameState.sell_item(row.inventory_item):
		print("Sold: ", item_name)


func _on_close_button_pressed() -> void:
	hide()
